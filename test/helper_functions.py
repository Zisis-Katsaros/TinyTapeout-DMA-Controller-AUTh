import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


# ---------------------------------------------------------
# Pack ui_in according to your CURRENT RTL:
# ui_in[7]   = enable
# ui_in[6]   = fetch
# ui_in[5]   = external_capture
# ui_in[4]   = BG
# ui_in[3:0] = cfg_in
# ---------------------------------------------------------
def set_ui_in(dut, enable=0, fetch=0, external_capture=0, bg=0, cfg=0):
    value = (
        ((enable & 1) << 7)
        | ((fetch & 1) << 6)
        | ((external_capture & 1) << 5)
        | ((bg & 1) << 4)
        | (cfg & 0xF)
    )
    dut.ui_in.value = value


# ---------------------------------------------------------
# Decode uo_out according to your CURRENT RTL:
# uo_out = {2'b00, ack, bus_dir, valid, done, write_en, BR}
#
# bit 0 = BR
# bit 1 = write_en
# bit 2 = done
# bit 3 = valid
# bit 4 = bus_dir
# bit 5 = ack
# ---------------------------------------------------------
def get_status_bits(dut):
    val = int(dut.uo_out.value)
    return {
        "BR":       (val >> 0) & 1,
        "write_en": (val >> 1) & 1,
        "done":     (val >> 2) & 1,
        "valid":    (val >> 3) & 1,
        "bus_dir":  (val >> 4) & 1,
        "ack":      (val >> 5) & 1,
    }


def get_br(dut):
    return get_status_bits(dut)["BR"]


def get_write_en(dut):
    return get_status_bits(dut)["write_en"]


def get_done(dut):
    return get_status_bits(dut)["done"]


def get_valid(dut):
    return get_status_bits(dut)["valid"]


def get_bus_dir(dut):
    return get_status_bits(dut)["bus_dir"]


def get_ack(dut):
    return get_status_bits(dut)["ack"]


# ---------------------------------------------------------
# Wait helpers
# ---------------------------------------------------------
async def wait_until(dut, predicate, max_cycles=100, description="condition"):
    for _ in range(max_cycles):
        if predicate():
            return
        await ClockCycles(dut.clk, 1)
    raise AssertionError(f"Timeout waiting for {description} after {max_cycles} DMA clock cycles")


async def wait_for_br(dut, max_cycles=100):
    dut._log.info("Waiting for BR=1")
    await wait_until(dut, lambda: get_br(dut) == 1, max_cycles=max_cycles, description="BR=1")
    dut._log.info("Observed BR=1")


async def wait_for_done(dut, max_cycles=100):
    dut._log.info("Waiting for done=1")
    await wait_until(dut, lambda: get_done(dut) == 1, max_cycles=max_cycles, description="done=1")
    dut._log.info("Observed done=1")


async def wait_for_valid(dut, expected_write_en=None, max_cycles=200):
    if expected_write_en is None:
        dut._log.info("Waiting for valid=1")
    else:
        dut._log.info(f"Waiting for valid=1 with write_en={expected_write_en}")

    for _ in range(max_cycles):
        await ClockCycles(dut.clk, 1)
        if get_valid(dut) == 1:
            if expected_write_en is None:
                dut._log.info("Observed valid=1")
                return
            if get_write_en(dut) == expected_write_en:
                dut._log.info(f"Observed valid=1 and write_en={expected_write_en}")
                return

    raise AssertionError("Timeout waiting for valid phase")


async def wait_for_ack(dut, max_cycles=200):
    dut._log.info("Waiting for ack=1")
    await wait_until(dut, lambda: get_ack(dut) == 1, max_cycles=max_cycles, description="ack=1")
    dut._log.info("Observed ack=1")


# ---------------------------------------------------------
# Clock / reset
# ---------------------------------------------------------
async def init_clocks(dut):
    dut._log.info("Starting clocks: clk, mem_clk, io_clk")
    cocotb.start_soon(Clock(dut.clk, 10, unit="us").start())
    cocotb.start_soon(Clock(dut.mem_clk, 12.5, unit="us").start())
    cocotb.start_soon(Clock(dut.io_clk, 8.33, unit="us").start())

    await ClockCycles(dut.clk, 3)
    dut._log.info("Clocks started")


async def reset_dut(dut):
    dut._log.info("Resetting DUT")
    dut.ena.value = 1
    dut.uio_in.value = 0
    set_ui_in(dut, enable=0, fetch=0, external_capture=0, bg=0, cfg=0)

    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)

    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    dut._log.info("Reset complete")


# ---------------------------------------------------------
# Config loading for your CURRENT RTL:
# cycle 0: cfg[3]=mode, cfg[2]=direction
# cycle 1: src_addr[7:4]
# cycle 2: src_addr[3:0]
# cycle 3: dst_addr[7:4]
# cycle 4: dst_addr[3:0]
# ---------------------------------------------------------
async def send_config(dut, mode, direction, src_addr, dst_addr):
    cfg_words = [
        ((mode & 1) << 3) | ((direction & 1) << 2),
        (src_addr >> 4) & 0xF,
        src_addr & 0xF,
        (dst_addr >> 4) & 0xF,
        dst_addr & 0xF,
    ]

    dut._log.info(
        f"Sending config: mode={mode}, direction={direction}, "
        f"src=0x{src_addr:02X}, dst=0x{dst_addr:02X}"
    )

    for i, word in enumerate(cfg_words):
        dut._log.info(f"  cfg cycle {i}: cfg=0x{word:X}")
        set_ui_in(dut, enable=1, fetch=0, external_capture=0, bg=0, cfg=word)
        await ClockCycles(dut.clk, 1)

    dut._log.info("Lowering enable after config load")
    set_ui_in(dut, enable=0, fetch=0, external_capture=0, bg=0, cfg=0)

    await wait_for_br(dut, max_cycles=120)

    dut._log.info("Granting bus with BG=1")
    await ClockCycles(dut.clk, 2)
    set_ui_in(dut, enable=0, fetch=0, external_capture=0, bg=1, cfg=0)


# ---------------------------------------------------------
# Handshake helpers
# ---------------------------------------------------------

# Case 1:
# DMA is driving address/data out.
# External side responds using external_capture.
async def external_accept_dma_output(dut, actor_clk, pre_cycles=2):
    current_ui = int(dut.ui_in.value)
    bg = (current_ui >> 4) & 1

    dut._log.info(f"External side waiting {pre_cycles} external-clock cycles before external_capture")
    await ClockCycles(actor_clk, pre_cycles)

    dut._log.info("External side raises external_capture=1")
    set_ui_in(dut, enable=0, fetch=0, external_capture=1, bg=bg, cfg=0)

    await wait_until(dut, lambda: get_valid(dut) == 0, max_cycles=200, description="valid to drop after external_capture")

    dut._log.info("DMA dropped valid, external side lowers external_capture=0")
    set_ui_in(dut, enable=0, fetch=0, external_capture=0, bg=bg, cfg=0)
    await ClockCycles(actor_clk, 1)


# Case 2:
# External side is driving read data into DMA.
# External side raises fetch and keeps it high until DMA raises ack.
async def external_send_data_to_dma(dut, actor_clk, data, pre_cycles=2):
    current_ui = int(dut.ui_in.value)
    bg = (current_ui >> 4) & 1

    dut._log.info(f"External source drives read data 0x{data:02X} onto uio_in")
    dut.uio_in.value = data

    dut._log.info(f"External source waiting {pre_cycles} external-clock cycles before fetch")
    await ClockCycles(actor_clk, pre_cycles)

    dut._log.info("External source raises fetch=1")
    set_ui_in(dut, enable=0, fetch=1, external_capture=0, bg=bg, cfg=0)

    await wait_for_ack(dut, max_cycles=200)

    dut._log.info("DMA acknowledged input data, external source lowers fetch=0")
    set_ui_in(dut, enable=0, fetch=0, external_capture=0, bg=bg, cfg=0)
    await ClockCycles(actor_clk, 1)


# ---------------------------------------------------------
# Phase check helpers
# ---------------------------------------------------------
async def check_source_address_phase(dut, expected_src_addr, expected_direction):
    dut._log.info("Checking source-address phase")
    await wait_for_valid(dut, expected_write_en=0, max_cycles=300)

    observed_addr = int(dut.uio_out.value)
    observed_oe = int(dut.uio_oe.value)
    observed_dir = get_bus_dir(dut)

    dut._log.info(
        f"Observed source phase: addr=0x{observed_addr:02X}, "
        f"uio_oe=0x{observed_oe:02X}, bus_dir={observed_dir}"
    )

    assert observed_oe == 0xFF, "DMA should drive the bus during source-address phase"
    assert observed_addr == expected_src_addr, (
        f"Source address mismatch: got 0x{observed_addr:02X}, expected 0x{expected_src_addr:02X}"
    )
    assert observed_dir == expected_direction, (
        f"bus_dir mismatch in source-address phase: got {observed_dir}, expected {expected_direction}"
    )


async def check_destination_address_phase(dut, expected_dst_addr, expected_direction):
    dut._log.info("Checking destination-address phase")
    await wait_for_valid(dut, expected_write_en=0, max_cycles=300)

    observed_addr = int(dut.uio_out.value)
    observed_oe = int(dut.uio_oe.value)
    observed_dir = get_bus_dir(dut)

    dut._log.info(
        f"Observed destination phase: addr=0x{observed_addr:02X}, "
        f"uio_oe=0x{observed_oe:02X}, bus_dir={observed_dir}"
    )

    assert observed_oe == 0xFF, "DMA should drive the bus during destination-address phase"
    assert observed_addr == expected_dst_addr, (
        f"Destination address mismatch: got 0x{observed_addr:02X}, expected 0x{expected_dst_addr:02X}"
    )
    assert observed_dir == expected_direction, (
        f"bus_dir mismatch in destination-address phase: got {observed_dir}, expected {expected_direction}"
    )


async def check_write_data_phase(dut, expected_data, expected_direction):
    dut._log.info("Checking write-data phase")
    await wait_for_valid(dut, expected_write_en=1, max_cycles=300)

    observed_data = int(dut.uio_out.value)
    observed_oe = int(dut.uio_oe.value)
    observed_dir = get_bus_dir(dut)
    observed_we = get_write_en(dut)

    dut._log.info(
        f"Observed write-data phase: data=0x{observed_data:02X}, "
        f"uio_oe=0x{observed_oe:02X}, bus_dir={observed_dir}, write_en={observed_we}"
    )

    assert observed_oe == 0xFF, "DMA should drive the bus during write-data phase"
    assert observed_data == expected_data, (
        f"Write-data mismatch: got 0x{observed_data:02X}, expected 0x{expected_data:02X}"
    )
    assert observed_dir == expected_direction, (
        f"bus_dir mismatch in write-data phase: got {observed_dir}, expected {expected_direction}"
    )
    assert observed_we == 1, "write_en should be 1 during write-data phase"


# ---------------------------------------------------------
# Run one whole transfer sequence
# direction 0: mem -> io
# direction 1: io -> mem
# ---------------------------------------------------------
async def run_transfer_sequence(dut, src_addr, dst_addr, payload, direction):
    if direction == 0:
        source_clk = dut.mem_clk
        destination_clk = dut.io_clk
        dut._log.info("Running transfer sequence: mem -> io")
    else:
        source_clk = dut.io_clk
        destination_clk = dut.mem_clk
        dut._log.info("Running transfer sequence: io -> mem")

    for i, datum in enumerate(payload):
        expected_src_addr = (src_addr + i) & 0xFF
        expected_dst_addr = (dst_addr + i) & 0xFF

        dut._log.info(
            f"--- Beat {i}: expected_src=0x{expected_src_addr:02X}, "
            f"expected_dst=0x{expected_dst_addr:02X}, data=0x{datum:02X} ---"
        )

        # 1. DMA sends source address
        await check_source_address_phase(dut, expected_src_addr, expected_direction=direction)
        await external_accept_dma_output(dut, source_clk)

        # 2. External source returns data to DMA
        await external_send_data_to_dma(dut, source_clk, datum)

        # 3. DMA sends destination address
        await check_destination_address_phase(dut, expected_dst_addr, expected_direction=(direction ^ 1))
        await external_accept_dma_output(dut, destination_clk)

        # 4. DMA sends write data
        await check_write_data_phase(dut, datum, expected_direction=(direction ^ 1))
        await external_accept_dma_output(dut, destination_clk)

    dut._log.info("Transfer sequence complete")