from pathlib import Path
import os

from cocotb_tools.runner import get_runner


def main() -> None:
    root = Path(__file__).resolve().parent
    src = root.parent / "src" / "project.v"
    tb = root / "tb.v"
    build_dir = root / "sim_build" / "rtl"

    runner = get_runner("icarus")
    runner.build(
        sources=[src, tb],
        hdl_toplevel="tb",
        always=True,
        build_dir=str(build_dir),
        waves=True,
    )
    runner.test(
        hdl_toplevel="tb",
        test_module="test",
        build_dir=str(build_dir),
        test_dir=str(root),
        waves=True,
        plusargs=["dumpfile_path=tb.vcd"],
        extra_env={
            "PYTHONPATH": str(root) + os.pathsep + os.environ.get("PYTHONPATH", "")
        },
    )


if __name__ == "__main__":
    main()
