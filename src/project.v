/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);


    //Inputs Signals
    wire enable = ui_in[7];
    wire fetch = ui_in[6];
    wire BG = ui_in[5];
    wire [4:0] cfg_in = ui_in[4:0];

    //Bidirectional bus signals
    wire [7:0] transfer_bus_out;
    wire transfer_bus_oe;

    //output Signals
    wire done;
    wire BR;
    wire valid;
    wire write_en;
    wire bus_dir;

    dma_4_state dma_inst (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .cfg_in(cfg_in),
        .fetch(fetch),
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

    assign uo_out = {3'b000, bus_dir, valid, done, write_en, BR};


    // List all unused inputs to prevent warnings
    wire _unused = &{ena, 1'b0};

    assign uio_out = transfer_bus_out;
    assign uio_oe  = transfer_bus_oe ? 8'hFF : 8'h00;

endmodule

module dma_4_state(

    // standrd signals
    input wire clk,
    input wire rst_n,
    input wire enable,

    // Configuration bus 
    input wire [4:0] cfg_in,

    // SIgnlas for the data transfer between the two time domains
    input wire fetch, //this is the enable/ready signal that tells us the data from the other time domain is ready to be read
    // Asserted by the external side as a pulse to acknowledge the current handshake step.

    //A separate fetch pulse is required for each of these phases:

    //source address accepted
    //source data ready on bus
    //destination address accepted
    //destination data accepted
    output reg valid, //Asserted by the DMA whenever the DMA is driving a meaningful value on the shared transfer bus. 
    // valid still needs to be syncronised on the other side as well from what I have understood

    // Bus handshaking. We don't need syncronisation, the cpu has the same clock
    output reg BR,
    input wire BG,

    output reg done, // signal to signify the completion of the data transfer

    output reg write_en, //signal to show we can write to the memory

    output reg bus_dir,

    input  wire [7:0] transfer_bus_in,
    output reg  [7:0] transfer_bus_out,
    output reg        transfer_bus_oe
);

// Internal registers and wires
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////// 
reg [7:0] src_addr;
reg [7:0] dst_addr;

// No need for src_loaded and dst_loaded because the CPU and DMA have the same clock domain
// So we know that in each cycle (total 4 cycles) we will get the source and destination address from the CPU

reg mode_reg;
reg direction_reg;
//Simple registers to save teh mode and direction

reg [7:0] data_reg; // register to hold the data being transferred

//reg send_done; // flag because I am losing my mind with the syncronisation

reg [1:0] cycle_count; // counter to keep track of the current cycle (0 to 3)

reg phase; // 0 = address phase where we send the address, 1 = data phase where we send the data

reg [2:0] words_left; // This is for burst mode, to keep track of how many words are left to transfer. We can have a maximum of 4 words in burst mode  
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//Synconisation 
reg fetch_ff1, fetch_ff2, fetch_ff2_d;
wire fetch_rise;

assign fetch_rise = fetch_ff2 & ~fetch_ff2_d;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fetch_ff1   <= 1'b0;
        fetch_ff2   <= 1'b0;
        fetch_ff2_d <= 1'b0;
    end else begin
        fetch_ff1   <= fetch;
        fetch_ff2   <= fetch_ff1;
        fetch_ff2_d <= fetch_ff2;
    end
end



//State encoding
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
localparam S0_IDLE = 2'b00;
localparam  S1_PREPERATION = 2'b01;
localparam S2_RECEIVING = 2'b10;
localparam S3_SENDING = 2'b11;

reg [1:0] state;
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


//Sequential logic
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S0_IDLE;
        src_addr <= 8'b00000000;
        dst_addr <= 8'b00000000;
        data_reg <= 8'b00000000;

        transfer_bus_out <= 8'b00000000;
        transfer_bus_oe  <= 1'b0;

        BR <= 1'b0;
        valid <= 1'b0;
        write_en <= 1'b0;
        done <= 1'b0;
        cycle_count <= 2'b00;
        phase <= 1'b0;
        mode_reg <= 1'b0; 
        direction_reg <= 1'b0; //maybe not the best because it means deafult is single byte transfer for memory?
        bus_dir <= 1'b0;
        words_left <= 3'd0;
        

    end else begin

        BR <= 1'b0;
        write_en <= 1'b0;
        done <= 1'b0;
        transfer_bus_oe <= 1'b0; // This is imprtant because in S2 where we set it as high for example we ight forget to set it low
        valid <= 1'b0;
        case(state)
            // I do not like that I assign the addresses in the idle state, but because of how I understood the enable sinal this is the best I can think of at the moment  
            S0_IDLE: begin
                valid <= 1'b0;
                phase <= 1'b0;
                if (!enable) begin
                    cycle_count <= 2'b00; // And it stays in IDLE 
                end else begin
                     //THIS IS IMPORTANT AND NEEDS DISCUSSION!!!!!!!! At first I thought about having and idle state, ands when the enable signal is high we go to the preperation state where request bus and assign the addresses. HOWEVER if we do that then we might miss a cycle!! After all when enable is high it means the data in input is indeed the first 4 bits of source adress, so next cycle (when we would change to preperation) it would be the rest of the 4 bits of source address!!! I think..?
                    case(cycle_count)
                        2'b00: begin
                            mode_reg <= cfg_in[4]; 
                            direction_reg <= cfg_in[3];
                            src_addr[7:5] <= cfg_in[2:0]; 
                            cycle_count <= 2'b01;
                            // state <= S0_IDLE; We don't need this because we are already in the idle state so unless we explicitly change the state it will stay here 
                        end 
                        2'b01: begin
                            src_addr[4:0] <= cfg_in; 
                            cycle_count <= 2'b10;
                        end 
                        2'b10: begin
                            dst_addr[7:3] <= cfg_in;
                            cycle_count <= 2'b11;
                        end 
                        2'b11: begin 
                            dst_addr[2:0] <= cfg_in[4:2]; 
                            cycle_count   <= 2'b00; // for burst we need to have count back to zero,  unless we explicitly do something else for burst write, where we go to stae idle but enable has a low value for one cycle before we do the configuration for the second word
                            words_left    <= mode_reg ? 3'd4 : 3'd1;
                            state <= S1_PREPERATION;
                        end
                    endcase
                end
            end

            S1_PREPERATION: begin
                BR  <= 1'b1; // Request the bus
                if (BG) begin
                    state <= S2_RECEIVING; // Move to the next state when bus is granted
                end else begin
                    state <= S1_PREPERATION; // Stay in the current state until bus is granted
                    //This is not needed I realise 
                end
            end

            S2_RECEIVING: begin
                valid <= 1'b0;
                bus_dir <= direction_reg; // simply because it is better for it to be stable for both phases
                BR <= 1'b1;
                //Phase 0 : we send the source adress
                if (phase == 1'b0) begin
                    transfer_bus_out <= src_addr;
                    transfer_bus_oe <= 1'b1;
                    write_en <= 1'b0;
                    valid <= 1'b1;
 
                    // Wait until other side acknowledges address
                    if (fetch_rise) begin
                        phase <= 1'b1;
                    end
                end else begin
                    //Phase 1: We receive the data from the address
                    transfer_bus_oe <= 1'b0; //this will release the bus and make it into an input
                    write_en <= 1'b0;
                    valid <= 1'b0;

                    if (fetch_rise) begin
                        data_reg <= transfer_bus_in;
                        phase <= 1'b0;
                        state <= S3_SENDING;
                    end
                end

            end

            S3_SENDING: begin
                bus_dir <= !direction_reg; // Because whatever the source is we want the opposite . Since both meory and I/O have the same 8 bits for adrees and with direction we say where exactly we want it
                BR <= 1'b1; 
                    // Phase 0: we send the destination address
                    if (phase == 1'b0) begin
                        transfer_bus_out <= dst_addr;
                        transfer_bus_oe <= 1'b1;
                        write_en <= 1'b0;
                        valid <= 1'b1;
                    
                        // Wait until other side acknowledges address
                        if (fetch_rise) begin
                            phase <= 1'b1;
                        end
                    end else begin
                        // Phase 1: we send the data to the destination adress
                        transfer_bus_out <= data_reg;
                        transfer_bus_oe <= 1'b1;
                        write_en <= 1'b1;
                        valid <= 1'b1;

                        // Wait until other side acknowledges data
                        if (fetch_rise) begin
                            if (words_left == 3'd1) begin
                                done       <= 1'b1;
                                words_left <= 3'd0;
                                phase      <= 1'b0;
                                state      <= S0_IDLE;
                            end else begin
                                words_left <= words_left - 3'd1;
                                src_addr   <= src_addr + 8'd1;
                                dst_addr   <= dst_addr + 8'd1;
                                phase      <= 1'b0;
                                state      <= S2_RECEIVING;
                            end
                        end
                    end
                end 

            default: begin
                state <= S0_IDLE;
            end

        endcase

    end
end

endmodule
