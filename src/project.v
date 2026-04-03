/*
 * Copyright (c) 2026 Zisis Katsaros
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_auth_dmac (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // Inputs
    wire       enable;
    wire       BG;
    wire       rtrn;
    wire [4:0] cfg_in;

    // Internal output controls
    reg BR;
    reg WRITE_en;
    reg done;
    reg valid;
    reg transfer_drive;
    reg [7:0] transfer_bus_out;

    // Config and data registers
    reg mode;           // 0: single word, 1: 4-word burst
    reg direction;      // 0: mem -> io, 1: io -> mem
    reg [7:0] src_addr;
    reg [7:0] dst_addr;
    reg [7:0] data_buffer;
    reg [1:0] prep_cntr;
    reg src_send_cntr;
    reg dst_addr_cntr;
    reg dst_data_cntr;
    reg [1:0] words_left;

    // FSM state
    reg [2:0] current_state;
    reg [2:0] next_state;

    localparam [2:0] IDLE       = 3'b000;
    localparam [2:0] PREPERATION = 3'b001;
    localparam [2:0] WAIT4BG    = 3'b010;
    localparam [2:0] SRC_SEND   = 3'b011;
    localparam [2:0] RECEIVE    = 3'b100;
    localparam [2:0] SENDaddr   = 3'b101;
    localparam [2:0] SENDdata   = 3'b110;

    // 2FF synchronizers for CDC 
    reg rtrn_ff1, rtrn_ff2, rtrn_ff2_d;
    wire rtrn_sync;
    wire rtrn_rise;

    assign enable = ui_in[7];
    assign BG = ui_in[6];
    assign rtrn = ui_in[5];
    assign cfg_in = ui_in[4:0];

    assign uo_out[7] = BR;
    assign uo_out[6] = WRITE_en;
    assign uo_out[5] = done;
    assign uo_out[4] = valid;
    assign uo_out[3:0] = 4'b0000;

    assign uio_out = transfer_bus_out;
    assign uio_oe = {8{transfer_drive}};

    assign rtrn_sync = rtrn_ff2;
    assign rtrn_rise = rtrn_sync & ~rtrn_ff2_d;

    
    always @(posedge clk or negedge rst_n) begin: SEQUENTIAL_LOGIC
        if (!rst_n) begin
            // reset sync FFs
            rtrn_ff1 <= 1'b0;
            rtrn_ff2 <= 1'b0;
            rtrn_ff2_d <= 1'b0;

            // reset counters
            prep_cntr <= 2'b00;
            src_send_cntr <= 1'b0;
            dst_addr_cntr <= 1'b0;
            dst_data_cntr <= 1'b0;

            // reset internal regs
            mode <= 1'b0;
            direction <= 1'b0;
            src_addr <= 8'h00;
            dst_addr <= 8'h00;
            data_buffer <= 8'h00;
            words_left <= 2'b00;
            done <= 1'b0;

            // reset FSM state
            current_state <= IDLE;
        end 
        else begin
            // Update sync FFs
            rtrn_ff1 <= rtrn;
            rtrn_ff2 <= rtrn_ff1;
            rtrn_ff2_d <= rtrn_ff2;

            // Update FSM state
            current_state <= next_state;

            // State-specific sequential logic
            case (current_state)
                IDLE: begin
                    // reset counters
                    prep_cntr <= 2'b00; 
                    src_send_cntr <= 1'b0;
                    dst_addr_cntr <= 1'b0;
                    dst_data_cntr <= 1'b0;

                    done <= 1'b0;
                end
                PREPERATION: begin
                    case (prep_cntr) // preperation sequence
                        2'b00: begin
                            src_addr[3:0] <= cfg_in[3:0];
                            mode <= cfg_in[4];
                        end
                        2'b01: begin
                            src_addr[7:4] <= cfg_in[3:0];
                            direction <= cfg_in[4];
                        end
                        2'b10: begin
                            dst_addr[3:0] <= cfg_in[3:0];
                        end
                        2'b11: begin
                            dst_addr[7:4] <= cfg_in[3:0];
                            words_left <= mode ? 2'b11 : 2'b00;
                        end
                        default: begin
                        end
                    endcase

                    // update prep counter
                    if (prep_cntr != 2'b11) prep_cntr <= prep_cntr + 2'b01;
                end
                WAIT4BG: begin
                    src_send_cntr <= 1'b0;
                    dst_addr_cntr <= 1'b0;
                    dst_data_cntr <= 1'b0;
                end
                SRC_SEND: begin
                    dst_addr_cntr <= 1'b0;
                    dst_data_cntr <= 1'b0;

                    // update src_addr send counter
                    if (src_send_cntr == 1'b0) src_send_cntr <= 1'b1; 
                end
                RECEIVE: begin
                    src_send_cntr <= 1'b0;
                    dst_addr_cntr <= 1'b0;
                    dst_data_cntr <= 1'b0;

                    // capture data from transfer_bus
                    if (rtrn_rise) data_buffer <= uio_in; 
                end
                SENDaddr: begin
                    src_send_cntr <= 1'b0;
                    dst_data_cntr <= 1'b0;

                    // update dest_addr send counter
                    if (dst_addr_cntr == 1'b0) dst_addr_cntr <= 1'b1;
                    else if (rtrn_rise) dst_addr_cntr <= 1'b0;
                end
                SENDdata: begin
                    src_send_cntr <= 1'b0;
                    dst_addr_cntr <= 1'b0;

                    // update dest_data send counter
                    if (dst_data_cntr == 1'b0) dst_data_cntr <= 1'b1;
                    else if (rtrn_rise) begin
                        dst_data_cntr <= 1'b0;
                        if (words_left == 2'b0) done <= 1'b1; // send done if no more words left
                        else begin
                            words_left <= words_left - 2'b01; // decrement words left, increment addresses
                            src_addr <= src_addr + 8'h01;
                            dst_addr <= dst_addr + 8'h01;
                        end
                    end
                end
                default: begin
                    src_send_cntr <= 1'b0;
                    dst_addr_cntr <= 1'b0;
                    dst_data_cntr <= 1'b0;
                end
            endcase
        end
    end

    always @(*) begin: NEXT_STATE_LOGIC
        next_state = current_state;

        case (current_state)
            IDLE: begin
              if (enable) next_state = PREPERATION;
            end
            PREPERATION: begin
                if (prep_cntr == 2'b11) next_state = WAIT4BG;
            end
            WAIT4BG: begin
                if (BG) next_state = SRC_SEND;
            end
            SRC_SEND: begin
                if(src_send_cntr == 1'b1) next_state = RECEIVE;
            end
            RECEIVE: begin
                if (rtrn_rise) next_state = SENDaddr;
            end
            SENDaddr: begin
                if ((dst_addr_cntr == 1'b1) && rtrn_rise) begin
                    next_state = SENDdata;
                end
            end
            SENDdata: begin
                if ((dst_data_cntr == 1'b1) && rtrn_rise) begin
                    if (words_left == 2'b00) next_state = IDLE; // move to idle if no more words left
                    else next_state = SRC_SEND; // else go back to src_send
                end
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end
  
    always @(*) begin: OUTPUT_LOGIC
        BR = 1'b0;
        WRITE_en = 1'b0;
        valid = 1'b0;
        transfer_drive = 1'b0;
        transfer_bus_out = 8'h00;

        case (current_state)
            IDLE: begin
            end
            PREPERATION: begin
            end
            WAIT4BG: begin
                BR = 1'b1; // send BR to CPU
            end
            SRC_SEND: begin
                BR = 1'b1;
                WRITE_en = 1'b0;
                transfer_drive = 1'b1; // set bidir to output
                transfer_bus_out = src_addr;

                // after one cycle send valid
                if(src_send_cntr == 1'b1) valid = 1'b1; 
            end
            RECEIVE: begin
                BR = 1'b1;
                WRITE_en = 1'b0;
                transfer_drive = 1'b0; // set bidir to input
            end
            SENDaddr: begin
                BR = 1'b1;
                WRITE_en = 1'b1;
                transfer_drive = 1'b1; // set bidir to output
                transfer_bus_out = dst_addr;

                // after one cycle send valid
                if (dst_addr_cntr == 1'b1) valid = 1'b1;
            end
            SENDdata: begin
                BR = 1'b1;
                WRITE_en = 1'b1;
                transfer_drive = 1'b1; // set bidir to output
                transfer_bus_out = data_buffer;

                // after one cycle send valid
                if (dst_data_cntr == 1'b1) valid = 1'b1;
            end
            default: begin
            end
        endcase
    end

    // Prevent unused warning for currently unconsumed mode bits.
    wire _unused_ok = &{ena, direction, 1'b0};

endmodule
