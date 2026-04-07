# 6-State DMA Controller Documentation

## Contents

- Overview
- I/O Configuration
- How it works
- State Machine
- How to test

## Overview

This project implements a small DMA controller as a finite state machine (FSM).

The DMA supports two transfer modes:

- single-word transfer mode
- 4-word burst transfer mode

The controller receives its configuration from the CPU through a 4-bit configuration bus over multiple clock cycles. After configuration is loaded, the DMA requests control of the bus, reads data from the source side, and writes it to the destination side.

Both source and destination addresses are 8 bits wide. In burst mode, both addresses are incremented after each transferred word.

This design uses a simple handshake protocol to communicate with external logic over an 8-bit transfer bus. Since the external side may be in a different clock domain, the `fetch` and `external_capture` inputs are synchronized into the DMA clock domain using two-flop synchronizers.

## I/O Configuration

This design targets Tiny Tapeout, so the available I/O is limited to:

- 8 dedicated inputs
- 8 dedicated outputs
- 8 bidirectional pins
- clock and reset

### Inputs

- `ui_in[7]`: `enable`  
  Enables configuration loading. The DMA loads its command while this signal is high.

- `ui_in[6]`: `fetch`  
  Handshake signal from the external side. When high, it indicates that valid input data is present on `uio_in[7:0]` and should be captured by the DMA.

- `ui_in[5]`: `external_capture`  
  Handshake signal from the external side. When high, it indicates that the external side has captured the address or data currently being driven by the DMA.

- `ui_in[4]`: `BG`  
  Bus grant from the CPU/system. When high, the DMA is allowed to begin the transfer.

- `ui_in[3:0]`: `cfg_in[3:0]`  
  4-bit configuration input used to load mode, direction, source address, and destination address over 5 cycles.

### Outputs

The output bus is assigned as:

- `uo_out[0]`: `BR`  
  Bus request signal. The DMA asserts this when requesting control of the system bus.

- `uo_out[1]`: `write_en`  
  Indicates that the current valid byte on the transfer bus is write data for the destination.

- `uo_out[2]`: `done`  
  Indicates that the transfer has completed.

- `uo_out[3]`: `valid`  
  Indicates that the DMA is currently driving a valid byte on the transfer bus.

- `uo_out[4]`: `bus_dir`  
  Direction/target indicator. This distinguishes whether the current transfer is toward the source side or the destination side.

- `uo_out[5]`: `ack`  
  Acknowledge signal. The DMA asserts this after capturing data from `uio_in`.

- `uo_out[6]`: unused

- `uo_out[7]`: unused

### Bidirectional pins

- `uio_in[7:0]`  
  Input path of the transfer bus. Used when the external side sends data into the DMA.

- `uio_out[7:0]`  
  Output path of the transfer bus. Used when the DMA sends source address, destination address, or write data.

- `uio_oe[7:0]`  
  Output enable for the transfer bus. When high, the DMA is driving the bus. When low, the bus is treated as input.

## How it works

The DMA operates in two phases:

1. **Configuration loading**
2. **Transfer execution**

### Configuration loading

Configuration is loaded in state `S0_IDLE_AND_LOAD` while `enable=1`.

The command is loaded over 5 cycles:

1. **Cycle 0**
   - `cfg_in[3]` = transfer mode
   - `cfg_in[2]` = direction
   - `cfg_in[1:0]` unused

2. **Cycle 1**
   - source address upper nibble

3. **Cycle 2**
   - source address lower nibble

4. **Cycle 3**
   - destination address upper nibble

5. **Cycle 4**
   - destination address lower nibble

After the fifth configuration cycle, the DMA moves to bus acquisition.

### Transfer modes

- `mode = 0` → single-word transfer
- `mode = 1` → 4-word burst transfer

A register named `words_left` keeps track of how many words remain.

### Bus request / grant

Once configuration is complete, the DMA asserts `BR` and waits until `BG` is high. This happens in state `S1_BUS_ACCESS`.

### External handshake behavior

This design uses two handshake styles.

#### 1. DMA sends address or data to external logic

When the DMA wants to send a byte:

- it drives `uio_out`
- it enables the bus with `uio_oe`
- it sets `valid=1`

The external side then raises `external_capture=1` to indicate that it received the byte.

The DMA responds by:

- dropping `valid`
- releasing the bus
- waiting for `external_capture` to return to `0`

This handshake is used when sending:

- source address
- destination address
- write data

#### 2. External logic sends data to DMA

When the external side wants to send data into the DMA:

- it drives `uio_in`
- it raises `fetch=1`

The DMA captures the byte and then raises `ack=1`.

The external side then lowers `fetch=0`, and the DMA drops `ack`.

This handshake is used when receiving read data from the source side.

### Burst behavior

In burst mode, after each successful write to the destination:

- `src_addr` is incremented by 1
- `dst_addr` is incremented by 1
- `words_left` is decremented

If more words remain, the DMA loops back to fetch from the next source address.

If no words remain, the DMA asserts `done` and returns to idle.

### Protection against repeated triggering

The signal `wait_enable_low` prevents the DMA from starting a new transfer immediately if `enable` stays high after configuration. The DMA requires `enable` to return low before accepting a new command.

## State Machine

This DMA uses 6 top-level FSM states.

### `S0_IDLE_AND_LOAD`

Idle/configuration state.

- Waits for `enable`
- Loads mode and direction
- Loads source and destination addresses over 5 cycles
- Initializes `words_left`
- Prevents accidental retriggering using `wait_enable_low`

### `S1_BUS_ACCESS`

Bus arbitration state.

- Asserts `BR`
- Waits for `BG`
- Moves to source-address transmission when the bus is granted

### `S2_SEND_SRC_ADDR`

Source-address transmit state.

- Drives `src_addr` onto the transfer bus
- Sets `valid=1`
- Waits for `external_capture`
- After capture completes, releases the bus and moves on

### `S3_RECEIVE_DATA_FROM_SRC_ADDR`

Receive-data state.

- Waits for the external side to provide data and assert `fetch`
- Captures the byte from `uio_in`
- Raises `ack`
- Waits for `fetch` to return low
- Moves to destination-address transmission

### `S4_SEND_DEST_ADDR`

Destination-address transmit state.

- Drives `dst_addr` onto the transfer bus
- Sets `valid=1`
- Waits for `external_capture`
- Releases the bus and moves to data transmission

### `S5_SEND_DATA_TO_DEST_ADDR`

Destination-data transmit state.

- Drives `data_reg` onto the transfer bus
- Sets `valid=1`
- Sets `write_en=1`
- Waits for `external_capture`

After the handshake finishes:

- if this was the last word, asserts `done` and returns to idle
- otherwise increments addresses and loops back to `S2_SEND_SRC_ADDR`

## Internal registers and signals

Important internal registers include:

- `src_addr` : source address
- `dst_addr` : destination address
- `data_reg` : temporary storage for fetched data
- `mode_reg` : selects single or burst mode
- `direction_reg` : stores transfer direction
- `words_left` : number of remaining words
- `cycle_count` : tracks configuration loading cycles
- `phase` : tracks the two-step handshake behavior inside several states
- `wait_enable_low` : prevents repeated triggering
- `fetch_ff1/fetch_ff2` : synchronizer for `fetch`
- `external_capture_ff1/external_capture_ff2` : synchronizer for `external_capture`

## How to test

This project can be tested in simulation by exercising both configuration loading and transfer handshakes.

### Basic test procedure

1. Apply reset.
2. Release reset.
3. Set `enable=1`.
4. Provide the 5 configuration nibbles on `cfg_in` over 5 clock cycles:
   - mode/direction
   - source address high nibble
   - source address low nibble
   - destination address high nibble
   - destination address low nibble
5. Set `enable=0`.
6. Wait for `BR=1`.
7. Assert `BG=1` to grant the bus.
8. Observe the DMA sending the source address with `valid=1`.
9. Raise `external_capture` to acknowledge the source address.
10. Drive data onto `uio_in` and raise `fetch`.
11. Wait for `ack=1`, then lower `fetch`.
12. Observe the DMA sending the destination address with `valid=1`.
13. Raise `external_capture` to acknowledge the destination address.
14. Observe the DMA sending write data with `valid=1` and `write_en=1`.
15. Raise `external_capture` to acknowledge the write data.
16. Check whether:
    - `done` goes high after one word in single mode
    - the DMA repeats for 4 words in burst mode
    - source and destination addresses increment correctly in burst mode

### Things to verify

A good testbench should verify:

- reset behavior
- correct 5-cycle configuration loading
- `BR` assertion during bus request
- proper waiting for `BG`
- proper source address handshake
- proper input data capture with `fetch/ack`
- proper destination address handshake
- proper write-data handshake
- correct `done` behavior
- correct 4-word burst looping
- correct source/destination address incrementing

## Notes

- `fetch` and `external_capture` are asynchronous-style handshake inputs and are synchronized into the DMA clock domain.
- `valid` is only asserted while the DMA is actively driving a meaningful byte onto the bus.
- `ack` is only asserted after the DMA has captured incoming data.
- `uio_oe` is set to all 1s when the DMA drives the transfer bus and to all 0s when the DMA listens.