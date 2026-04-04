#!/usr/bin/env python3
"""
Python-based testbench for TinyTapeout DMA Controller
Simulates the Verilog design behavior without needing iverilog
Generates VCD file for waveform viewing in GTKWave
"""

import os
from datetime import datetime

class VCDWriter:
    """Simple VCD file writer"""
    def __init__(self, filename, timescale="1ns"):
        self.filename = filename
        self.timescale = timescale
        self.signals = {}
        self.values = {}
        self.next_var_id = 0
        self.vcd_lines = []
        
    def register_signal(self, name, width=1):
        """Register a signal to track"""
        var_id = chr(33 + self.next_var_id)
        self.next_var_id += 1
        self.signals[name] = (var_id, width)
        self.values[name] = 0
        return var_id
    
    def write_header(self):
        """Write VCD header"""
        self.vcd_lines.append("$date")
        self.vcd_lines.append(f"  {datetime.now()}")
        self.vcd_lines.append("$end")
        self.vcd_lines.append("$version")
        self.vcd_lines.append("  Python DMA Testbench 1.0")
        self.vcd_lines.append("$end")
        self.vcd_lines.append("$timescale")
        self.vcd_lines.append(f"  {self.timescale}")
        self.vcd_lines.append("$end")
        self.vcd_lines.append("$scope module tb $end")
        
        # Register variables
        for name, (var_id, width) in self.signals.items():
            if width == 1:
                self.vcd_lines.append(f"$var wire 1 {var_id} {name} $end")
            else:
                self.vcd_lines.append(f"$var wire {width} {var_id} {name} $end")
        
        self.vcd_lines.append("$upscope $end")
        self.vcd_lines.append("$enddefs $end")
        self.vcd_lines.append("#0")
        
        # Initial values
        for name, (var_id, width) in self.signals.items():
            if width == 1:
                self.vcd_lines.append(f"0{var_id}")
            else:
                self.vcd_lines.append(f"b0 {var_id}")
    
    def change(self, time, name, value):
        """Record a signal change"""
        if name not in self.signals:
            return
        
        var_id, width = self.signals[name]
        if self.values.get(name) != value:
            self.values[name] = value
            self.vcd_lines.append(f"#{time}")
            
            if width == 1:
                self.vcd_lines.append(f"{value}{var_id}")
            else:
                self.vcd_lines.append(f"b{value:0{width}b} {var_id}")
    
    def save(self):
        """Save VCD file"""
        with open(self.filename, 'w') as f:
            f.write('\n'.join(self.vcd_lines))
        print(f"VCD file saved: {self.filename}")


class DMACController:
    """Behavioral model of tt_um_AUTH_DMA_CONTROLLER"""
    
    # State definitions
    IDLE = 0b000
    CONFIGURATION = 0b001
    HANDSHAKE = 0b010
    DMA2SRC = 0b011
    SRC2DMA = 0b100
    DMA2DEST_addr = 0b101
    DMA2DEST_data = 0b110
    
    def __init__(self):
        # State
        self.current_state = self.IDLE
        self.next_state = self.IDLE
        self.counter = 0
        
        # Data registers
        self.src_addr = 0
        self.dest_addr = 0
        self.data = 0
        self.transfer_bus_out = 0
        
        # Control signals
        self.BR = 0
        self.WRITE_en = 1
        self.done = 0
        self.REQ = 0
        self.ALE = 0
        self.Write_dir = 0
        self.io_dir = 0
        
        # Configuration
        self.MODE = 0
        self.words_left = 0
        
        # Synchronizer (2-FF)
        self.ACK_sync_ff1 = 0
        self.ACK_sync_ff2 = 0
        self.ACK_sync = 0
    
    def clock(self, ui_in, uio_in, ena, rst_n):
        """Simulate one clock cycle"""
        
        # Extract inputs
        enable = (ui_in >> 7) & 1
        BG = (ui_in >> 6) & 1
        ACK_async = (ui_in >> 5) & 1
        cfg_in = ui_in & 0x0F
        
        # Reset logic
        if not rst_n:
            self.current_state = self.IDLE
            self.counter = 0
            self.src_addr = 0
            self.dest_addr = 0
            self.data = 0
            self.transfer_bus_out = 0
            self.ACK_sync_ff1 = 0
            self.ACK_sync_ff2 = 0
            self.ACK_sync = 0
            return
        
        # 2-FF synchronizer for ACK
        self.ACK_sync_ff1 = ACK_async
        self.ACK_sync_ff2 = self.ACK_sync_ff1
        self.ACK_sync = self.ACK_sync_ff2
        
        # Update state
        self.current_state = self.next_state
        
        # Counter logic
        if self.next_state != self.current_state or self.current_state == self.IDLE:
            self.counter = 0
        else:
            self.counter = (self.counter + 1) & 0x7
        
        # Sequential logic (on clock edge)
        if self.current_state == self.IDLE:
            if enable:
                self.src_addr = (self.src_addr & 0xF0) | (cfg_in & 0x0F)
                self.MODE = (ui_in >> 4) & 1
        
        elif self.current_state == self.CONFIGURATION:
            if self.counter == 0:
                self.Write_dir = (ui_in >> 7) & 1
                self.src_addr = (self.src_addr & 0x0F) | ((cfg_in & 0x0F) << 4)
            
            if self.counter == 1:
                self.dest_addr = (self.dest_addr & 0xF0) | (cfg_in & 0x0F)
            
            if self.counter == 2:
                self.dest_addr = (self.dest_addr & 0x0F) | ((cfg_in & 0x0F) << 4)
        
        elif self.current_state == self.SRC2DMA:
            if self.ACK_sync:
                self.data = uio_in
    
    def compute_next_state(self, ui_in):
        """Compute next state (combinational)"""
        BG = (ui_in >> 6) & 1
        enable = (ui_in >> 7) & 1
        
        self.next_state = self.current_state
        
        if self.current_state == self.IDLE:
            if enable:
                self.next_state = self.CONFIGURATION
        
        elif self.current_state == self.CONFIGURATION:
            if self.counter == 2:
                self.next_state = self.HANDSHAKE
        
        elif self.current_state == self.HANDSHAKE:
            if BG:
                self.next_state = self.DMA2SRC
        
        elif self.current_state == self.DMA2SRC:
            if self.ACK_sync:
                self.next_state = self.SRC2DMA
        
        elif self.current_state == self.SRC2DMA:
            if self.ACK_sync:
                self.next_state = self.DMA2DEST_addr
        
        elif self.current_state == self.DMA2DEST_addr:
            if self.ACK_sync:
                self.next_state = self.DMA2DEST_data
    
    def compute_outputs(self):
        """Compute combinational outputs"""
        
        # Default outputs
        self.BR = 0
        self.WRITE_en = 1
        self.done = 0
        self.REQ = 0
        self.ALE = 0
        self.io_dir = 0
        self.transfer_bus_out = 0
        
        if self.current_state == self.HANDSHAKE:
            self.BR = 1
        
        elif self.current_state == self.DMA2SRC:
            self.BR = 0
            self.WRITE_en = 0
            self.REQ = 1
            self.io_dir = 1
            self.transfer_bus_out = self.src_addr
        
        elif self.current_state == self.SRC2DMA:
            self.io_dir = 0
            self.REQ = 0
            if self.ACK_sync:
                self.REQ = 1
        
        elif self.current_state == self.DMA2DEST_addr:
            self.io_dir = 1
            self.WRITE_en = 1
            self.transfer_bus_out = self.dest_addr
            self.REQ = 1
        
        elif self.current_state == self.DMA2DEST_data:
            self.io_dir = 1
            self.transfer_bus_out = self.data
            self.REQ = 1
    
    def get_uo_out(self):
        """Output: uo_out = {2'b00, Write_dir, ALE, REQ, done, WRITE_en, BR}"""
        return (self.Write_dir << 5) | (self.ALE << 4) | (self.REQ << 3) | (self.done << 2) | (self.WRITE_en << 1) | self.BR
    
    def get_uio_out(self):
        """Output: uio_out = transfer_bus_out"""
        return self.transfer_bus_out
    
    def get_uio_oe(self):
        """Output: uio_oe = io_dir ? 8'hFF : 8'h00"""
        return 0xFF if self.io_dir else 0x00
    
    def get_state_name(self):
        """Get human-readable state name"""
        states = {
            self.IDLE: "IDLE",
            self.CONFIGURATION: "CONFIG",
            self.HANDSHAKE: "HANDSHAKE",
            self.DMA2SRC: "DMA2SRC",
            self.SRC2DMA: "SRC2DMA",
            self.DMA2DEST_addr: "DMA2DEST_addr",
            self.DMA2DEST_data: "DMA2DEST_data",
        }
        return states.get(self.current_state, f"UNKNOWN({self.current_state})")


def run_simulation():
    """Run the testbench stimulus"""
    
    dut = DMACController()
    clk = 0
    rst_n = 1
    ena = 1
    
    # Initialize VCD writer
    vcd = VCDWriter("tb.vcd", "1ns")
    
    # Register signals
    vcd.register_signal("clk", 1)
    vcd.register_signal("rst_n", 1)
    vcd.register_signal("ena", 1)
    vcd.register_signal("ui_in[7:0]", 8)
    vcd.register_signal("uio_in[7:0]", 8)
    vcd.register_signal("uo_out[7:0]", 8)
    vcd.register_signal("uio_out[7:0]", 8)
    vcd.register_signal("uio_oe[7:0]", 8)
    vcd.register_signal("state[2:0]", 3)
    vcd.register_signal("counter[2:0]", 3)
    vcd.register_signal("REQ", 1)
    vcd.register_signal("io_dir", 1)
    vcd.register_signal("ACK_sync", 1)
    vcd.register_signal("src_addr[7:0]", 8)
    vcd.register_signal("dest_addr[7:0]", 8)
    vcd.register_signal("data[7:0]", 8)
    vcd.register_signal("transfer_bus_out[7:0]", 8)
    
    vcd.write_header()
    
    # Test sequence from tb.v
    test_vectors = [
        # time, ui_in, uio_in
        (0, 0x00, 0x00),
        (10, 0x00, 0x00),      # rst_n = 0
        (20, 0x9F, 0x00),      # rst_n = 1, Enable=1, MODE=1, cfg_in=1111
        (30, 0x8A, 0x00),      # src_addr[7:4] = 1010
        (40, 0x8E, 0x00),      # dest_addr[3:0] = 1110
        (50, 0x8A, 0x00),      # dest_addr[7:4] = 1010
        (70, 0x42, 0x00),      # BG=1
        (80, 0x60, 0x00),      # BG=1, ACK_async=1
        (90, 0x40, 0x00),      # BG=1, ACK_async=0
        (120, 0x40, 0xE1),     # data from source
        (130, 0x60, 0xE1),     # BG=1, ACK_async=1
    ]
    
    print("=" * 80)
    print("DMA Controller Testbench (Python Simulation with VCD Output)")
    print("=" * 80)
    print()
    
    for time_step, (t, ui_in, uio_in) in enumerate(test_vectors):
        # Determine reset
        if t < 20:
            rst_n = 0
        else:
            rst_n = 1
        
        # Compute next state (combinational, before clock)
        dut.compute_next_state(ui_in)
        
        # Clock edge
        dut.clock(ui_in, uio_in, ena, rst_n)
        
        # Compute outputs (combinational)
        dut.compute_outputs()
        
        # Get outputs
        uo_out = dut.get_uo_out()
        uio_out = dut.get_uio_out()
        uio_oe = dut.get_uio_oe()
        
        # Record changes in VCD
        vcd.change(t, "clk", 0)
        vcd.change(t+1, "clk", 1)
        vcd.change(t, "rst_n", rst_n)
        vcd.change(t, "ena", ena)
        vcd.change(t, "ui_in[7:0]", ui_in)
        vcd.change(t, "uio_in[7:0]", uio_in)
        vcd.change(t+2, "uo_out[7:0]", uo_out)
        vcd.change(t+2, "uio_out[7:0]", uio_out)
        vcd.change(t+2, "uio_oe[7:0]", uio_oe)
        vcd.change(t+2, "state[2:0]", dut.current_state)
        vcd.change(t+2, "counter[2:0]", dut.counter)
        vcd.change(t+2, "REQ", dut.REQ)
        vcd.change(t+2, "io_dir", dut.io_dir)
        vcd.change(t+2, "ACK_sync", dut.ACK_sync)
        vcd.change(t+2, "src_addr[7:0]", dut.src_addr)
        vcd.change(t+2, "dest_addr[7:0]", dut.dest_addr)
        vcd.change(t+2, "data[7:0]", dut.data)
        vcd.change(t+2, "transfer_bus_out[7:0]", dut.transfer_bus_out)
        
        # Print state
        print(f"[Cycle {time_step}] t={t:3d}ns | State: {dut.get_state_name():15s} | Counter: {dut.counter}")
        print(f"  Inputs:  ui_in=0x{ui_in:02X}, uio_in=0x{uio_in:02X}, rst_n={rst_n}")
        print(f"  Outputs: uo_out=0x{uo_out:02X}, uio_out=0x{uio_out:02X}, uio_oe=0x{uio_oe:02X}")
        
        if dut.current_state == dut.DMA2SRC:
            print(f"  --> DMA2SRC: Drive src_addr=0x{dut.src_addr:02X} to bus (io_dir={dut.io_dir})")
        elif dut.current_state == dut.SRC2DMA:
            print(f"  --> SRC2DMA: Read data from source, ACK_sync={dut.ACK_sync}")
        elif dut.current_state == dut.DMA2DEST_addr:
            print(f"  --> DMA2DEST_addr: Drive dest_addr=0x{dut.dest_addr:02X}")
        elif dut.current_state == dut.DMA2DEST_data:
            print(f"  --> DMA2DEST_data: Drive data=0x{dut.data:02X}")
        
        print()
    
    # Save VCD file
    vcd.save()
    
    print("=" * 80)
    print("Simulation Complete")
    print("=" * 80)
    print(f"\nFinal State: {dut.get_state_name()}")
    print(f"src_addr:  0x{dut.src_addr:02X}")
    print(f"dest_addr: 0x{dut.dest_addr:02X}")
    print(f"data:      0x{dut.data:02X}")
    print()
    print("To view waveforms in GTKWave (if installed):")
    print("  gtkwave tb.vcd")
    print()


if __name__ == "__main__":
    run_simulation()
