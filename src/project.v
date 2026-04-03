/*
 * Copyright (c) 2024 Kyriakos Kokkinos
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_AUTH_DMA_CONTROLLER (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
  
  
  	reg BR;
    reg WRITE_en;
    reg done;
    reg valid;
    reg ALE;
    reg bus_dir;

    localparam IDLE = 3'b000;
    localparam CONFIGURATION = 3'b001;
  	localparam HANDSHAKE = 3'b010;	
    localparam DMA2SRC = 3'b011;	//Stelno stin mnimi ti thelo na paro
    localparam SENDING = 3'b100;

    reg [2:0] current_state, next_state;
    reg [2:0] counter;
    reg MODE ; //0 for single word transfer and 1 for burst mode
    reg direction; //0 for MEMORY -> IO write 1 for IO -> MEMORY  
    reg [2:0] words_left;
    reg [7:0] src_addr;
    reg [7:0] dest_addr;
    reg [7:0] data;
    reg [7:0] transfer_bus_out;
  
    //INPUTS
    wire BG;
    wire Enable;
    wire fetch;
  	wire [3:0] cfg_in;

  assign Enable = ui_in[7];
  assign BG = ui_in[6];
  assign fetch = ui_in[5];
  assign cfg_in = ui_in[3:0];


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            counter <= 3'b000;
          	src_addr <= 8'b00000000;
          	dest_addr <= 8'b00000000;
          	data <= 8'b00000000;
          	transfer_bus_out <= 8'b00000000;
        end 
        else begin
            current_state <= next_state;

          if (next_state != current_state || current_state==IDLE) begin
                counter <= 3'b000;
            end 
            else begin
                counter <= counter + 3'b001;
            end

          	//To ypoloipo sequential Logic
          case(current_state) 
            IDLE: begin
              if (Enable) begin
                src_addr[3:0] <= cfg_in;
                MODE <= ui_in[4];
            	end
              end 
              
             CONFIGURATION: begin
               if (counter == 0) begin
                 src_addr[7:4] <= cfg_in;
               end
               
               if (counter == 1) begin
                 dest_addr[3:0] <= cfg_in;
               end
               
               if (counter == 2) begin
                 dest_addr[7:4] <= cfg_in;
               end
             end
              

            endcase
          
        end
    end

    always @* begin: NEXT_STATE_LOGIC
        next_state = current_state;

        case (current_state)
            IDLE: begin
                if (Enable) begin
                    next_state = CONFIGURATION;
                end
            end

            CONFIGURATION: begin
              if (counter == 2)
                next_state = HANDSHAKE;
            end
          
            HANDSHAKE: begin
                if (BG)
                  next_state = DMA2SRC;
              end

            DMA2SRC: begin
               
            end

            SENDING: begin
               
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

    always @* begin: OUTPUT_LOGIC
        case (current_state)

            HANDSHAKE: begin
                BR = 1;    
            end
          
          	DMA2SRC: begin
                WRITE_en = 0;
              	valid = 1 ;
                bus_dir = 1;
              	transfer_bus_out = src_addr;
              	
            end
          
        endcase
    end

    assign uo_out = {2'b00, bus_dir, ALE, valid, done, WRITE_en, BR};
    assign uio_out = transfer_bus_out;
    assign uio_oe = bus_dir ? 8'hFF : 8'h00;

    wire _unused = &{ena, 1'b0};

endmodule
