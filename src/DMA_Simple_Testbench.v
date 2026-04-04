`timescale 1ns / 1ps

module tb_dma_controller;

    reg clk;
    reg rst_n;
    reg ena;
    reg [7:0] ui_in;
    wire [7:0] uo_out;
    reg [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    tt_um_dma_controller dut (
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(ena),
        .clk(clk),
        .rst_n(rst_n)
    );

    always #50 clk = ~clk;

    initial begin
    $dumpfile("dump.vcd"); 
    $dumpvars(0, tb_dma_controller);        clk = 0;
        rst_n = 0;
        ena = 1;
        ui_in = 0;
        uio_in = 8'h00;

        #150 rst_n = 1; 
        $display("Time %t: Reset released", $time);

        ui_in = 8'b01010010; 
        #100;
        ui_in[6] = 0;

        wait(uio_out[7] == 1); 
        $display("Time %t: DMA sent Bus Request (BR)", $time);
        
        #200; 
        uio_in[7] = 1;
        $display("Time %t: CPU granted Bus (BG)", $time);

       
        uio_in[6:0] = 7'h2A; 
        #200;
     
        if (uio_oe == 8'hFF)
            $display("Time %t: DMA is writing to Destination successfully!", $time);

        #500;
        $display("Test Finished");
        $finish;
    end

endmodule
