# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge


def update_ui_in(dut, dma_en, bus_grant, mode_dir, addr_2bits):
    _dma_en     = dma_en     & 0b1
    _bus_grant  = bus_grant  & 0b1
    _mode_dir   = mode_dir   & 0b1
    _addr_2bits = addr_2bits & 0b11

    dut.ui_in.value = (
        (_dma_en        << 4) | 
        (_bus_grant     << 3) | 
        (_mode_dir      << 2) | 
        _addr_2bits     
    )
    

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, unit="us")
    clock_mem = Clock(dut.clk_mem, 10, unit="us")
    clock_io = Clock(dut.clk_io, 10, unit="us")
    cocotb.start_soon(clock.start())
    cocotb.start_soon(clock_mem.start())
    cocotb.start_soon(clock_io.start())

    # Reset

    # Initialize/reset procedure for all modules

    dut._log.info("Reset")
    dut.ena.value = 1
    dut.rst_n.value = 1

    # Initializing DMA inputs - The other two modules have their inputs driven by the DMA
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)

    dut.rst_n.value = 1

    dut._log.info("DMA ready")

    # Sending data to the DMA

    dut._log.info("Testing DMA")

    # Configuring the ui_in

    # Define two 8-bit addresses to send
    address_1 = 0xAA  # Replace with actual first address
    address_2 = 0x55  # Replace with actual second address
    # Combine them into a 16-bit word (addr_2 in upper 8 bits, addr_1 in lower 8 bits)
    full_address = (address_2 << 8) | address_1

    for i in range(8):
        # Wait for the negedge of the clock before applying new values
        await FallingEdge(dut.clk)

        # Extract 2 bits for the current iteration
        # Cycle 0 gets bits 0-1, Cycle 1 gets bits 2-3, etc.
        current_2bits = (full_address >> (i * 2)) & 0b11
        
        # We need to evaluate the signals or default to 0 if uninitialized
        fetch_val = dut.fetch_mem.value | dut.fetch_io.value

        mode_dir = 0

        if i == 0:
            mode_dir = 0
        elif i == 1:
            mode_dir = 0
        else:
            mode_dir = 0
        
        update_ui_in(
            dut, 
            dma_en=1, 
            bus_grant=0, 
            mode_dir=mode_dir, 
            addr_2bits=current_2bits, 
        )


    assert dut.uo_out[2].value == 1

    # Keep testing the module by changing the input values, waiting for
    # one or more clock cycles, and asserting the expected output values.
