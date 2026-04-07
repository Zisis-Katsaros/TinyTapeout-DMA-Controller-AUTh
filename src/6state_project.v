/*
 * Copyright (c) 2024 Spyridon Vasileiou
 * SPDX-License-Identifier: Apache-2.0
 */


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
    wire transfer_bus_oe;

    // Outputs
    wire done;
    wire BR;
    wire valid;
    wire write_en;
    wire bus_dir;
    wire ack;

    dma_6_state dma_inst (
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

    assign uo_out = {2'b00, ack, bus_dir, valid, done, write_en, BR};

    assign uio_out = transfer_bus_out;
    assign uio_oe = transfer_bus_oe ? 8'hFF : 8'h00;

    // prevent warnings
    wire _unused = &{ena, 1'b0};

endmodule


module dma_6_state(
    // Standard signals
    input wire clk,
    input wire rst_n,
    input wire enable,

    // Configuration input (same clock domain as DMA)
    input wire [3:0] cfg_in, //So I changed config. I instead made it 4 bit. On the first cycle I load the direction and the mode. And then load the 8 bit addresses spliting each address in 2

    // Cross-domain handshake from external side.
    // IMPORTANT I CHANGED THIS!!!:
    //   - treat this as a LEVEL handshake, not a short pulse.
    //   - when DMA presents valid data/address, external raises external_capture=1 to signify it got it
    //     and keeps it high until DMA drops valid.
    //   - when external drives data to DMA, external raises fetch=1
    //     while holding transfer_bus_in stable.
    //     DMA send ack =1 when it captures it
    //     When external receives the ack it drop fetch to 0
    input wire fetch,
    input wire external_capture,
    output reg ack,
    output reg valid,// This signal is how the DMA says that it is driving a valid address/data byte on transfer_bus_out

    // Bus request/grant with CPU-side logic (same clock domain)
    output reg BR, //Bus request
    input wire BG, //Bus grant

    // Status
    output reg done, 
    output reg write_en,
    output reg bus_dir, //Because we have the same addresses for I/O and memory, we tae the direction bit of the input and have it as output

    // Bidirectinal bus to the external side on a diffenrt time domain
    input wire [7:0] transfer_bus_in,
    output reg  [7:0] transfer_bus_out,
    output reg transfer_bus_oe

);

    // ============================================================
    // Internal registers
    // ============================================================

    reg [7:0] src_addr;
    reg [7:0] dst_addr;
    reg [7:0] data_reg;

    //Registers to svae teh values of mode and direction, because we need to use the rest of the bits in the config bus
    reg mode_reg;  // 0 = single transfer, 1 = 4-word burst
    reg direction_reg;  // source selector 

    reg [2:0] cycle_count;    // config loading counter
    reg phase;   // handshake microstep counter withing states S2,S3,S4,S5 to propErly handle the handshakes between time domains in just two states

    // New siganl to tackle the problem of enable neing high for mor ethan one cycle would cause the state machine to start a new transfer
    //Turns it was a bug not a feature..
    // Because we might start a transfer when we shoudn't
    reg wait_enable_low;

    reg [2:0] words_left;   // enough for values 0..4 because I need the 0 bit to signify we are done not just 0-3 

    // ============================================================
    // Synchronize fetch and external_capture into clk domain
    // ============================================================

    reg fetch_ff1, fetch_ff2;
    wire fetch_sync;

    assign fetch_sync = fetch_ff2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fetch_ff1 <= 1'b0;
            fetch_ff2 <= 1'b0;
        end else begin
            fetch_ff1 <= fetch;
            fetch_ff2 <= fetch_ff1;
        end
    end


    reg external_capture_ff1, external_capture_ff2;
    wire external_capture_sync;

    assign external_capture_sync = external_capture_ff2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            external_capture_ff1 <= 1'b0;
            external_capture_ff2 <= 1'b0;
        end else begin
            external_capture_ff1 <= external_capture;
            external_capture_ff2 <= external_capture_ff1;
        end
    end

    // ============================================================
    // State encoding (6 top-level states only)
    // ============================================================

    localparam S0_IDLE_AND_LOAD = 3'b000;
    localparam S1_BUS_ACCESS = 3'b001;
    localparam S2_SEND_SRC_ADDR = 3'b010;
    localparam S3_RECEIVE_DATA_FROM_SRC_ADDR = 3'b011;
    localparam S4_SEND_DEST_ADDR = 3'b100;
    localparam S5_SEND_DATA_TO_DEST_ADDR = 3'b101;

    reg [2:0] state;

    // ============================================================
    // Main sequential logic
    // ============================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S0_IDLE_AND_LOAD;
            src_addr <= 8'b00000000;
            dst_addr <= 8'b00000000;
            data_reg <= 8'b00000000;
            mode_reg <= 1'b0;
            direction_reg <= 1'b0;

            cycle_count <= 3'b000;
            phase <= 1'b0;
            wait_enable_low  <= 1'b0;
            words_left <= 3'd0;

            transfer_bus_out <= 8'h00;
            transfer_bus_oe <= 1'b0;

            BR <= 1'b0;
            valid <= 1'b0;
            ack <= 1'b0;
            done <= 1'b0;
            write_en <= 1'b0;
            bus_dir <= 1'b0;

        end else begin

            // Defaults each cycle
            BR <= 1'b0;
            valid <= 1'b0;
            ack <= 1'b0;
            write_en <= 1'b0;
            transfer_bus_oe <= 1'b0;

            case (state)

                // ====================================================
                // S0_IDLE_AND_LOAD
                // Collect 5 config chunks over 5 cycles while enable=1.
                // On the first cycle it is just the mode and reg
                // On the other 4 it is the 8 bit source and destination addresses split up 
                // Requires enable to go low between different word transfers.
                // if enable drops in the middle of config loading, 
                // I abort the partially loaded command
                // ====================================================
                S0_IDLE_AND_LOAD: begin
                    phase <= 1'b0;
                    bus_dir <= 1'b0;

                    if (!enable) begin
                        cycle_count <= 3'b000;
                        wait_enable_low <= 1'b0;
                        words_left <= 3'd0;
                    end else if (!wait_enable_low) begin
                        case (cycle_count)
                            3'b000: begin
                                //I am using this cycle just to load the direction and the mode, so I can then have a cleaner ptocol with loading the addresses
                                done <= 1'b0;   // clear done when new command starts
                                mode_reg <= cfg_in[3];
                                direction_reg <= cfg_in[2];
                                //cfg[1:0] are unused here
                                cycle_count <= 3'b001;
                            end

                            3'b001: begin
                                src_addr[7:4] <= cfg_in;
                                cycle_count <= 3'b010;

                            end

                            3'b010: begin
                                src_addr[3:0] <= cfg_in;
                                cycle_count <= 3'b011;
                            end

                            3'b011: begin
                                dst_addr[7:4] <= cfg_in;
                                cycle_count <= 3'b100;
                            end

                            3'b100: begin
                                dst_addr[3:0] <= cfg_in;
                                cycle_count <= 3'b000;
                                state <= S1_BUS_ACCESS;
                                wait_enable_low <= 1'b1;

                                if (mode_reg)
                                    words_left <= 3'd4;   // burst mode
                                else
                                    words_left <= 3'd1;   // single transfer
                            end
                            default: begin
                                cycle_count <= 3'b000;
                            end

                        endcase
                    end
                end

                // ====================================================
                // S1_BUS_ACCESS
                //
                // Request the bus, wait for grant.
                // ====================================================
                S1_BUS_ACCESS: begin //I skipped the  else state <= S1_BUS_ACCESS, no need since it will stay here until it gets the bus granted
                    BR <= 1'b1;
                    if (BG) begin
                        state <= S2_SEND_SRC_ADDR;
                        phase <= 1'b0;
                    end
                end

                // ====================================================
                // S2_SEND_SRC_ADDR
                //
                // phase 0:
                //   Drive source address, valid=1, wait external_capture_sync=1
                //
                // phase 1:
                //   Drop valid, release bus,  wait external_capture_sync=0
                // ====================================================
                S2_SEND_SRC_ADDR: begin
                    BR <= 1'b1;
                    bus_dir <= direction_reg;
                    write_en <= 1'b0;

                    if (!phase) begin 
                        transfer_bus_out <= src_addr;
                        transfer_bus_oe <= 1'b1;
                        valid <= 1'b1;

                        if (external_capture_sync) begin // The xetrnal side got
                            phase <= 1'b1;
                        end
                    end else begin
                        // Drop valid so external side can release external_capture since it alreay got the data
                        transfer_bus_oe <= 1'b0;
                        valid <= 1'b0;

                        if (!external_capture_sync) begin
                            phase <= 1'b0;
                            state <= S3_RECEIVE_DATA_FROM_SRC_ADDR;
                        end
                    end
                end

                //=======================================================================
                // S3_RECEIVE_DATA_FROM_SRC_ADDR
                //
                // phase = 0:
                //    Wait for external side to drive read data and assert fetch=1 
                //    wait for fetch high and capture data
                // phase = 1: 
                //    hold ack high until fetch returns low, 
                //    which will mean the capturing window is over, 
                //    and we move to the next state
                //=======================================================================

                S3_RECEIVE_DATA_FROM_SRC_ADDR: begin
                    BR <= 1'b1;
                    bus_dir <= direction_reg;
                    valid <= 1'b0;
                    transfer_bus_oe <= 1'b0;
                    write_en <= 1'b0;

                    if (!phase) begin
                        ack <= 1'b0; //This isn't needed here since I put on default as well But I am keeping to show the handshake matters from this stage

                        if (fetch_sync) begin
                            data_reg <= transfer_bus_in;
                            phase <= 1'b1;
                            //ack <= 1'b1;
                        end
                    end else begin
                        //Give acknowldge that we got the data
                        ack <= 1'b1; //This will give ack with one clock delay at least instead of just putting above where the comment is

                        if (!fetch_sync) begin
                            phase <= 1'b0;
                            ack <= 1'b0; // not really needed since I have it as default, but I am putting it just to clarify this  handshake is done
                            state <= S4_SEND_DEST_ADDR;
                        end
                    end
                end



                // ====================================================
                // S4_SEND_DEST_ADDR
                //
                // phase 0:
                //   Drive destination address, valid=1, wait external_capture_sync=1
                //
                // phase 1:
                //   Drop valid, wait external_capture_sync=0
                //
                // ====================================================
                S4_SEND_DEST_ADDR: begin
                    BR <= 1'b1;
                    bus_dir <= !direction_reg;
                    write_en <= 1'b0;

                    if (!phase) begin
                        transfer_bus_out <= dst_addr;
                        transfer_bus_oe <= 1'b1;
                        valid <= 1'b1;

                        if (external_capture_sync) begin
                            phase <= 1'b1;
                        end
                    end else begin
                        transfer_bus_oe <= 1'b0;
                        valid <= 1'b0;

                        if (!external_capture_sync) begin
                            phase <= 1'b0;
                            state <= S5_SEND_DATA_TO_DEST_ADDR;
                        end
                    end

                end


                //====================================================
                // S5_SEND_DATA_TO_DEST_ADDR
                // 
                // phase 0:
                //   Drive write data, valid=1, write_en=1, wait external_capture_sync=1
                //
                // phase 1:
                //   Drop valid, wait external_capture_sync=0 : 
                //     - either pulse done, return to idle
                //     - or decrement words_left, increment addresses, loop back to S3_SEND_SRC_ADDR
                // ====================================================

                S5_SEND_DATA_TO_DEST_ADDR: begin
                    BR <= 1'b1;
                    bus_dir <= !direction_reg;

                    if (!phase) begin
                        transfer_bus_out <= data_reg;
                        transfer_bus_oe <= 1'b1;
                        valid <= 1'b1;
                        write_en <= 1'b1;

                        if (external_capture_sync) begin
                            phase <= 1'b1;
                        end
                    end else begin
                        transfer_bus_oe <= 1'b0;
                        valid <= 1'b0;
                        write_en <= 1'b0;

                        if (!external_capture_sync) begin

                            if (words_left <= 3'd1) begin // with word's left I meanthe number of words remaing including the one being proccessed
                                // This was the last word
                                done <= 1'b1;
                                words_left <= 3'd0;
                                phase <= 1'b0;
                                state <= S0_IDLE_AND_LOAD;
                            end else begin
                                // More words remain in burst
                                words_left <= words_left - 3'd1;
                                src_addr <= src_addr + 8'd1;
                                dst_addr <= dst_addr + 8'd1;
                                phase <= 1'b0;
                                state <= S2_SEND_SRC_ADDR;
                            end
                        end
                    end

                end

                default: begin
                    state <= S0_IDLE_AND_LOAD;
                    //Just in case
                    phase <= 1'b0;
                    cycle_count <= 3'b000;
                end

            endcase
        end
    end

endmodule