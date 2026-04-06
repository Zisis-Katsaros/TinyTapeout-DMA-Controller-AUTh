<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

# AUTh DMA Controller Documentation

## Contents

- Overview
- I/O Configuration
- State Diagram
- How to test

## Overview

The core function of the DMA Controller (DMAC) is to take over the system buses and transfer data from memory to an I/O device, or vice versa, when instructed by the CPU. In this implementation, the DMAC is synchronous with the CPU, while memory operates in a second clock domain and the I/O device operates in a third clock domain.

Both word and address width are 8 bits. The DMAC supports two operating modes:

- Single-word transfer mode
- Four-word burst mode

In burst mode, both source and destination addresses are incremented by 1 after each transfer. The DMAC is implemented as a finite state machine (FSM).

## I/O Configuration

Since this project is submitted to a Tiny Tapeout shuttle, there is a strict pin budget: 8 input pins, 8 output pins, 8 bidirectional pins, and 2 pins for clock and reset.

The I/O pins are configured as follows.

### Inputs

- `ui[7]`: `start` - Sent by the CPU to indicate that transfer instructions are about to be provided.
- `ui[6]`: `BG` - Sent by the CPU to indicate that the DMAC is granted control of the system bus.
- `ui[5]`: `rtrn` - Sent by either memory or the I/O device to indicate either: (i) data sent by the DMAC has been received, or (ii) data loaded onto the transfer bus is ready to be read.
- `ui[4:0]`: `cfg_in[4:0]` - Configuration input from the CPU over 4 cycles, carrying mode, direction, source address, and destination address.

### Outputs

- `uo[7]`: `BR` - Sent to the CPU to request control of the system bus.
- `uo[6]`: `WRITE_en` - Sent to memory or the I/O device to indicate whether data should be written or read.
- `uo[5]`: `done` - Sent to the CPU when all transfers are complete.
- `uo[4]`: `valid` - Sent to memory or the I/O device to indicate that address/data on the transfer bus is valid.
- `uo[3]`: `ack` - Sent to memory or the I/O device to indicate that the DMAC has received incoming data.
- `uo[2]`: `target` - Indicates whether transfer bus address/data is intended for memory or the I/O device.
- `uo[1:0]`: Unused.

### Bidirectional

- `uio[7:0]`: `transfer_bus[7:0]`

## State Diagram

### States

- `S0: IDLE` - Idle state before `start` is asserted.
- `S1: PREPARATION` - Loading CPU instructions.
- `S2: WAIT4BG` - Waiting for the CPU to grant control over the system bus.
- `S3: SRC_SEND` - Sending address to source.
- `S4: RECEIVE` - Receiving data from source.
- `S5: SENDaddr` - Sending address to destination.
- `S6: SENDdata` - Sending data to destination.

![DMAC State Diagram](STATE_DIAGRAM_3.PNG)

Notes:

- In the state diagram above, `rtrn_rise` is an internal pulse generated shortly after `rtrn` rises to high.
- `wrds_lft` is not an actual signal; it indicates whether there are still words left to transfer in four-word burst mode.

How to Run & Test 
This project uses a cocotb-based Python testbench and runs simulation with Icarus Verilog. The entry point for this flow is test/run_cocotb.py.

1. Requirements
You need all of the following:

Python 3.10+ (Tested up to Python 3.14).

pip (Python package installer).

Icarus Verilog (iverilog and vvp available in PATH).

The Python packages in test/requirements.txt.

Optional but Recommended:

Surfer (Modern waveform viewer for macOS/Linux/Windows).

GTKWave (Classic waveform viewing).

2. Install System Dependencies
Install Icarus Verilog first.

macOS (Homebrew): brew install icarus-verilog

Windows (winget): winget install IcarusVerilog.IcarusVerilog

Linux (Ubuntu): sudo apt update && sudo apt install -y iverilog

Waveform Viewers:

Surfer (macOS): Download the .dmg from the official Surfer GitHub.

Note: On macOS, if it blocks opening, right-click the app and select Open.

GTKWave: brew install --cask gtkwave (macOS).

3. Create and Activate a Python Virtual Environment
Crucial for macOS users to avoid "externally-managed-environment" errors.

From repository root:

macOS/Linux:

Bash
python3 -m venv .venv
source .venv/bin/activate
Windows (PowerShell):

PowerShell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
4. Install Python Test Dependencies
With .venv activated:

Bash
python -m pip install --upgrade pip
python -m pip install -r test/requirements.txt
Special Case: Python 3.14+ (macOS Compatibility)

If you are using Python 3.14 or newer, cocotb might block installation due to version checks. Use this workaround:

Bash
export COCOTB_IGNORE_PYTHON_REQUIRES=1
pip install cocotb cocotb-bus pytest
5. Verify Tools
Bash
iverilog -V
python -c "import cocotb; print(cocotb.__version__)"
6. Run the Cocotb Flow
From repository root:

Bash
python3 test/run_cocotb.py
Note for macOS: If run_cocotb.py fails with ModuleNotFoundError: No module named 'cocotb_tools', ensure your script uses from cocotb.runner import get_runner (updated syntax).

7. Expected Results
You should see: TESTS=4 PASS=4 FAIL=0 SKIP=0.
The suite validates:

test_single_word_mode

test_burst4_mode

test_randomized_clock_and_transfer_stress (Validates 2-FF Synchronizers).

test_all_speed_profile_combinations (Validates Async Handshaking).

8. Waveform Viewing (The "Visual" Test)
After a successful run, a waveform file is generated at test/sim_build/rtl/tb.fst (or .vcd).

Using Surfer (Recommended):

Open Surfer.

Drag and drop test/sim_build/rtl/tb.fst into the window.

Observe the rtrn_rise and state transitions to verify the DMA logic.

9. Troubleshooting (Common Issues)
Error: externally-managed-environment: You are not using a Virtual Environment. See Step 3.

Error: cocotb 2.0.1 only supports up to Python 3.13: See Step 4 for the COCOTB_IGNORE_PYTHON_REQUIRES=1 fix.

ModuleNotFoundError: cocotb_tools:

Install explicitly: pip install cocotb-tools

OR update run_cocotb.py to import from cocotb.runner.

Zsh parse error: Ensure you are not pasting multi-line comments directly into the terminal without proper escaping.
