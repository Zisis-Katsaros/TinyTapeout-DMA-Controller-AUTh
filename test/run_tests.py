#!/usr/bin/env python3
"""Simple cocotb test runner for Windows (no make required)"""

import os
import sys
from pathlib import Path

# Add test directory to path for imports
test_dir = Path(__file__).parent
sys.path.insert(0, str(test_dir))

try:
    from cocotb_tools.runner import get_runner
    
    src_dir = test_dir.parent / "src"
    build_dir = test_dir / "sim_build" / "rtl"
    
    # Create runner
    runner = get_runner("icarus")
    
    # Build
    print("Building testbench...")
    runner.build(
        sources=[
            str(src_dir / "project.v"),
            str(test_dir / "tb.v"),
        ],
        hdl_toplevel="tb",
        always=True,
        build_dir=str(build_dir),
        waves=True,
    )
    
    # Run tests
    print("Running tests...")
    runner.test(
        hdl_toplevel="tb",
        test_module="test",
        build_dir=str(build_dir),
        test_dir=str(test_dir),
        waves=True,
        plusargs=["dumpfile_path=tb.vcd"],
        extra_env={
            "PYTHONPATH": str(test_dir) + os.pathsep + os.environ.get("PYTHONPATH", "")
        },
    )
    
except ImportError as e:
    print(f"Error: {e}")
    print("\nTrying alternative method...")
    print("Install cocotb-tools: pip install git+https://github.com/cocotb/cocotb-tools.git")
