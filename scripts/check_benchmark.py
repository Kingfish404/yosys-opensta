#!/usr/bin/env python3
"""Validate a benchmark synthesis + STA result directory.

Checks performed:
  1. Yosys log: no ``ERROR:`` lines, design was actually parsed.
  2. ``synth_stat.txt`` exists and contains a non-trivial mapped cell count
     for the requested platform.
  3. ``synth_check.txt`` contains no critical issues (e.g. unmapped memories
     left in the netlist after technology mapping).
  4. ``sta.log`` reports a real timing path against the target clock and
     emits both ``period_min`` and ``fmax`` summary lines, plus a chip-area
     line -- confirming STA actually evaluated the design against the chosen
     standard-cell library rather than silently producing an empty report.

Exit code is non-zero on any failure.

Usage::

    python3 scripts/check_benchmark.py result/nangate45-picorv32-50MHz \
        --design picorv32 --clk-port clk --min-cells 500
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def fail(messages: list[str], msg: str) -> None:
    messages.append(f"  - {msg}")


def check_yosys_log(result_dir: Path, design: str, errors: list[str]) -> None:
    log = result_dir / "yosys.log"
    if not log.is_file() or log.stat().st_size == 0:
        fail(errors, f"missing or empty yosys.log: {log}")
        return
    text = log.read_text(errors="replace")
    # Yosys prints "ERROR: ..." on hard failures. Some plugins use ERROR for
    # info -- restrict to the canonical leading "ERROR:" prefix.
    err_lines = [ln for ln in text.splitlines() if ln.startswith("ERROR:")]
    if err_lines:
        fail(errors, "yosys.log contains ERROR lines:")
        for ln in err_lines[:5]:
            errors.append(f"      {ln}")
    if f"DESIGN: {design}" not in text:
        fail(errors, f"yosys.log does not show 'DESIGN: {design}' -- top not parsed?")


def _extract_int(pattern: str, text: str) -> int | None:
    m = re.search(pattern, text)
    return int(m.group(1)) if m else None


def check_synth_stat(result_dir: Path, min_cells: int, errors: list[str]) -> None:
    stat = result_dir / "synth_stat.txt"
    if not stat.is_file():
        fail(errors, f"missing synth_stat.txt: {stat}")
        return
    text = stat.read_text(errors="replace")
    # Yosys ``stat -liberty`` prints lines like ``    1870 2.67E+03 cells``.
    # Capture the leading integer immediately preceding the literal 'cells'.
    m = re.search(r"^\s*(\d+)\s+\S+\s+cells\s*$", text, re.MULTILINE)
    n = int(m.group(1)) if m else None
    if n is None:
        fail(errors, "synth_stat.txt does not report a 'cells' summary line")
    elif n < min_cells:
        fail(errors, f"mapped cell count {n} below threshold {min_cells} -- "
                     "synthesis likely degenerate (missing RTL files / wrong top)")

    # Chip area should be reported by yosys ``stat -liberty``.
    if "Chip area for module" not in text:
        fail(errors, "synth_stat.txt: missing 'Chip area for module' line -- "
                     "liberty file may not have been loaded for stat")


def check_synth_check(result_dir: Path, errors: list[str]) -> None:
    check = result_dir / "synth_check.txt"
    if not check.is_file():
        # Optional file for some flows; warn but don't fail.
        return
    text = check.read_text(errors="replace")
    bad_patterns = [
        # Memory left after techmap means we silently produced something the
        # target library cannot represent.
        r"found unmapped memor",
        r"contains \d+ unprocessed memor",
        # Combinational loops break STA fidelity entirely.
        r"found \d+ logic loops",
    ]
    for pat in bad_patterns:
        m = re.search(pat, text, re.IGNORECASE)
        if m:
            fail(errors, f"synth_check.txt: '{m.group(0)}'")


def check_sta_log(result_dir: Path, design: str, clk_port: str,
                  errors: list[str]) -> None:
    log = result_dir / "sta.log"
    if not log.is_file() or log.stat().st_size == 0:
        fail(errors, f"missing or empty sta.log: {log}")
        return
    text = log.read_text(errors="replace")

    if f"DESIGN: {design}" not in text:
        fail(errors, f"sta.log does not show 'DESIGN: {design}'")

    # Real STA report includes a critical path, slack, and an fmax summary.
    required_markers = {
        "Path Type: max": "no critical path reported",
        "slack (":        "no slack line -- STA never evaluated a path",
        "period_min":     "no period_min line -- fmax not derived",
        "fmax = ":         "no fmax = <value> summary",
    }
    for marker, why in required_markers.items():
        if marker not in text:
            fail(errors, f"sta.log: {why} (missing '{marker}')")

    # Validate fmax is a positive finite number rather than a placeholder.
    fmax_vals = [float(v) for v in re.findall(r"fmax\s*=\s*([0-9]+\.?[0-9]*)", text)]
    if fmax_vals and max(fmax_vals) <= 0.0:
        fail(errors, f"sta.log: fmax is non-positive ({fmax_vals}) -- "
                     "clock not constrained?")

    # Sanity: clock should be the one we set up (core_clock in opensta.tcl).
    if not re.search(r"clocked by\s+\S*core_clock", text):
        fail(errors, "sta.log: no flop reported as clocked by 'core_clock' -- "
                     f"check that CLK_PORT_NAME='{clk_port}' actually exists "
                     "on the design top")

    # Power report sanity -- a fully-empty design would show zero total power.
    # Match the final 'Total ... 100.0%' summary row from report_power.
    pwr = re.search(r"^Total\s+\S+\s+\S+\s+\S+\s+(\S+)\s+100\.0%\s*$",
                    text, re.MULTILINE)
    if pwr:
        try:
            if float(pwr.group(1)) <= 0.0:
                fail(errors, "sta.log: total power is zero -- netlist appears empty")
        except ValueError:
            pass


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("result_dir", type=Path,
                    help="result/<platform>-<design>-<freq>MHz directory")
    ap.add_argument("--design", required=True, help="top-level design name")
    ap.add_argument("--clk-port", default="clk",
                    help="clock port name passed to STA (informational)")
    ap.add_argument("--min-cells", type=int, default=200,
                    help="minimum mapped-cell count expected (default: 200)")
    args = ap.parse_args()

    if not args.result_dir.is_dir():
        print(f"FAIL: result directory does not exist: {args.result_dir}",
              file=sys.stderr)
        return 2

    errors: list[str] = []
    check_yosys_log(args.result_dir, args.design, errors)
    check_synth_stat(args.result_dir, args.min_cells, errors)
    check_synth_check(args.result_dir, errors)
    check_sta_log(args.result_dir, args.design, args.clk_port, errors)

    if errors:
        print(f"FAIL: {args.design} @ {args.result_dir}", file=sys.stderr)
        for e in errors:
            print(e, file=sys.stderr)
        return 1

    print(f"PASS: {args.design} @ {args.result_dir} -- STA report is well-formed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
