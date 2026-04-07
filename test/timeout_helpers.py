# SPDX-FileCopyrightText: © 2026 Zisis Katsaros
# SPDX-License-Identifier: Apache-2.0

from cocotb.triggers import ClockCycles
from general_test_helpers import _pulse_rtrn, _reset_dut, _send_cfg, _wait_until, _init_clock


async def _assert_timeout_result(dut):
    assert int(dut.uo_out.value[7]) == 0, "BR should be low after timeout"
    assert int(dut.uo_out.value[5]) == 0, "done should be low after timeout"


async def _assert_wait_state_active(dut):
    assert int(dut.uo_out.value[7]) == 1, "BR should stay high before timeout"
    assert int(dut.uo_out.value[5]) == 0, "done should stay low while waiting for rtrn"


async def _timeout_in_receive(dut, src_addr, dst_addr, timeout_limit=200, phase_wait_cycles=300):
    await _init_clock(dut)
    await _reset_dut(dut)

    await _send_cfg(dut, mode=0, direction=0, src_addr=src_addr, dst_addr=dst_addr)

    direction = 0 # hardcoded, without loss of generality
    receive_sender = "mem" if direction == 0 else "io"
    send_sender = "io" if direction == 0 else "mem"
    source_target = direction
    dest_target = direction ^ 1

    # SRC_SEND phase: DMA drives source address with valid and WRITE_en=0.
    await _wait_until(
        dut,
        lambda: int(dut.uo_out.value[4]) == 1 and int(dut.uo_out.value[6]) == 0,
        max_cycles=phase_wait_cycles,
    )

    await _assert_wait_state_active(dut)
    await ClockCycles(dut.clk, timeout_limit+2)
    await _assert_timeout_result(dut)


async def _timeout_in_sendaddr(dut, src_addr, dst_addr, payload, rtrn_delay, timeout_limit=200, phase_wait_cycles=300):
    await _init_clock(dut)
    await _reset_dut(dut)

    await _send_cfg(dut, mode=0, direction=0, src_addr=src_addr, dst_addr=dst_addr)

    direction = 0 # hardcoded, without loss of generality
    receive_sender = "mem" if direction == 0 else "io"
    send_sender = "io" if direction == 0 else "mem"
    source_target = direction
    dest_target = direction ^ 1

    # SRC_SEND phase: DMA drives source address with valid and WRITE_en=0.
    await _wait_until(
        dut,
        lambda: int(dut.uo_out.value[4]) == 1 and int(dut.uo_out.value[6]) == 0,
        max_cycles=phase_wait_cycles,
    )

    # RECEIVE phase: source returns data, signaled by rtrn rising edge.
    dut.uio_in.value = payload[0]
    await _pulse_rtrn(dut, sender=receive_sender, bg=1, pre_cycles=rtrn_delay)

    # SENDaddr phase: No rtrn
    await _assert_wait_state_active(dut)
    await ClockCycles(dut.clk, timeout_limit+2)
    await _assert_timeout_result(dut)


async def _timeout_in_senddata(dut, src_addr, dst_addr, payload, rtrn_delay, timeout_limit=200, phase_wait_cycles=300):
    await _init_clock(dut)
    await _reset_dut(dut)

    await _send_cfg(dut, mode=0, direction=0, src_addr=src_addr, dst_addr=dst_addr)

    direction = 0 # hardcoded, without loss of generality
    receive_sender = "mem" if direction == 0 else "io"
    send_sender = "io" if direction == 0 else "mem"
    source_target = direction
    dest_target = direction ^ 1

    # SRC_SEND phase: DMA drives source address with valid and WRITE_en=0.
    await _wait_until(
        dut,
        lambda: int(dut.uo_out.value[4]) == 1 and int(dut.uo_out.value[6]) == 0,
        max_cycles=phase_wait_cycles,
    )

    # RECEIVE phase: source returns data, signaled by rtrn rising edge.
    dut.uio_in.value = payload[0]
    await _pulse_rtrn(dut, sender=receive_sender, bg=1, pre_cycles=rtrn_delay)

    # SENDaddr phase: DMA presents destination address with valid and WRITE_en=1.
    await _wait_until(
        dut,
        lambda: int(dut.uo_out.value[4]) == 1 and int(dut.uo_out.value[6]) == 1,
        max_cycles=phase_wait_cycles,
    )
    await _pulse_rtrn(dut, sender=send_sender, bg=1, pre_cycles=rtrn_delay)

    # SENDdata phase: No rtrn
    await _assert_wait_state_active(dut)
    await ClockCycles(dut.clk, timeout_limit+2)
    await _assert_timeout_result(dut)