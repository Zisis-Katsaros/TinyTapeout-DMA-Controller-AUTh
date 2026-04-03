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

    # Send BG and pull down start
    dut.ui_in.value = _pack_ui(start=0, bg=1, rtrn=0, cfg=0)

# Send rtrn pulse via 2FF synchronizer
async def _pulse_rtrn(dut, bg=1):
    dut.ui_in.value = _pack_ui(start=0, bg=bg, rtrn=0, cfg=0)
    await ClockCycles(dut.clk, 2)
    dut.ui_in.value = _pack_ui(start=0, bg=bg, rtrn=1, cfg=0)
    await ClockCycles(dut.clk, 3)
    dut.ui_in.value = _pack_ui(start=0, bg=bg, rtrn=0, cfg=0)
    await ClockCycles(dut.clk, 1)


async def _run_transfer_sequence(dut, src_addr, dst_addr, payload):
    for i, datum in enumerate(payload):
        # Expected addresses (increment for burst mode)
        exp_src = (src_addr + i) & 0xFF
        exp_dst = (dst_addr + i) & 0xFF

        # SRC_SEND phase: DMA drives source address with valid and WRITE_en=0.
        await _wait_until(
            dut,
            lambda: int(dut.uo_out.value[4]) == 1 and int(dut.uo_out.value[6]) == 0,
            max_cycles=120,
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
        await _pulse_rtrn(dut, bg=1)

        # SENDaddr phase: DMA presents destination address with valid and WRITE_en=1.
        await _wait_until(
            dut,
            lambda: int(dut.uo_out.value[4]) == 1
            and int(dut.uo_out.value[6]) == 1
            and int(dut.uio_out.value) == exp_dst,
            max_cycles=120,
        )
        await _pulse_rtrn(dut, bg=1)

        # SENDdata phase: DMA presents captured data with valid and WRITE_en=1.
        await _wait_until(
            dut,
            lambda: int(dut.uo_out.value[4]) == 1
            and int(dut.uo_out.value[6]) == 1
            and int(dut.uio_out.value) == (datum & 0xFF),
            max_cycles=120,
        )
        await _pulse_rtrn(dut, bg=1)


async def _init_clock(dut):
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

# Single Word Mode Test
@cocotb.test()
async def test_single_word_mode(dut):
    await _init_clock(dut)
    await _reset_dut(dut)

    src_addr = 0x34
    dst_addr = 0xA1
    payload = [0x5C]

    await _send_cfg(dut, mode=0, direction=0, src_addr=src_addr, dst_addr=dst_addr)
    await _run_transfer_sequence(dut, src_addr=src_addr, dst_addr=dst_addr, payload=payload)

    await _wait_until(dut, lambda: int(dut.uo_out.value[5]) == 1, max_cycles=80)
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
    await _run_transfer_sequence(dut, src_addr=src_addr, dst_addr=dst_addr, payload=payload)

    await _wait_until(dut, lambda: int(dut.uo_out.value[5]) == 1, max_cycles=120)
    await _wait_until(dut, lambda: int(dut.uo_out.value[7]) == 0, max_cycles=60)
