/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_example_zafeiris (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // All output pins must be assigned. If not used, assign to 0.
  // assign uo_out  = ui_in + uio_in;  // Example: ou_out is the sum of ui_in and uio_in
  // assign uio_out = 0;
  // assign uio_oe  = 0;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, 1'b0};

  // -------------- DECLARING ACKNOWLEDGMENT VALUES STORED IN ui_i[0] and ui_i[1] (reused) ---------------

  wire SRC_ack, DEST_ack;

  assign SRC_ack = ui_in[0];
  assign DEST_ack = ui_in[1]; 

  // --------------     END     -----------------------

  // Synchronizers

  reg SRC_ack_sync1, SRC_ack_sync2;

  always @(posedge clk or negedge rst_n)
  begin

    if (!rst_n)
    begin
      SRC_ack_sync1 <= 1'b0; // check this reset logic
      SRC_ack_sync2 <= 1'b0;
    end
    else
    begin
      SRC_ack_sync1 <= SRC_ack;
      SRC_ack_sync2 <= SRC_ack_sync1;
    end
  end

  reg DEST_ack_sync1, DEST_ack_sync2;

  always @(posedge clk or negedge rst_n)
  begin

    if (!rst_n)
    begin
      DEST_ack_sync1 <= 1'b0; // check this reset logic
      DEST_ack_sync2 <= 1'b0;
    end
    else
    begin
      DEST_ack_sync1 <= DEST_ack;
      DEST_ack_sync2 <= DEST_ack_sync1;
    end
  end

  reg fetch_sync2, fetch_sync1;

  always @(posedge clk or negedge rst_n)
  begin

    if (!rst_n)
    begin
      fetch_sync1 <= 1'b0; // check this reset logic
      fetch_sync2 <= 1'b0;
    end
    else
    begin
      fetch_sync1 <= fetch;
      fetch_sync2 <= fetch_sync1;
    end


  end

  always @(posedge clk or negedge rst_n)
  begin

    if (!rst_n)
      cnt <= 0;
    else if ((current_state == IDLE_PREPARATION && enable == 1) || (current_state == DELAY))
      cnt <= cnt + 1'b1;
    else
      cnt <= 0;

  end

  // Reg_file to hold source_addr and dest_addr

  reg [1:0] regs_for_addr [7:0];
  reg regs [1:0];

  reg [7:0] source_addr, dest_addr;

  reg [1:0] b4_config_address;
  reg data;
  reg [7:0] data2;

  reg [2:0] address1;
  reg address2;

  reg write, write2, write3; // Using this to change the regs data only when we want, else they are left with the last value

  reg [7:0] source_data;
  reg [7:0] regs_source_data;

  integer i;

  // regfile for addresses

  always @(posedge clk or negedge rst_n)
  begin

    if (!rst_n)
    begin

      for (i=0; i<8; i++)
        regs_for_addr[i] <= 2'b0;

    end
    else if (write)
    begin

      regs_for_addr[address1] <= b4_config_address;

    end
    else
    begin

      source_addr <= {regs_for_addr[3], regs_for_addr[2], regs_for_addr[1], regs_for_addr[0]};
      dest_addr <= {regs_for_addr[7], regs_for_addr[6], regs_for_addr[5], regs_for_addr[4]};

    end

  end

  // regfile for direction, BG and mode

  integer j;

  always @(posedge clk or negedge rst_n)
  begin

    if (!rst_n)
    begin

      for (j=0; j<2; j++)
        regs[j] <= 1'b0;

    end
    else if (write2)
    begin

      regs[address2] <= data; // address2 = 0 mode, 1 direction

    end
    else
    begin

      mode <= regs[0];
      direction <= regs[1];

    end

  end

  // regfile for source_data

  always @(posedge clk or negedge rst_n)
  begin

    if (!rst_n)
    begin

      regs_source_data <= 8'd0;

    end
    else if (write3)
    begin

      regs_source_data <= data2; // address2 = 0 mode, 1 direction, 2 source_data

    end
    else
    begin

      source_data <= regs_source_data;

    end

  end

  // Input registers 

  reg mode; // 0 single - 1 burst
  reg direction; // 0 memory --> io, 1 io --> memory
  wire fetch; // fetch/acknowledgement
  wire BG;
  wire enable;

  assign enable = ui_in[7];
  assign BG = ui_in[6];
  assign fetch = ui_in[5];

  // Output registers

  reg valid;
  reg done;
  reg WRITE_en;
  reg BR;
  // -- done with mode -- reg bus_dir; // same values as direction --> informs memory and io who is source and who destination (will be used in testbench)
  reg ack;

  // Output assignments

  wire bus_dir;
  assign bus_dir = direction;

  assign uo_out[0] = valid;
  assign uo_out[1] = WRITE_en;
  assign uo_out[2] = done;
  assign uo_out[3] = bus_dir; // bus_dir, same with direction
  assign uo_out[4] = ack;
  assign uo_out[5] = mode;
  assign uo_out[6] = BR;
  assign uo_out[7] = 0;


  // Data BUS

  reg [7:0] transfer_bus;
  assign uio_out = transfer_bus;

  // FSM 

  reg [3:0] current_state, next_state;

  reg [6:0] cnt;

  localparam IDLE_PREPARATION = 4'b000;
  localparam BUS_REQ = 4'b001;
  localparam DMA_to_SRC = 4'b010;
  localparam SRC_to_DMA = 4'b011;
  localparam DMA_to_DEST_addr = 4'b100;
  localparam DELAY = 4'b101;
  localparam DMA_to_DEST_data = 4'b110;
  localparam DONE = 4'b111;
  localparam ACKNOWLEDGMENT = 4'b1000;

  // Bidirectional bus

  assign uio_oe = ((current_state == DMA_to_SRC) || (current_state == DMA_to_DEST_data) || (current_state == DMA_to_DEST_addr)) ? 8'b1111_1111 : 8'b0000_0000; 

  // FSM implementation

  always @(posedge clk or negedge rst_n) 
  begin

    if (!rst_n)
      current_state <= IDLE_PREPARATION;
    else
      current_state <= next_state;
    
  end

  always @(current_state or enable or BG or fetch_sync2 or cnt or SRC_ack_sync2 or DEST_ack_sync2)
  begin

    case (current_state)
      
      IDLE_PREPARATION: if (enable && cnt == 8) next_state = BUS_REQ; else next_state = IDLE_PREPARATION;

      BUS_REQ         : if (BG) next_state = DMA_to_SRC; else next_state = BUS_REQ;

      DMA_to_SRC      : if (SRC_ack_sync2) next_state = SRC_to_DMA; else next_state = DMA_to_SRC;

      SRC_to_DMA      : if (fetch_sync2) next_state = ACKNOWLEDGMENT; else next_state = SRC_to_DMA;

      DMA_to_DEST_addr: if (DEST_ack_sync2) next_state = DELAY; else next_state = DMA_to_DEST_addr;

      DELAY           : if (!DEST_ack_sync2) next_state = DMA_to_DEST_data; else next_state = DELAY;  // Before: cnt == 100

      DMA_to_DEST_data: if (DEST_ack_sync2) next_state = DONE; else next_state = DMA_to_DEST_data;
      
      ACKNOWLEDGMENT  : if (!fetch_sync2) next_state = DMA_to_DEST_addr; else next_state = ACKNOWLEDGMENT; 

      DONE            : next_state = IDLE_PREPARATION;

      default         : next_state = IDLE_PREPARATION;


    endcase


  end

  always @(current_state or BG or fetch_sync2 or cnt)
  begin

    // Defaults

    write = 0;
    write2 = 0;
    write3 = 0;
    address1 = 0;
    address2 = 0;
    b4_config_address = 0;
    data = 0;
    data2 = 0;
    BR = 1'b0;
    valid = 1'd0;
    transfer_bus = 8'd0;
    WRITE_en = 0;
    ack = 0;
    done = 0;

    case (current_state)

      IDLE_PREPARATION      : //1st state
      begin

        if (enable)
        begin

          if (cnt == 1) // We enter the always because of enable so cnt=0 and cnt=1 write the same first value, so we need 8 cnt's to load 8 values
          begin

            // Indicate writing
            write = 1;
            write2 = 1;

            // Store the data in the proper regfile addresses 
            address1 = 3'd0; // first 2 bits of source address
            address2 = 1'd0; 

            // Get the input data
            data = ui_in[4]; // get mode
            b4_config_address = ui_in[3:2];
          
          end

          else if (cnt == 2)
          begin

            write = 1;
            write2 = 1;

            // Store the data in the proper regfile addresses 
            address1 = 3'd1; // second 2 bits of source address
            address2 = 1'd1; 

            // Get the input data
            data = ui_in[4]; // get direction
            b4_config_address = ui_in[3:2];            

          end

          else if (cnt == 3)
          begin

            write = 1;
            write2 = 0;

            // Store the data in the proper regfile addresses 
            address1 = 3'd2; // third 2 bits of dest address

            // Get the input data
            b4_config_address = ui_in[3:2];

          end

          else if (cnt == 4)
          begin

            write = 1;
            write2 = 0;

            // Store the data in the proper regfile addresses 
            address1 = 3'd3; // fourth 2 bits of dest address

            // Get the input data
            b4_config_address = ui_in[3:2];

          end

          else if (cnt == 5)
          begin

            write = 1;
            write2 = 0;

            // Store the data in the proper regfile addresses 
            address1 = 3'd4; // first 2 bits of dest address

            // Get the input data
            b4_config_address = ui_in[3:2];

          end

          else if (cnt == 6)
          begin

            write = 1;
            write2 = 0;

            // Store the data in the proper regfile addresses 
            address1 = 3'd5; // second 2 bits of dest address

            // Get the input data
            b4_config_address = ui_in[3:2];

          end

          else if (cnt == 7)
          begin

            write = 1;
            write2 = 0;

            // Store the data in the proper regfile addresses 
            address1 = 3'd6; // third 2 bits of dest address

            // Get the input data
            b4_config_address = ui_in[3:2];

          end

          else if (cnt == 8)
          begin

            write = 1;
            write2 = 0;

            // Store the data in the proper regfile addresses 
            address1 = 3'd7; // fourth 2 bits of dest address

            // Get the input data
            b4_config_address = ui_in[3:2];

          end
      
        end

      end

      BUS_REQ               : BR = 1'b1;  // 2nd state

      DMA_to_SRC            :
      begin

        transfer_bus = source_addr;
        valid = 1'd1;
        WRITE_en = 1'd0;
        BR = 1'b1;

      end

      SRC_to_DMA            :
      begin

        BR = 1'b1;

        if (fetch_sync2)
        begin

          data2 = uio_in; // Storing data in source_data
          write3 = 1;
          ack = 1;

        end
          

      end

      DMA_to_DEST_addr      :
      begin

        transfer_bus = dest_addr;
        valid = 1'd1;
        WRITE_en = 1'd1;
        BR = 1'b1;

      end

      DELAY                : begin valid = 0; BR = 1'b1; end // Sending for a bit more time that valid went low to indicate that the acknowledgment was successsfull

      ACKNOWLEDGMENT       : begin ack = 1; BR = 1'b1; end // This state ensures that we will inform that we got the data

      DMA_to_DEST_data     :
      begin

        transfer_bus = source_data;
        valid = 1'd1;
        WRITE_en = 1'd1;
        BR = 1'b1;

      end

      DONE                  : done = 1'd1;

      default               : done = 0;

    endcase
    

  end

endmodule
