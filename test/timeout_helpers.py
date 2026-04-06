# SPDX-FileCopyrightText: © 2026 Zisis Katsaros
# SPDX-License-Identifier: Apache-2.0

from cocotb.triggers import ClockCycles

from general_test_helpers import _pulse_rtrn, _reset_dut, _send_cfg, _wait_until


IDLE = 0b000
RECEIVE = 0b100
SENDADDR = 0b101
SENDDATA = 0b110


def _get_timeout_limit(dut):
    return int(dut.dut.TIMEOUT_LIMIT.value)


async def _wait_for_state(dut, expected_state, max_cycles=200):
    await _wait_until(
        dut,
        lambda: int(dut.dut.current_state.value) == expected_state,
        max_cycles=max_cycles,
    )


async def _assert_timeout_result(dut):
    assert int(dut.dut.current_state.value) == IDLE, "FSM should return to IDLE after timeout"
    assert int(dut.uo_out.value[7]) == 0, "BR should be low after timeout"
    assert int(dut.uo_out.value[5]) == 0, "done should be low after timeout"


async def _assert_wait_state_active(dut):
    assert int(dut.uo_out.value[7]) == 1, "BR should stay high before timeout"
    assert int(dut.uo_out.value[5]) == 0, "done should stay low while waiting for rtrn"


async def _wait_for_timeout(dut):
    timeout_limit = _get_timeout_limit(dut)
    await ClockCycles(dut.clk, timeout_limit + 5) 
    


async def _prepare_timeout_transaction(dut, src_addr, dst_addr):
    await _reset_dut(dut)
    await _send_cfg(dut, mode=0, direction=0, src_addr=src_addr, dst_addr=dst_addr)
    await _wait_for_state(dut, RECEIVE)


async def _timeout_in_receive(dut, src_addr, dst_addr):
    await _prepare_timeout_transaction(dut, src_addr, dst_addr)

    await _assert_wait_state_active(dut)
    await _wait_for_timeout(dut)
    await _assert_timeout_result(dut)


async def _timeout_in_sendaddr(dut, src_addr, dst_addr, rtrn_delay):
    await _prepare_timeout_transaction(dut, src_addr, dst_addr)

    dut.uio_in.value = 0x5A
    await _pulse_rtrn(dut, sender="mem", bg=1, pre_cycles=rtrn_delay)
    await _wait_for_state(dut, SENDADDR)

    await _assert_wait_state_active(dut)
    await _wait_for_timeout(dut)
    await _assert_timeout_result(dut)


async def _timeout_in_senddata(dut, src_addr, dst_addr, rtrn_delay):
    await _prepare_timeout_transaction(dut, src_addr, dst_addr)

    dut.uio_in.value = 0x5A
    await _pulse_rtrn(dut, sender="mem", bg=1, pre_cycles=rtrn_delay)
    await _wait_for_state(dut, SENDADDR)

    await _pulse_rtrn(dut, sender="io", bg=1, pre_cycles=rtrn_delay)
    await _wait_for_state(dut, SENDDATA)

    await _assert_wait_state_active(dut)
    await _wait_for_timeout(dut)
    await _assert_timeout_result(dut)