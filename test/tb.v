`default_nettype none
`timescale 1ns / 1ps

`include "../src/project.v"
`include "../src/memory.v"
`include "../src/io.v"

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
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
  reg [4:0] ui_in;
  //reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  // Replace tt_um_example with your module name:
  tt_um_example_zafeiris dut (

      // Include power ports for the Gate Level test:
`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif

      .ui_in  ({ui_in[4:3], (fetch_io || fetch_mem), ui_in[2:0], IO_ack, MEM_ack}),    // Dedicated inputs
      .uo_out (uo_out),   // Dedicated outputs
      .uio_in (DMA_data_out_mem),   // IOs: Input path --- DMA_data_out_mem because source is MEM now, so only MEM sends data to DMA 
      .uio_out(uio_out),  // IOs: Output path
      .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),      // enable - goes high when design is selected
      .clk    (clk),      // clock
      .rst_n  (rst_n)     // not reset
  );

  reg clk_mem;
  //reg rst_n;
  wire [7:0] DMA_data_out_mem;
  wire fetch_mem;
  wire MEM_ack;
// `ifdef GL_TEST
//   wire VPWR = 1'b1;
//   wire VGND = 1'b0;
// `endif

  // Replace tt_um_example with your module name:
  memory dut_mem (

      // Include power ports for the Gate Level test:
// `ifdef GL_TEST
//       .VPWR(VPWR),
//       .VGND(VGND),
// `endif

      .fetch  (fetch_mem),    // Dedicated inputs
      .MEM_ack (MEM_ack),   // Dedicated outputs
      .DMA_data_out (DMA_data_out_mem),   // IOs: Output path
      .DMA_data_in (uio_out),   // IOs: Output path
      .ins(uo_out[6:0]),  // IOs: Output path
      .clk    (clk_mem),      // clock
      .rst_n  (rst_n)     // not reset
  );

  reg clk_io;
  //reg rst_n;
  wire [7:0] DMA_data_out_io;
  wire fetch_io;
  wire IO_ack;
// `ifdef GL_TEST
//   wire VPWR = 1'b1;
//   wire VGND = 1'b0;
// `endif

  io dut_io (

      // Include power ports for the Gate Level test:
// `ifdef GL_TEST
//       .VPWR(VPWR),
//       .VGND(VGND),
// `endif

      .fetch  (fetch_io),    // Dedicated inputs
      .IO_ack (IO_ack),   // Dedicated outputs
      .DMA_data_out (DMA_data_out_io),   // IOs: Input path
      .DMA_data_in (uio_out),   // IOs: Input path
      .ins(uo_out[6:0]),  // IOs: Output path
      .clk    (clk_io),      // clock
      .rst_n  (rst_n)     // not reset
  );

endmodule
