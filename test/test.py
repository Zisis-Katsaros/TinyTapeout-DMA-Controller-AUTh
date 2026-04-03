# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


# 8-bit ui_in
def _pack_ui(start=0, bg=0, rtrn=0, cfg=0):
    # "&" to ensure we get excaclty as many bits as we expect, "<<" to shift into position, "|" to combine
    return ((start & 1) << 7) | ((bg & 1) << 6) | ((rtrn & 1) << 5) | (cfg & 0x1F)

async def _wait_until(dut, predicate, max_cycles=100):
    for _ in range(max_cycles):
        if predicate():
            return
        await ClockCycles(dut.clk, 1)
    raise AssertionError(f"Timeout waiting for condition after {max_cycles} cycles")


async def _reset_dut(dut):
    dut.ena.value = 1
    dut.ui_in.value = _pack_ui(start=0, bg=0, rtrn=0, cfg=0)
    dut.uio_in.value = 0
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

# Instructions from CPU
async def _send_cfg(dut, mode, direction, src_addr, dst_addr):
    words = [
        ((mode & 1) << 4) | (src_addr & 0x0F),
        ((direction & 1) << 4) | ((src_addr >> 4) & 0x0F),
        (dst_addr & 0x0F),
        ((dst_addr >> 4) & 0x0F),
    ]

    # Send start and wait 1 cycle
    dut.ui_in.value = _pack_ui(start=1, bg=0, rtrn=0, cfg=words[0])
    await ClockCycles(dut.clk, 1)

    # Send instructions
    for w in words:
        dut.ui_in.value = _pack_ui(start=1, bg=0, rtrn=0, cfg=w)
        await ClockCycles(dut.clk, 1)

    # Pull start down and wait for DMAC BR before CPU grants bus (BG).
    dut.ui_in.value = _pack_ui(start=0, bg=0, rtrn=0, cfg=0)
    await _wait_until(dut, lambda: int(dut.uo_out.value[7]) == 1, max_cycles=120)
    await ClockCycles(dut.clk, 2)
    dut.ui_in.value = _pack_ui(start=0, bg=1, rtrn=0, cfg=0)

# Send rtrn pulse via 2FF synchronizer
async def _pulse_rtrn(dut, sender, bg=1, pre_cycles=4, max_wait_cycles=60):
    if sender == "mem":
        source_clk = dut.mem_clk
    else:
        source_clk = dut.io_clk

    dut.ui_in.value = _pack_ui(start=0, bg=bg, rtrn=0, cfg=0)
    await ClockCycles(source_clk, pre_cycles)
    dut.ui_in.value = _pack_ui(start=0, bg=bg, rtrn=1, cfg=0)
    # Pull down rtrn once ack is sent
    for _ in range(max_wait_cycles):
        if int(dut.uo_out.value[3]) == 1:
            break
        await ClockCycles(dut.clk, 1)
    else:
        raise AssertionError(f"Timeout waiting for ack after {max_wait_cycles} cycles")
    dut.ui_in.value = _pack_ui(start=0, bg=bg, rtrn=0, cfg=0)
    await ClockCycles(source_clk, 1)


async def _run_transfer_sequence(dut, src_addr, dst_addr, payload, direction):
    # Determine which device (mem or io) sends the rtrn signal
    receive_sender = "mem" if direction == 0 else "io"
    send_sender = "io" if direction == 0 else "mem"

    for i, datum in enumerate(payload):
        # Expected addresses (increment for burst mode)
        exp_src = (src_addr + i) & 0xFF
        exp_dst = (dst_addr + i) & 0xFF

        # SRC_SEND phase: DMA drives source address with valid and WRITE_en=0.
        await _wait_until(
            dut,
            lambda: int(dut.uo_out.value[4]) == 1 and int(dut.uo_out.value[6]) == 0,
            max_cycles=300,
        )
        # Check that DMA is setting bidir ports to output
        assert int(dut.uio_oe.value) == 0xFF, "DMA must drive transfer bus in SRC_SEND"
        # Check that DMA is sending the expected address
        assert int(dut.uio_out.value) == exp_src, (
            f"SRC address mismatch at beat {i}: got 0x{int(dut.uio_out.value):02X}, "
            f"expected 0x{exp_src:02X}"
        )

        # RECEIVE phase: source returns data, signaled by rtrn rising edge.
        dut.uio_in.value = datum
        await _pulse_rtrn(dut, sender=receive_sender, bg=1, pre_cycles=2)

        # SENDaddr phase: DMA presents destination address with valid and WRITE_en=1.
        await _wait_until(
            dut,
            lambda: int(dut.uo_out.value[4]) == 1 and int(dut.uo_out.value[6]) == 1,
            max_cycles=300,
        )
        assert int(dut.uio_out.value) == exp_dst, (
            f"DST address mismatch at beat {i}: got 0x{int(dut.uio_out.value):02X}, "
            f"expected 0x{exp_dst:02X}"
        )

        await _pulse_rtrn(dut, sender=send_sender, bg=1, pre_cycles=2)

        # SENDdata phase: DMA presents captured data with valid and WRITE_en=1.
        await _wait_until(
            dut,
            lambda: int(dut.uo_out.value[4]) == 1 and int(dut.uo_out.value[6]) == 1,
            max_cycles=300,
        )
        assert int(dut.uio_out.value) == (datum & 0xFF), (
            f"DST payload mismatch at beat {i}: got 0x{int(dut.uio_out.value):02X}, "
            f"expected 0x{(datum & 0xFF):02X}"
        )
        await _pulse_rtrn(dut, sender=send_sender, bg=1, pre_cycles=2)


async def _init_clock(dut):
    # Initialize three independent clock domains
    # DMAC/CPU clock: 100MHz (period = 10us in simulation time scaling)
    dmac_clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(dmac_clock.start())

    # Memory clock: 80MHz (period = 12.5us)
    mem_clock = Clock(dut.mem_clk, 12.5, unit="us")
    cocotb.start_soon(mem_clock.start())

    # I/O Device clock: 120MHz (period = 8.33us)
    io_clock = Clock(dut.io_clk, 8.33, unit="us")
    cocotb.start_soon(io_clock.start())

# Single Word Mode Test
@cocotb.test()
async def test_single_word_mode(dut):
    await _init_clock(dut)
    await _reset_dut(dut)

    src_addr = 0x34
    dst_addr = 0xA1
    payload = [0x5C]

    await _send_cfg(dut, mode=0, direction=0, src_addr=src_addr, dst_addr=dst_addr)
    await _run_transfer_sequence(dut, src_addr=src_addr, dst_addr=dst_addr, payload=payload, direction=0)

    await _wait_until(dut, lambda: int(dut.uo_out.value[5]) == 1, max_cycles=200)
    await _wait_until(dut, lambda: int(dut.uo_out.value[7]) == 0, max_cycles=40)

# Four Word Burst Mode Test
@cocotb.test()
async def test_burst4_mode(dut):
    await _init_clock(dut)
    await _reset_dut(dut)

    src_addr = 0x20
    dst_addr = 0x80
    payload = [0x11, 0x22, 0x33, 0x44]

    await _send_cfg(dut, mode=1, direction=0, src_addr=src_addr, dst_addr=dst_addr)
    await _run_transfer_sequence(dut, src_addr=src_addr, dst_addr=dst_addr, payload=payload, direction=0)

    await _wait_until(dut, lambda: int(dut.uo_out.value[5]) == 1, max_cycles=300)
    await _wait_until(dut, lambda: int(dut.uo_out.value[7]) == 0, max_cycles=120)
