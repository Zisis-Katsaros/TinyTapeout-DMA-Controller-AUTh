import cocotb
from helper_functions import (
    init_clocks,
    reset_dut,
    send_config,
    run_transfer_sequence,
    wait_for_done,
    wait_until,
    get_br,
)


@cocotb.test()
async def test_single_word_mem_to_io(dut):
    dut._log.info("=== TEST START: single word mem -> io ===")

    await init_clocks(dut)
    await reset_dut(dut)

    src_addr = 0x34
    dst_addr = 0xA1
    payload = [0x5C]
    direction = 0  # mem -> io

    dut._log.info(
        f"Config: mode=0, direction={direction}, "
        f"src_addr=0x{src_addr:02X}, dst_addr=0x{dst_addr:02X}, payload={payload}"
    )

    await send_config(dut, mode=0, direction=direction, src_addr=src_addr, dst_addr=dst_addr)
    await run_transfer_sequence(dut, src_addr=src_addr, dst_addr=dst_addr, payload=payload, direction=direction)

    dut._log.info("Waiting for done flag")
    await wait_for_done(dut, max_cycles=200)

    dut._log.info("Checking that BR returns low after completion")
    await wait_until(dut, lambda: get_br(dut) == 0, max_cycles=80)

    assert get_br(dut) == 0, "BR should be low after transfer completion"

    dut._log.info("=== TEST PASS: single word mem -> io ===")


@cocotb.test()
async def test_single_word_io_to_mem(dut):
    dut._log.info("=== TEST START: single word io -> mem ===")

    await init_clocks(dut)
    await reset_dut(dut)

    src_addr = 0x22
    dst_addr = 0x91
    payload = [0xA7]
    direction = 1  # io -> mem

    dut._log.info(
        f"Config: mode=0, direction={direction}, "
        f"src_addr=0x{src_addr:02X}, dst_addr=0x{dst_addr:02X}, payload={payload}"
    )

    await send_config(dut, mode=0, direction=direction, src_addr=src_addr, dst_addr=dst_addr)
    await run_transfer_sequence(dut, src_addr=src_addr, dst_addr=dst_addr, payload=payload, direction=direction)

    dut._log.info("Waiting for done flag")
    await wait_for_done(dut, max_cycles=200)

    dut._log.info("Checking that BR returns low after completion")
    await wait_until(dut, lambda: get_br(dut) == 0, max_cycles=80)

    assert get_br(dut) == 0, "BR should be low after transfer completion"

    dut._log.info("=== TEST PASS: single word io -> mem ===")


@cocotb.test()
async def test_burst4_mem_to_io(dut):
    dut._log.info("=== TEST START: burst4 mem -> io ===")

    await init_clocks(dut)
    await reset_dut(dut)

    src_addr = 0x20
    dst_addr = 0x80
    payload = [0x11, 0x22, 0x33, 0x44]
    direction = 0  # mem -> io

    dut._log.info(
        f"Config: mode=1, direction={direction}, "
        f"src_addr=0x{src_addr:02X}, dst_addr=0x{dst_addr:02X}, payload={payload}"
    )

    await send_config(dut, mode=1, direction=direction, src_addr=src_addr, dst_addr=dst_addr)
    await run_transfer_sequence(dut, src_addr=src_addr, dst_addr=dst_addr, payload=payload, direction=direction)

    dut._log.info("Waiting for done flag")
    await wait_for_done(dut, max_cycles=400)

    dut._log.info("Checking that BR returns low after completion")
    await wait_until(dut, lambda: get_br(dut) == 0, max_cycles=160)

    assert get_br(dut) == 0, "BR should be low after burst completion"

    dut._log.info("=== TEST PASS: burst4 mem -> io ===")


@cocotb.test()
async def test_burst4_io_to_mem(dut):
    dut._log.info("=== TEST START: burst4 io -> mem ===")

    await init_clocks(dut)
    await reset_dut(dut)

    src_addr = 0x18
    dst_addr = 0x70
    payload = [0xDE, 0xAD, 0xBE, 0xEF]
    direction = 1  # io -> mem

    dut._log.info(
        f"Config: mode=1, direction={direction}, "
        f"src_addr=0x{src_addr:02X}, dst_addr=0x{dst_addr:02X}, payload={payload}"
    )

    await send_config(dut, mode=1, direction=direction, src_addr=src_addr, dst_addr=dst_addr)
    await run_transfer_sequence(dut, src_addr=src_addr, dst_addr=dst_addr, payload=payload, direction=direction)

    dut._log.info("Waiting for done flag")
    await wait_for_done(dut, max_cycles=400)

    dut._log.info("Checking that BR returns low after completion")
    await wait_until(dut, lambda: get_br(dut) == 0, max_cycles=160)

    assert get_br(dut) == 0, "BR should be low after burst completion"

    dut._log.info("=== TEST PASS: burst4 io -> mem ===")