`default_nettype none
`timescale 1ns / 1ps

module tb ();

  // Dump the signals to a FST file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  // Wire up the inputs and outputs:
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  tt_um_AUTH_DMA_CONTROLLER user_project (
`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif
      .ui_in(ui_in),
      .uo_out(uo_out),
      .uio_in(uio_in),
      .uio_out(uio_out),
      .uio_oe(uio_oe),
      .ena(ena),
      .clk(clk),
      .rst_n(rst_n)
  );

  initial begin
    ui_in = 8'b00000000;
    uio_in = 8'b00000000;
    ena = 1'b1;
    clk = 1'b0;
    rst_n = 1'b1;

    #10 rst_n = 1'b0;

    #10 ui_in = 8'b10011111;  // Enable=1, MODE=1, cfg_in=1111
    rst_n = 1'b1;

    #10 ui_in = 8'b10001010;  // src_addr[7:4] = 1010

    #10 ui_in = 8'b10001110;  // dest_addr[3:0] = 1110

    #10 ui_in = 8'b10001010;  // dest_addr[7:4] = 1010

    #20 ui_in = 8'b01000010;   // BG=1

    #10 ui_in = 8'b01100000;   // BG=1, ACK_async=1

    #10 ui_in = 8'b01000000;   // BG=1, ACK_async=0

    #30 uio_in = 8'b11100001;  // data from source side

    #10 ui_in = 8'b01100000;   // BG=1, ACK_async=1

    #100 $finish();
  end

  always #5 clk = ~clk;

endmodule
