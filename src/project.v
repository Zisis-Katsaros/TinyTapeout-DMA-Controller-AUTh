`default_nettype none

module tt_um_dma_controller (
    input  wire [7:0] ui_in,    // [5:0] cfg_in, [6] enable
    output wire [7:0] uo_out,   // [5:0] addr_bus
    input  wire [7:0] uio_in,   // [7] BG (Bus Grant)
    output wire [7:0] uio_out,  // [7] BR (Bus Request), [6:0] data_bus_out
    output wire [7:0] uio_oe,   // bidirectional pins
    input  wire       ena,      // Tiny Tapeout enable
    input  wire       clk,      
    input  wire       rst_n     
);

    wire enable = ui_in[6];
    wire [5:0] cfg_in = ui_in[5:0];
    wire bg = uio_in[7]; 

    reg br;                       
    reg write_en;                 
    reg [7:0] addr_bus;          
    reg [7:0] data_bus_out;
    reg       data_bus_oe;             
    reg [7:0] src_addr;
    reg [7:0] dest_addr;
    reg [7:0] internal_data;

    localparam S0_IDLE        = 2'b00;
    localparam S1_PREPARATION = 2'b01;
    localparam S2_TRANSACTION = 2'b10;
    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin 
            state         <= S0_IDLE;
            br            <= 1'b0;
            write_en      <= 1'b0;
            addr_bus      <= 8'h00;
            data_bus_out  <= 8'h00;
            data_bus_oe   <= 1'b0;
            src_addr      <= 8'h00;
            dest_addr     <= 8'h00;
            internal_data <= 8'h00;
        end else if (ena) begin
            case (state)
                S0_IDLE: begin
                    br          <= 1'b0;
                    write_en    <= 1'b0;
                    data_bus_oe <= 1'b0;
                    if (enable) begin
                        src_addr  <= {2'b00, cfg_in}; 
                        dest_addr <= 8'hFF; // Παράδειγμα προορισμού
                        state     <= S1_PREPARATION;
                    end
                end

                S1_PREPARATION: begin
                    br <= 1'b1; 
                    if (bg) begin 
                        state <= S2_TRANSACTION;
                    end
                end

                S2_TRANSACTION: begin
                    addr_bus      <= src_addr;
                    write_en      <= 1'b0; 
                    data_bus_oe   <= 1'b0; 
                    internal_data <= uio_in; 
                    addr_bus     <= dest_addr;
                    data_bus_out <= internal_data;
                    data_bus_oe  <= 1'b1; 
                    write_en     <= 1'b1;
                    
                    state <= S0_IDLE; 
                end

                default: state <= S0_IDLE;
            endcase
        end
    end
    
    // Οι διευθύνσεις βγαίνουν στα uo_out pins [5:0]
    assign uo_out = addr_bus[5:0]; 

    // Τα δεδομένα και το σήμα BR βγαίνουν στα uio_out pins
    assign uio_out[6:0] = data_bus_out[6:0]; 
    assign uio_out[7]   = br; 
    assign uio_oe = (state == S2_TRANSACTION && data_bus_oe) ? 8'hFF : 8'h80;

endmodule
