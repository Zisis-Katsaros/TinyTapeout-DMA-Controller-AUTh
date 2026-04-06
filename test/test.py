import cocotb
import random
from itertools import product
from cocotb.triggers import ClockCycles

from randomized_clock_helpers import init_random_clocks
from speed_profile_helpers import init_variable_clocks, period_from_speed

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


    #===============================================================
    # Random clock Tests
    #===============================================================

@cocotb.test()
async def test_randomized_clock_and_transfer_stress(dut):
    rng = random.Random()
    span_percent = 20

    await init_random_clocks(dut, rng, span_percent)
    dut._log.info("=== TEST START: randomized clock stress ===")

    for trial in range(100):
        await reset_dut(dut)

        mode = rng.randint(0, 1)
        direction = rng.randint(0, 1)
        src_addr = rng.randint(0, 0xFF)
        dst_addr = rng.randint(0, 0xFF)
        payload_len = 4 if mode == 1 else 1
        payload = [rng.randint(0, 0xFF) for _ in range(payload_len)]

        dut._log.info(
            f"[trial {trial}] mode={mode}, direction={direction}, "
            f"src=0x{src_addr:02X}, dst=0x{dst_addr:02X}, payload={payload}"
        )

        await send_config(
            dut,
            mode=mode,
            direction=direction,
            src_addr=src_addr,
            dst_addr=dst_addr,
        )

        await run_transfer_sequence(
            dut,
            src_addr=src_addr,
            dst_addr=dst_addr,
            payload=payload,
            direction=direction,
        )

        await wait_for_done(dut, max_cycles=600)
        await wait_until(dut, lambda: get_br(dut) == 0, max_cycles=200, description="BR=0 after completion")

    dut._log.info("=== TEST PASS: randomized clock stress ===")


@cocotb.test()
async def test_all_speed_profile_combinations(dut):
    rng = random.Random(0xA11C0B0)

    dmac_normal_ps = 10_000_000
    mem_normal_ps = 12_500_000
    io_normal_ps = 8_330_000
    speed_delta_percent = 30

    dmac_ref, mem_ref, io_ref = await init_variable_clocks(
        dut,
        rng,
        dmac_normal_ps,
        mem_normal_ps,
        io_normal_ps,
    )

    speed_levels = ("slow", "normal", "fast")

    dut._log.info("=== TEST START: all speed profile combinations ===")

    for dmac_speed, src_speed, dest_speed in product(speed_levels, repeat=3):
        direction = rng.randint(0, 1)
        mode = rng.randint(0, 1)
        src_addr = rng.randint(0, 0xFF)
        dst_addr = rng.randint(0, 0xFF)
        payload_len = 4 if mode == 1 else 1
        payload = [rng.randint(0, 0xFF) for _ in range(payload_len)]

        if direction == 0:
            mem_speed = src_speed
            io_speed = dest_speed
        else:
            mem_speed = dest_speed
            io_speed = src_speed

        dmac_ref["period_ps"] = period_from_speed(dmac_normal_ps, dmac_speed, speed_delta_percent)
        mem_ref["period_ps"] = period_from_speed(mem_normal_ps, mem_speed, speed_delta_percent)
        io_ref["period_ps"] = period_from_speed(io_normal_ps, io_speed, speed_delta_percent)

        await ClockCycles(dut.clk, 4)
        await reset_dut(dut)

        dut._log.info(
            f"Speed case: dmac={dmac_speed}, src={src_speed}, dest={dest_speed}, "
            f"direction={direction}, mode={mode}, "
            f"src=0x{src_addr:02X}, dst=0x{dst_addr:02X}, payload={payload}"
        )

        try:
            await send_config(
                dut,
                mode=mode,
                direction=direction,
                src_addr=src_addr,
                dst_addr=dst_addr,
            )

            await run_transfer_sequence(
                dut,
                src_addr=src_addr,
                dst_addr=dst_addr,
                payload=payload,
                direction=direction,
            )

            await wait_for_done(dut, max_cycles=800)
            await wait_until(dut, lambda: get_br(dut) == 0, max_cycles=240, description="BR=0 after completion")

        except AssertionError as exc:
            raise AssertionError(
                "Speed profile failure: "
                f"dmac={dmac_speed}, src={src_speed}, dest={dest_speed}, "
                f"direction={direction}, mode={mode}, "
                f"src_addr=0x{src_addr:02X}, dst_addr=0x{dst_addr:02X}, payload={payload}; {exc}"
            ) from exc

    dut._log.info("=== TEST PASS: all speed profile combinations ===")