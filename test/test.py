# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge


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
    clock = Clock(dut.clk, 100, unit="us")
    clock_mem = Clock(dut.clk_mem, 250, unit="us")
    clock_io = Clock(dut.clk_io, 1, unit="us")
    cocotb.start_soon(clock.start())
    cocotb.start_soon(clock_mem.start())
    cocotb.start_soon(clock_io.start())

    # Reset

    # Initialize/reset procedure for all modules

    dut._log.info("Reset")
    dut.ena.value = 1
    dut.rst_n.value = 1

    await ClockCycles(dut.clk, 5)

    # Initializing DMA inputs - The other two modules have their inputs driven by the DMA
    dut.ui_in.value = 0

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)

    dut.rst_n.value = 1

    dut._log.info("DMA ready")

    # Sending data to the DMA

    dut._log.info("Testing DMA")

    # Configuring the ui_in

    # Define two 8-bit addresses to send
    address_1 = 0x15  # Source address (8 bit address, maximum hex value: 0xFF)
    address_2 = 0xBB  # Destination address (8 bit address, maximum hex value: 0xFF)
    # Combine them into a 16-bit word (addr_2 in upper 8 bits, addr_1 in lower 8 bits)
    full_address = (address_2 << 8) | address_1

    for i in range(8):
        # Wait for the negedge of the clock before applying new values
        await FallingEdge(dut.clk)

        # Extract 2 bits for the current iteration
        # Cycle 0 gets bits 0-1, Cycle 1 gets bits 2-3, etc. --- IMPORTANT !!! Always the first address we sent is the source address
        current_2bits = (full_address >> (i * 2)) & 0b11
        
        mode_dir = 0

        if i == 0:
            mode_dir = 0
        elif i == 1:
            mode_dir = 1
            direction = mode_dir
        else:
            mode_dir = 0
        
        update_ui_in(
            dut, 
            dma_en=1, 
            bus_grant=0, 
            mode_dir=mode_dir, 
            addr_2bits=current_2bits, 
        )

        dut._log.info(f"Loading procedure: Iteration {i}/7")


    # Wait for a few more clock cycles so we can observe the results in gtkwave
    await ClockCycles(dut.clk, 20)

    # Wait until the Bus Request (BR) bit becomes 1
    while dut.uo_out.value[6] != 1:
        await RisingEdge(dut.clk)  # Advance simulation time by one clock cycle

    # Once we break out of the loop, BR is 1, so we grant the bus
    update_ui_in(
        dut, 
        dma_en=1, 
        bus_grant=1, 
        mode_dir=mode_dir, 
        addr_2bits=current_2bits, 
    )

    # Testing if done bit becomes 1

    dut._log.info("Waiting for the 'done' bit to be set...")
    
    max_cycles = 5000
    for loop_cnt in range(max_cycles):
        if dut.uo_out.value[2] == 1:
            dut._log.info(f"Done bit (uo_out[2]) set after {loop_cnt} cycles. Test successful!")
            assert 1 == 1
            break
        await RisingEdge(dut.clk)


    await ClockCycles(dut.clk, 5)

    # Checking if the data we sent was successfuly received

    if direction == 0 and dut.dut_io.regs[address_2].value == dut.dut_mem.regs[address_1].value :
        dut._log.info(f"The destination address (dec: {address_2}) now holds the data we sent --> data sent: {dut.dut_mem.regs[address_1].value}) --- data received: {dut.dut_io.regs[address_2].value}")
        assert 1 == 1
    elif direction == 1 and dut.dut_mem.regs[address_2].value == dut.dut_io.regs[address_1].value :
        dut._log.info(f"The destination address (dec: {address_2}) now holds the data we sent --> data sent: {dut.dut_io.regs[address_1].value}) --- data received: {dut.dut_mem.regs[address_2].value}")
        assert 1 == 1
    else:
        dut._log.info(f"destination data: {dut.dut_mem.regs[address_2].value} --- source data: {dut.dut_io.regs[address_1].value}")
        assert 1 == 0 
            
    #assert False, f"Simulation timeout: 'done' bit did not become 1 after {max_cycles} clock cycles!"

    # Keep testing the module by changing the input values, waiting for
    # one or more clock cycles, and asserting the expected output values.
