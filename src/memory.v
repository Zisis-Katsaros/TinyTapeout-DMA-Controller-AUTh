`default_nettype none

module memory (output reg fetch, output reg MEM_ack, output reg [7:0] DMA_data_out, input wire [7:0] DMA_data_in, input [6:0] ins, input clk, input rst_n);

    wire BG, done, valid, WRITE_en, mode, direction, DMA_ack;

    assign valid = ins[0];
    assign WRITE_en = ins[1];
    assign done = ins[2];
    assign direction = ins[3];
    assign DMA_ack = ins[4];
    assign mode = ins[5];
    assign BG = ins[6];

    // -------- HANDLING THE BIDIRECTIONAL PORT -----------------

    // reg [7:0] data_out;
    // reg data_oe;   // output enable
    // wire [7:0] data_in;

    // assign data = data_oe ? data_out : 8'bz; // drive or high-Z
    // assign data_in = data;                   // read

    // ---------- END -----------------

    // ----------- SYNCHRONISERS ------------------

  reg valid_sync2, valid_sync1;

  always @(posedge clk or negedge rst_n)
  begin

    if (!rst_n)
    begin
      valid_sync1 <= 1'b0; // check this reset logic
      valid_sync2 <= 1'b0;
    end 
    else
    begin
      valid_sync1 <= valid;
      valid_sync2 <= valid_sync1;
    end

  end

  reg BG_sync2, BG_sync1;

  always @(posedge clk or negedge rst_n)
  begin

    if (!rst_n)
    begin
      BG_sync1 <= 1'b0; // check this reset logic
      BG_sync2 <= 1'b0;
    end 
    else
    begin
      BG_sync1 <= BG;
      BG_sync2 <= BG_sync1;
    end

  end

  reg done_sync2, done_sync1;

  always @(posedge clk or negedge rst_n)
  begin

    if (!rst_n)
    begin
      done_sync1 <= 1'b0; // check this reset logic
      done_sync2 <= 1'b0;
    end 
    else
    begin
      done_sync1 <= done;
      done_sync2 <= done_sync1;
    end

  end

  reg WRITE_en_sync2, WRITE_en_sync1;

  always @(posedge clk or negedge rst_n)
  begin

    if (!rst_n)
    begin
      WRITE_en_sync1 <= 1'b0; // check this reset logic
      WRITE_en_sync2 <= 1'b0;
    end 
    else
    begin
      WRITE_en_sync1 <= WRITE_en;
      WRITE_en_sync2 <= WRITE_en_sync1;
    end

  end

  reg mode_sync2, mode_sync1;

  always @(posedge clk or negedge rst_n)
  begin

    if (!rst_n)
    begin
      mode_sync1 <= 1'b0; // check this reset logic
      mode_sync2 <= 1'b0;
    end 
    else
    begin
      mode_sync1 <= mode;
      mode_sync2 <= mode_sync1;
    end

  end

  reg direction_sync2, direction_sync1;

  always @(posedge clk or negedge rst_n)
  begin

    if (!rst_n)
    begin
      direction_sync1 <= 1'b0; // check this reset logic
      direction_sync2 <= 1'b0;
    end 
    else
    begin
      direction_sync1 <= direction;
      direction_sync2 <= direction_sync1;
    end

  end

  reg DMA_ack_sync2, DMA_ack_sync1;

  always @(posedge clk or negedge rst_n)
  begin

    if (!rst_n)
    begin
      DMA_ack_sync1 <= 1'b0; // check this reset logic
      DMA_ack_sync2 <= 1'b0;
    end 
    else
    begin
      DMA_ack_sync1 <= DMA_ack;
      DMA_ack_sync2 <= DMA_ack_sync1;
    end

  end

//------------ END of synchroniserss --------------

    // memory regfile 

  reg [7:0] regfile_write_data, regfile_read_data, regfile_address;
  reg [7:0] regs [255:0];

  integer i;
  reg write;

  always @(posedge clk or negedge rst_n)
  begin

    if (!rst_n)
    begin

      for (i=0; i<256; i++)
        regs[i] = 8'd4;     // error for <=

    end
    else if (write)
    begin

      regs[regfile_address] <= regfile_write_data;

    end
    else
    begin

      regfile_read_data <= regs[regfile_address];

    end

  end

    // Destination address and data regfile

  reg [7:0] write_target_address, read_target_address, target_address;
  reg write2;

  always @(posedge clk or negedge rst_n)
  begin

    if (!rst_n)
    begin

      for (i=0; i<1; i++)
        target_address <= 8'b0;

    end
    else if (write2)
    begin

      target_address <= write_target_address;

    end
    else
    begin

      read_target_address <= target_address;

    end

  end

// ------  COUNTER ---------

  reg [4:0] cnt;

  always @(posedge clk or negedge rst_n)
  begin

    if (!rst_n)
      cnt <= 0;
    else if (current_state == SOURCE2)
      cnt <= cnt + 1'b1;
    else
      cnt <= 0;

  end

    // ---------- FSM -----------------

    localparam WAITING = 4'b000;
    localparam ROLE = 4'b001;
    localparam SOURCE1 = 4'b010;
    localparam SOURCE2 = 4'b011;
    localparam DESTINATION1 = 4'b100;
    localparam DESTINATION2 = 4'b101;
    localparam DONE_STATE = 4'b110;
    localparam ACKNOWLEDGMENT = 4'b111;
    localparam DEST2_ACKNOWLEDGMENT = 4'b1000;

    reg [3:0] current_state, next_state;

    always @(posedge clk or negedge rst_n)
    begin

        if (!rst_n)
            current_state <= WAITING;
        else
            current_state <= next_state;

    end

    always @(current_state or BG_sync2 or valid_sync2 or direction_sync2 or mode_sync2 or done_sync2 or WRITE_en_sync2 or DMA_ack_sync2)
    begin

        case (current_state)
        
            WAITING     : if (BG_sync2) next_state = ROLE; else next_state = WAITING; // if we took BG we took mode and direction as well, it is sent last

            ROLE        : if (!direction_sync2) next_state = SOURCE1; else if (direction_sync2) next_state = DESTINATION1; else next_state = ROLE;

            SOURCE1     : if (valid_sync2 && !WRITE_en_sync2) next_state = ACKNOWLEDGMENT; else next_state = SOURCE1;

            ACKNOWLEDGMENT : if (!valid_sync2 && !direction_sync2) next_state = SOURCE2; else if (!valid_sync2 && direction_sync2) next_state = DESTINATION2; else next_state = ACKNOWLEDGMENT;

            DEST2_ACKNOWLEDGMENT : if (!valid_sync2) next_state = DONE_STATE; else next_state = DEST2_ACKNOWLEDGMENT;

            SOURCE2     : if (DMA_ack_sync2) next_state = DONE_STATE; else next_state = SOURCE2;

            DESTINATION1: if (valid_sync2 && WRITE_en_sync2) next_state = ACKNOWLEDGMENT; else next_state = DESTINATION1;

            DESTINATION2: if (valid_sync2 && WRITE_en_sync2) next_state = DEST2_ACKNOWLEDGMENT; else next_state = DESTINATION2;

            DONE_STATE  : if (mode_sync2) next_state = SOURCE1; else if (done_sync2) next_state = WAITING; else next_state = DONE_STATE;

            default     : next_state = WAITING;

        endcase

    end

    always @(current_state or WRITE_en_sync2 or valid_sync2 or cnt)
    begin

        regfile_address = 0;
        write = 0;
        write2 = 0;
        MEM_ack = 0;
        fetch = 0;
        write_target_address = 0;
        regfile_write_data = 0;
        DMA_data_out = 0;
        // data_oe = 0;

        case (current_state)

            SOURCE1     : 
            begin

                if (valid_sync2 && !WRITE_en_sync2)
                begin

                    write_target_address = DMA_data_in; // we will have the data in
                    write2 = 1; 
                    MEM_ack = 1; // make this source acknowledgment

                end

            end

            SOURCE2     :
            begin

                // Send data from source address to DMA

                if (cnt == 0)
                    regfile_address = read_target_address;
                else
                begin
                    // data_oe = 1;
                    DMA_data_out = regfile_read_data;
                    fetch = 1;
                end

            end

            DESTINATION1:
            begin

                if (valid_sync2 && WRITE_en_sync2)
                begin

                    write_target_address = DMA_data_in;
                    write2 = 1;
                    MEM_ack = 1; // must become source_ack

                end

            end

            ACKNOWLEDGMENT  : MEM_ack = 1; // Sending ack until we are sure the DMA continues

            DEST2_ACKNOWLEDGMENT    : MEM_ack = 1;

            DESTINATION2:
            begin

                if (valid_sync2 && WRITE_en_sync2)
                begin
                    
                    regfile_write_data = DMA_data_in;
                    regfile_address = target_address;
                    write = 1;
                    MEM_ack = 1; // must become source_ack

                end

            end

            default     :  DMA_data_out = 0;

        endcase

    end


endmodule