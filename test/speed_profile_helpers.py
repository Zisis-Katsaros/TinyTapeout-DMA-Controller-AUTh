# SPDX-FileCopyrightText: © 2026 Zisis Katsaros
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.triggers import ClockCycles, Timer


def _period_from_speed(normal_ps, speed, delta_percent):
    if speed == "slow":
        factor = 1 + (delta_percent / 100)
    elif speed == "fast":
        factor = 1 - (delta_percent / 100)
    else:
        factor = 1.0
    period = int(normal_ps * factor)
    return max(2, period - (period % 2))


async def _variable_clock_with_phase(signal, period_ref, phase_ps):
    if phase_ps > 0:
        await Timer(phase_ps, unit="ps")

    signal.value = 0
    while True:
        period_ps = max(2, int(period_ref["period_ps"]))
        low_ps = period_ps // 2
        high_ps = period_ps - low_ps
        await Timer(low_ps, unit="ps")
        signal.value = 1
        await Timer(high_ps, unit="ps")
        signal.value = 0


async def _init_variable_clocks(dut, rng, dmac_period_ps, mem_period_ps, io_period_ps):
    dmac_ref = {"period_ps": dmac_period_ps}
    mem_ref = {"period_ps": mem_period_ps}
    io_ref = {"period_ps": io_period_ps}

    dmac_phase = 0
    mem_phase = rng.randint(0, max(mem_period_ps - 1, 0))
    io_phase = rng.randint(0, max(io_period_ps - 1, 0))

    dut.clk.value = 0
    dut.mem_clk.value = 0
    dut.io_clk.value = 0

    cocotb.start_soon(_variable_clock_with_phase(dut.clk, dmac_ref, dmac_phase))
    cocotb.start_soon(_variable_clock_with_phase(dut.mem_clk, mem_ref, mem_phase))
    cocotb.start_soon(_variable_clock_with_phase(dut.io_clk, io_ref, io_phase))

    await ClockCycles(dut.clk, 3)
    return dmac_ref, mem_ref, io_ref
