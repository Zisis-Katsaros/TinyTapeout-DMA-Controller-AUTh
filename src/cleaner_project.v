/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */


//=============================================================
// Ok so what id did here, is change the prebious dma controller into soemthing  a bit cleaner, while also fixing some weaknesses.
// First I kept it as a 4 state design, because I thought we would have to do it as 4 state, but mainly because of direct comparisson with the previous design
// The states could easily be split up. Specifically states S2 and S3, the handshake for the time domain corssing could be seprate states.

// Specifcally what I did is using my previous logic of the "phase" signal I mplemnted the substep counter
//the substep counter makes it so that teh handshake for tiem domain corssing is implmented  more safely
//Wha  happens is that compared to the previous design where we only wanted to see the rsing edge of the fecth signal, now we explicity wait for fetch to go high then low
// This allows us to properly handle the case where fetch is high for more than one cycle, which was a problem in the previous design 
//The previous design advanced only on a synchronized rising-edge event
// Thus a prolonged assertion could caus eproblems 
// Since the dma could mix up whihc fetxh signl is for what event
//Hence we epclicitly say to look for the featch level to ignify the full end of the event
//Not to mention an level handshake signal is eaier to track
//essentially I made what would otheriwse be mutliple states, into one single state with substeps using the counter

// I also changedthe way the "enable" siganl works, I added the wait_enable_low
// Before I kept it as is , and simply thought that there isn't a problem since enable will always be high anyway.
// However if enable keeps being high after a transfer is done and we go through ecah state, we would then reenter the idle state immidetly if we  hadsoemthing loaded in cfg i
// I thought that wasn't neccesrly wrong but it should be better to alwyaays make the option when a transfer is complete to drive enable low first andthne re-activate it if there needs to be another transfer

// I also changed done and made it a constant output instead of a pulse that appears at single cycle

// This design is stil fednitely weak
//We take as an assumtipon for example that in the transfer bus, the data will be stable when fetch is high
//valid alone does not enforce that
//It only shows the data is ready on the DMAs end , not that it won't chhange while fetch is high

//Also a small thing is thet typically a DMA controller mainly has the option not just i/o -> memory , and memory -> i/o, but mainly memory -> meemory (and i/o/ -> io in some cases but that is typically i/o -> memory -> i/o)
//I didn't implment this, however it could be doens simply by adding a bit to direction, although that would require some changes in the address assignment as well
//=============================================================



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
    wire BG = ui_in[5];
    wire [4:0] cfg_in = ui_in[4:0];

    // Bidirectional transfer bus control
    wire [7:0] transfer_bus_out;
    wire transfer_bus_oe;

    // Status outputs
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

    assign uio_out = transfer_bus_out;
    assign uio_oe = transfer_bus_oe ? 8'hFF : 8'h00;

    // prevent warnings
    wire _unused = &{ena, 1'b0};

endmodule


module dma_4_state(
    // Standard signals
    input wire clk,
    input wire rst_n,
    input wire enable,

    // Configuration input (same clock domain as DMA)
    input wire [4:0] cfg_in,

    // Cross-domain handshake from external side.
    // IMPORTANT I CHANGED THIS!!!:
    //   - treat this as a LEVEL handshake, not a short pulse.
    //   - when DMA presents valid data/address, external raises fetch=1
    //     and keeps it high until DMA drops valid.
    //   - when external presents read data to DMA, external raises fetch=1
    //     while holding transfer_bus_in stable.
    input wire fetch,

    
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

    reg [1:0] cycle_count;    // config loading counter
    reg [1:0] substep;   // handshake microstep counter withing states S2 and S3 to proeprly handle the handshakes between time domains in just two states

    // New siganl to tackle the problem of enable neing high for mor ethan one cycle would cause the state machine to start a new transfer
    //Turns it was a bug not a feature..
    // Because we might start a transfer when we shoudn't
    reg wait_enable_low;

    reg [2:0] words_left;   // enough for values 0..4 because I need the 0 bit to signify we are done not just 0-3 

    // ============================================================
    // Synchronize fetch into clk domain
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

    // ============================================================
    // State encoding (4 top-level states only)
    // ============================================================

    localparam S0_IDLE = 2'b00;
    localparam S1_PREPARATION = 2'b01;
    localparam S2_RECEIVING = 2'b10;
    localparam S3_SENDING = 2'b11;

    reg [1:0] state;

    // ============================================================
    // Main sequential logic
    // ============================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S0_IDLE;
            src_addr <= 8'b00000000;
            dst_addr <= 8'b00000000;
            data_reg <= 8'b00000000;
            mode_reg <= 1'b0;
            direction_reg <= 1'b0;

            cycle_count <= 2'b00;
            substep <= 2'b00;
            wait_enable_low  <= 1'b0;
            words_left <= 3'd0;

            transfer_bus_out <= 8'h00;
            transfer_bus_oe <= 1'b0;

            BR <= 1'b0;
            valid <= 1'b0;
            done <= 1'b0;
            write_en <= 1'b0;
            bus_dir <= 1'b0;
        end else begin
            // Defaults each cycle
            BR <= 1'b0;
            valid <= 1'b0;
            //done <= 1'b0; This isn't needed because done is constantly high when we are finished, not just a pulse for a single cycle
            write_en <= 1'b0;
            transfer_bus_oe <= 1'b0;

            case (state)

                // ====================================================
                // S0_IDLE
                // Collect 4 config chunks over 4 cycles while enable=1.
                // Requires enable to go low between commands.
                // ====================================================
                S0_IDLE: begin
                    substep <= 2'b00;
                    bus_dir <= 1'b0;

                    if (!enable) begin
                        cycle_count <= 2'b00;
                        wait_enable_low <= 1'b0;
                        words_left <= 3'd0;
                    end else if (!wait_enable_low) begin
                        case (cycle_count)
                            2'b00: begin
                                done <= 1'b0;   // clear done when new command starts
                                mode_reg <= cfg_in[4];
                                direction_reg <= cfg_in[3];
                                src_addr[7:5] <= cfg_in[2:0];
                                cycle_count <= 2'b01;
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
                                cycle_count <= 2'b00;
                                state <= S1_PREPARATION;
                                wait_enable_low <= 1'b1;

                                if (mode_reg)
                                    words_left <= 3'd4;   // burst mode
                                else
                                    words_left <= 3'd1;   // single transfer
                            end
                        endcase
                    end
                end

                // ====================================================
                // S1_PREPARATION
                // Request the bus, wait for grant.
                // ====================================================
                S1_PREPARATION: begin //I skipped the  else state <= S1_PREPERATION , no need
                    BR <= 1'b1;
                    if (BG) begin
                        state <= S2_RECEIVING;
                        substep <= 2'b00;
                    end
                end

                // ====================================================
                // S2_RECEIVING
                //
                // substep 0:
                //   Drive source address, valid=1, wait fetch_sync=1
                //
                // substep 1:
                //   Drop valid, release bus, wait fetch_sync=0
                //
                // substep 2:
                //   Wait for external side to drive read data and assert fetch=1
                //   Sample transfer_bus_in while fetch_sync=1
                //
                // substep 3:
                //   Wait fetch_sync=0, then go to sending state
                // ====================================================
                S2_RECEIVING: begin
                    BR <= 1'b1;
                    bus_dir <= direction_reg;

                    case (substep)
                        2'b00: begin
                            transfer_bus_out <= src_addr;
                            transfer_bus_oe <= 1'b1;
                            valid <= 1'b1;
                            write_en <= 1'b0;

                            if (fetch_sync) begin
                                substep <= 2'b01;
                            end
                        end

                        2'b01: begin
                            // Drop valid so external side can release fetch
                            transfer_bus_oe <= 1'b0;
                            valid <= 1'b0;
                            write_en <= 1'b0;

                            if (!fetch_sync) begin
                                substep <= 2'b10;
                            end
                        end

                        2'b10: begin
                            // External side must drive transfer_bus_in and hold it stable
                            // while asserting fetch=1.
                            transfer_bus_oe <= 1'b0;
                            valid <= 1'b0;
                            write_en <= 1'b0;

                            if (fetch_sync) begin
                                data_reg <= transfer_bus_in;
                                substep <= 2'b11;
                            end
                        end

                        2'b11: begin
                            transfer_bus_oe <= 1'b0;
                            valid <= 1'b0;
                            write_en <= 1'b0;

                            if (!fetch_sync) begin
                                substep <= 2'b00;
                                state <= S3_SENDING;
                            end
                        end
                    endcase
                end

                // ====================================================
                // S3_SENDING
                //
                // substep 0:
                //   Drive destination address, valid=1, wait fetch_sync=1
                //
                // substep 1:
                //   Drop valid, wait fetch_sync=0
                //
                // substep 2:
                //   Drive write data, valid=1, write_en=1, wait fetch_sync=1
                //
                // substep 3:
                //   Drop valid, wait fetch_sync=0 : 
                //     - either pulse done, return to idle
                //     - or decrement words_left, increment addresses, loop back to S2_RECEIVING
                // ====================================================
                S3_SENDING: begin
                    BR <= 1'b1;
                    bus_dir <= !direction_reg;

                    case (substep)
                        2'b00: begin
                            transfer_bus_out <= dst_addr;
                            transfer_bus_oe <= 1'b1;
                            valid <= 1'b1;
                            write_en <= 1'b0;

                            if (fetch_sync) begin
                                substep <= 2'b01;
                            end
                        end

                        2'b01: begin
                            transfer_bus_oe <= 1'b0;
                            valid <= 1'b0;
                            write_en <= 1'b0;

                            if (!fetch_sync) begin
                                substep <= 2'b10;
                            end
                        end

                        2'b10: begin
                            transfer_bus_out <= data_reg;
                            transfer_bus_oe <= 1'b1;
                            valid <= 1'b1;
                            write_en <= 1'b1;

                            if (fetch_sync) begin
                                substep <= 2'b11;
                            end
                        end

                        2'b11: begin
                            transfer_bus_oe <= 1'b0;
                            valid <= 1'b0;
                            write_en <= 1'b0;

                            if (!fetch_sync) begin
                                if (words_left <= 3'd1) begin // with word's left I meanthe number of words remaing including the one being proccessed
                                    // This was the last word
                                    done <= 1'b1;
                                    words_left <= 3'd0;
                                    substep <= 2'b00;
                                    state <= S0_IDLE;
                                end else begin
                                    // More words remain in burst
                                    words_left <= words_left - 3'd1;
                                    src_addr <= src_addr + 8'd1;
                                    dst_addr <= dst_addr + 8'd1;
                                    substep <= 2'b00;
                                    state <= S2_RECEIVING;
                                end
                            end
                        end
                    endcase
                end

                default: begin
                    state <= S0_IDLE;
                end
            endcase
        end
    end

endmodule
