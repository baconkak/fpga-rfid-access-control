"""Run the RTL regression using Vivado XSim or Icarus Verilog (Python 3.9+)."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "RFIDProj/RFIDProj.srcs/sources_1/new/rfid_reader_top.v"
TB = ROOT / "verification/tb_rfid_access.v"


def run(command, cwd):
    # Windows .bat launchers need cmd.exe; list2cmdline preserves path quoting.
    if os.name == "nt" and str(command[0]).lower().endswith((".bat", ".cmd")):
        command = [os.environ.get("COMSPEC", "cmd.exe"), "/d", "/s", "/c",
                   subprocess.list2cmdline([str(arg) for arg in command])]
    result = subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, errors="replace",
                            timeout=180)
    print(result.stdout, end="")
    if result.returncode:
        raise RuntimeError(f"Simulation command failed (exit {result.returncode})")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", choices=("xsim", "iverilog"), default="xsim")
    parser.add_argument("--vivado-bin", type=Path,
                        help="Vivado bin directory, if not on PATH")
    args = parser.parse_args()
    output = ROOT / "build" / ("sim_" + args.simulator)
    output.mkdir(parents=True, exist_ok=True)

    def tool(name):
        if args.vivado_bin:
            candidate = args.vivado_bin / (name + (".bat" if os.name == "nt" else ""))
            if candidate.is_file():
                return str(candidate)
        found = shutil.which(name)
        if not found:
            raise RuntimeError(f"Missing tool: {name}. See README.md for setup.")
        return found

    if args.simulator == "xsim":
        run([tool("xvlog"), str(RTL), str(TB)], output)
        run([tool("xelab"), "tb_rfid_access", "-s", "rfid_regression"], output)
        batch = output / "run.tcl"
        batch.write_text("run all\nquit\n", encoding="utf-8")
        # Tcl interprets backslashes as escapes even in some generated wrappers.
        transcript = run([tool("xsim"), "rfid_regression", "-tclbatch", batch.as_posix()], output)
    else:
        executable = output / "rfid_regression.vvp"
        run([tool("iverilog"), "-g2012", "-s", "tb_rfid_access", "-o",
             str(executable), str(RTL), str(TB)], output)
        transcript = run([tool("vvp"), str(executable)], output)
    (output / "regression.txt").write_text(transcript, encoding="utf-8")
    if "FAIL:" in transcript or not re.search(r"ALL TESTS PASSED \(\d+ checks\)", transcript):
        raise RuntimeError("Simulation did not report a complete passing regression")
    trace = output / "trace.csv"
    if not trace.is_file() or trace.stat().st_size == 0:
        raise RuntimeError("Simulation did not produce a trace")
    print(f"Trace: {trace}")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
