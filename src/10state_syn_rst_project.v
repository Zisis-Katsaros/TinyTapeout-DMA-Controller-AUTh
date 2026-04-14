`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // Inputs
    wire enable = ui_in[7];
    wire fetch = ui_in[6];
    wire external_capture = ui_in[5];
    wire BG = ui_in[4];
    wire [3:0] cfg_in = ui_in[3:0];

    // Bidirectional transfer bus control
    wire [7:0] transfer_bus_out;
    wire       transfer_bus_oe;

    // Outputs
    wire done;
    wire BR;
    wire valid;
    wire write_en;
    wire bus_dir;
    wire ack;

    dma_10_state dma_inst (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .cfg_in(cfg_in),
        .fetch(fetch),
        .external_capture(external_capture),
        .ack(ack),
        .valid(valid),
        .BR(BR),
        .BG(BG),
        .done(done),
        .write_en(write_en),
        .bus_dir(bus_dir),
        .transfer_bus_in(uio_in),
        .transfer_bus_out(transfer_bus_out),
        .transfer_bus_oe(transfer_bus_oe)
    );

    assign uo_out  = {2'b00, ack, bus_dir, valid, done, write_en, BR};
    assign uio_out = transfer_bus_out;
    assign uio_oe  = transfer_bus_oe ? 8'hFF : 8'h00;

    // prevent warnings
    wire _unused = &{ena, 1'b0};

endmodule


module dma_10_state(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       enable,
    input  wire [3:0] cfg_in,
    input  wire       fetch,
    input  wire       external_capture,
    output reg        ack,
    output reg        valid,
    output reg        BR,
    input  wire       BG,
    output reg        done,
    output reg        write_en,
    output reg        bus_dir,
    input  wire [7:0] transfer_bus_in,
    output reg  [7:0] transfer_bus_out,
    output reg        transfer_bus_oe
);

    // ============================================================
    // Internal registers
    // ============================================================
    reg [7:0] src_addr;
    reg [7:0] dst_addr;
    reg [7:0] data_reg;

    reg       mode_reg;       // 0 = single transfer, 1 = 4-word burst
    reg       direction_reg;

    reg [2:0] cycle_count;
    reg       wait_enable_low;
    reg [2:0] words_left;

    // ============================================================
    // Synchronizers (no async reset)
    // ============================================================
    reg fetch_ff1, fetch_ff2;
    wire fetch_sync = fetch_ff2;

    reg external_capture_ff1, external_capture_ff2;
    wire external_capture_sync = external_capture_ff2;

    always @(posedge clk) begin
        fetch_ff1 <= fetch;
        fetch_ff2 <= fetch_ff1;
    end

    always @(posedge clk) begin
        external_capture_ff1 <= external_capture;
        external_capture_ff2 <= external_capture_ff1;
    end

    // ============================================================
    // State encoding
    // ============================================================
    localparam S0_IDLE_AND_LOAD               = 4'b0000;
    localparam S1_BUS_ACCESS                  = 4'b0001;
    localparam S2A_SEND_SRC_ADDR_WAIT_CAPTURE = 4'b0010;
    localparam S2B_SEND_SRC_ADDR_WAIT_RELEASE = 4'b0011;
    localparam S3A_WAIT_FETCH                 = 4'b0100;
    localparam S3B_WAIT_FETCH_DROP            = 4'b0101;
    localparam S4A_SEND_DST_ADDR_WAIT_CAPTURE = 4'b0110;
    localparam S4B_SEND_DST_ADDR_WAIT_RELEASE = 4'b0111;
    localparam S5A_SEND_DATA_WAIT_CAPTURE     = 4'b1000;
    localparam S5B_SEND_DATA_WAIT_RELEASE     = 4'b1001;

    reg [3:0] state;

    // ============================================================
    // Datapath/config registers (no async reset)
    // These are only written when the FSM reaches the relevant states.
    // ============================================================
    always @(posedge clk) begin
        case (state)

            S0_IDLE_AND_LOAD: begin
                if (enable && !wait_enable_low) begin
                    case (cycle_count)
                        3'b000: begin
                            mode_reg      <= cfg_in[3];
                            direction_reg <= cfg_in[2];
                        end

                        3'b001: begin
                            src_addr[7:4] <= cfg_in;
                        end

                        3'b010: begin
                            src_addr[3:0] <= cfg_in;
                        end

                        3'b011: begin
                            dst_addr[7:4] <= cfg_in;
                        end

                        3'b100: begin
                            dst_addr[3:0] <= cfg_in;

                            if (mode_reg)
                                words_left <= 3'd4;
                            else
                                words_left <= 3'd1;
                        end

                        default: begin
                            // no datapath update
                        end
                    endcase
                end
            end

            S3A_WAIT_FETCH: begin
                if (fetch_sync) begin
                    data_reg <= transfer_bus_in;
                end
            end

            S5B_SEND_DATA_WAIT_RELEASE: begin
                if (!external_capture_sync) begin
                    if (words_left > 3'd1) begin
                        words_left <= words_left - 3'd1;
                        src_addr   <= src_addr + 8'd1;
                        dst_addr   <= dst_addr + 8'd1;
                    end else begin
                        words_left <= 3'd0;
                    end
                end
            end

            default: begin
                // no datapath change
            end
        endcase
    end

    // ============================================================
    // Control/state/output registers (keep async reset)
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S0_IDLE_AND_LOAD;
            cycle_count <= 3'b000;
            wait_enable_low <= 1'b0;

            BR <= 1'b0;
            valid <= 1'b0;
            ack <= 1'b0;
            done <= 1'b0;
            write_en <= 1'b0;
            bus_dir <= 1'b0;
            transfer_bus_oe <= 1'b0;

            // Optional: can be left unreset too, but keeping this is fine
            transfer_bus_out <= 8'h00;

        end else begin
            // defaults every cycle
            BR <= 1'b0;
            valid <= 1'b0;
            ack <= 1'b0;
            write_en <= 1'b0;
            transfer_bus_oe <= 1'b0;

            case (state)

                // ====================================================
                // S0_IDLE_AND_LOAD
                // ====================================================
                S0_IDLE_AND_LOAD: begin
                    bus_dir <= 1'b0;

                    if (!enable) begin
                        cycle_count <= 3'b000;
                        wait_enable_low <= 1'b0;
                    end else if (!wait_enable_low) begin
                        case (cycle_count)
                            3'b000: begin
                                done <= 1'b0;
                                cycle_count <= 3'b001;
                            end

                            3'b001: begin
                                cycle_count <= 3'b010;
                            end

                            3'b010: begin
                                cycle_count <= 3'b011;
                            end

                            3'b011: begin
                                cycle_count <= 3'b100;
                            end

                            3'b100: begin
                                cycle_count <= 3'b000;
                                state <= S1_BUS_ACCESS;
                                wait_enable_low <= 1'b1;
                            end

                            default: begin
                                cycle_count <= 3'b000;
                            end
                        endcase
                    end
                end

                // ====================================================
                // S1_BUS_ACCESS
                // ====================================================
                S1_BUS_ACCESS: begin
                    BR <= 1'b1;
                    if (BG) begin
                        state <= S2A_SEND_SRC_ADDR_WAIT_CAPTURE;
                    end
                end

                // ====================================================
                // S2A_SEND_SRC_ADDR_WAIT_CAPTURE
                // ====================================================
                S2A_SEND_SRC_ADDR_WAIT_CAPTURE: begin
                    BR <= 1'b1;
                    bus_dir <= direction_reg;

                    transfer_bus_out <= src_addr;
                    transfer_bus_oe <= 1'b1;
                    valid <= 1'b1;

                    if (external_capture_sync) begin
                        state <= S2B_SEND_SRC_ADDR_WAIT_RELEASE;
                    end
                end

                // ====================================================
                // S2B_SEND_SRC_ADDR_WAIT_RELEASE
                // ====================================================
                S2B_SEND_SRC_ADDR_WAIT_RELEASE: begin
                    BR <= 1'b1;
                    bus_dir <= direction_reg;

                    if (!external_capture_sync) begin
                        state <= S3A_WAIT_FETCH;
                    end
                end

                // ====================================================
                // S3A_WAIT_FETCH
                // ====================================================
                S3A_WAIT_FETCH: begin
                    BR <= 1'b1;
                    bus_dir <= direction_reg;

                    if (fetch_sync) begin
                        state <= S3B_WAIT_FETCH_DROP;
                    end
                end

                // ====================================================
                // S3B_WAIT_FETCH_DROP
                // ====================================================
                S3B_WAIT_FETCH_DROP: begin
                    BR <= 1'b1;
                    bus_dir <= direction_reg;
                    ack <= 1'b1;

                    if (!fetch_sync) begin
                        state <= S4A_SEND_DST_ADDR_WAIT_CAPTURE;
                    end
                end

                // ====================================================
                // S4A_SEND_DST_ADDR_WAIT_CAPTURE
                // ====================================================
                S4A_SEND_DST_ADDR_WAIT_CAPTURE: begin
                    BR <= 1'b1;
                    bus_dir <= !direction_reg;

                    transfer_bus_out <= dst_addr;
                    transfer_bus_oe <= 1'b1;
                    valid <= 1'b1;

                    if (external_capture_sync) begin
                        state <= S4B_SEND_DST_ADDR_WAIT_RELEASE;
                    end
                end

                // ====================================================
                // S4B_SEND_DST_ADDR_WAIT_RELEASE
                // ====================================================
                S4B_SEND_DST_ADDR_WAIT_RELEASE: begin
                    BR <= 1'b1;
                    bus_dir <= !direction_reg;

                    if (!external_capture_sync) begin
                        state <= S5A_SEND_DATA_WAIT_CAPTURE;
                    end
                end

                // ====================================================
                // S5A_SEND_DATA_WAIT_CAPTURE
                // ====================================================
                S5A_SEND_DATA_WAIT_CAPTURE: begin
                    BR <= 1'b1;
                    bus_dir <= !direction_reg;

                    transfer_bus_out <= data_reg;
                    transfer_bus_oe <= 1'b1;
                    valid <= 1'b1;
                    write_en <= 1'b1;

                    if (external_capture_sync) begin
                        state <= S5B_SEND_DATA_WAIT_RELEASE;
                    end
                end

                // ====================================================
                // S5B_SEND_DATA_WAIT_RELEASE
                // ====================================================
                S5B_SEND_DATA_WAIT_RELEASE: begin
                    BR <= 1'b1;
                    bus_dir <= !direction_reg;

                    if (!external_capture_sync) begin
                        if (words_left <= 3'd1) begin
                            done <= 1'b1;
                            state <= S0_IDLE_AND_LOAD;
                        end else begin
                            state <= S2A_SEND_SRC_ADDR_WAIT_CAPTURE;
                        end
                    end
                end

                default: begin
                    state <= S0_IDLE_AND_LOAD;
                    cycle_count <= 3'b000;
                    wait_enable_low <= 1'b0;
                end

            endcase
        end
    end

endmodule

`default_nettype wire