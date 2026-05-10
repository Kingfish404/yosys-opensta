#!/usr/bin/env python3
"""OpenROAD block-level signoff precheck.

This is a machine-readable gate for the local block flow. It is not a
replacement for foundry/OpenLane/TinyTapeout signoff, but it prevents obvious
bad artifacts from being mistaken for tapeout-ready results.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


def bool_arg(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes", "y", "on"}


def read_text(path: Path) -> str:
    try:
        return path.read_text(errors="replace")
    except FileNotFoundError:
        return ""


def count(pattern: str, text: str) -> int:
    return len(re.findall(pattern, text, flags=re.MULTILINE))


def parse_slacks(text: str) -> list[dict[str, Any]]:
    slacks: list[dict[str, Any]] = []
    for match in re.finditer(r"([-+]?\d+(?:\.\d+)?)\s+slack\s+\(([^)]+)\)", text):
        slacks.append({"value": float(match.group(1)), "status": match.group(2)})
    return slacks


def add_check(report: dict[str, Any], name: str, passed: bool, **details: Any) -> None:
    report["checks"][name] = {"pass": bool(passed), **details}
    if not passed:
        report["pass"] = False
        message = details.get("message")
        report["failures"].append(message or name)


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate local OpenROAD flow reports")
    parser.add_argument("--result-dir", required=True, type=Path)
    parser.add_argument("--pnr-dir", required=True, type=Path)
    parser.add_argument("--design", required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--require-spef", default="0")
    parser.add_argument("--forbid-cell-regex", default="")
    parser.add_argument("--json-out", type=Path)
    args = parser.parse_args()

    result_dir = args.result_dir
    pnr_dir = args.pnr_dir
    design = args.design
    require_spef = bool_arg(args.require_spef)
    forbid_cell_regex = args.forbid_cell_regex.strip()

    report: dict[str, Any] = {
        "pass": True,
        "design": design,
        "platform": args.platform,
        "result_dir": str(result_dir),
        "pnr_dir": str(pnr_dir),
        "checks": {},
        "failures": [],
    }

    required_files = [
        result_dir / f"{design}.netlist.syn.v",
        result_dir / "synth_check.txt",
        pnr_dir / f"{design}_final.def",
        pnr_dir / f"{design}_final.odb",
        pnr_dir / f"{design}_final.v",
        pnr_dir / f"{design}_route_drc.rpt",
        pnr_dir / "timing_max_final.rpt",
        pnr_dir / "timing_min_final.rpt",
        pnr_dir / "timing_violators.rpt",
        pnr_dir / "antenna_final.rpt",
        pnr_dir / "pnr.log",
    ]
    missing = [str(path) for path in required_files if not path.exists()]
    add_check(
        report,
        "required_files",
        not missing,
        missing=missing,
        message="missing required OpenROAD result files",
    )

    synth_check = read_text(result_dir / "synth_check.txt")
    synth_warnings = count(r"^Warning:", synth_check)
    synth_problems = 0
    problem_match = re.search(r"Found and reported\s+(\d+)\s+problems", synth_check)
    if problem_match:
        synth_problems = int(problem_match.group(1))
    add_check(
        report,
        "synthesis_check_clean",
        synth_warnings == 0 and synth_problems == 0,
        warnings=synth_warnings,
        problems=synth_problems,
        message="Yosys check reported warnings/problems",
    )

    route_drc_text = read_text(pnr_dir / f"{design}_route_drc.rpt")
    route_drc_clean = route_drc_text.strip() == ""
    add_check(
        report,
        "route_drc_clean",
        route_drc_clean,
        bytes=len(route_drc_text.encode()),
        message="detailed route DRC report is not clean",
    )

    antenna_text = read_text(pnr_dir / "antenna_final.rpt")
    antenna_violations = count(r"\(VIOLATED\)", antenna_text)
    add_check(
        report,
        "antenna_clean",
        antenna_violations == 0,
        violations=antenna_violations,
        message="antenna report contains violations",
    )

    pnr_log = read_text(pnr_dir / "pnr.log")
    pnr_errors = count(r"\[(?:ERROR|FATAL)\]|^Error:", pnr_log)
    rcx_fallback = "RCX rules not found" in pnr_log or "using estimated parasitics" in pnr_log
    add_check(
        report,
        "pnr_log_no_errors",
        pnr_errors == 0,
        errors=pnr_errors,
        message="OpenROAD PnR log contains errors",
    )

    spef_path = pnr_dir / f"{design}_final.spef"
    add_check(
        report,
        "spef_available",
        (not require_spef) or spef_path.exists(),
        required=require_spef,
        exists=spef_path.exists(),
        rcx_fallback=rcx_fallback,
        message="required extracted SPEF is missing",
    )
    add_check(
        report,
        "rcx_not_fallback",
        (not require_spef) or (not rcx_fallback),
        required=require_spef,
        rcx_fallback=rcx_fallback,
        message="OpenROAD used estimated parasitics instead of OpenRCX extraction",
    )

    timing_failures: list[str] = []
    timing_summary: dict[str, Any] = {}

    for timing_name in ["timing_max_final.rpt", "timing_min_final.rpt"]:
        timing_path = pnr_dir / timing_name
        timing_text = read_text(timing_path)
        slacks = parse_slacks(timing_text)
        bad_slacks = [item for item in slacks if item["value"] < -1e-9 or item["status"] != "MET"]
        if not slacks and "No paths found" not in timing_text:
            timing_failures.append(f"{timing_name}: no slack lines found")
        if bad_slacks:
            timing_failures.append(f"{timing_name}: {len(bad_slacks)} violating slack entries")
        timing_summary[timing_name] = {
            "paths": len(slacks),
            "worst_slack": min((item["value"] for item in slacks), default=None),
            "violations": len(bad_slacks),
        }

    violators_text = read_text(pnr_dir / "timing_violators.rpt")
    if "VIOLATED" in violators_text or re.search(r"-\d+(?:\.\d+)?\s+slack", violators_text):
        timing_failures.append("timing_violators.rpt reports violating paths")
    add_check(
        report,
        "timing_clean",
        not timing_failures,
        summary=timing_summary,
        failures=timing_failures,
        message="timing reports contain violations or malformed data",
    )

    forbidden_matches: list[str] = []
    if forbid_cell_regex:
        cell_re = re.compile(forbid_cell_regex)
        for netlist_path in [result_dir / f"{design}.netlist.syn.v", pnr_dir / f"{design}_final.v"]:
            for line_no, line in enumerate(read_text(netlist_path).splitlines(), start=1):
                if cell_re.search(line):
                    forbidden_matches.append(f"{netlist_path}:{line_no}:{line.strip()}")
                    if len(forbidden_matches) >= 50:
                        break
            if len(forbidden_matches) >= 50:
                break
    add_check(
        report,
        "forbidden_cells_absent",
        not forbidden_matches,
        regex=forbid_cell_regex,
        matches=forbidden_matches[:50],
        message="final netlist contains forbidden cells",
    )

    out_path = args.json_out or (pnr_dir / "signoff_openroad.json")
    out_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")

    status = "PASS" if report["pass"] else "FAIL"
    print(f"OpenROAD signoff precheck: {status}")
    print(f"Report: {out_path}")
    for name, check in report["checks"].items():
        check_status = "PASS" if check["pass"] else "FAIL"
        print(f"  {check_status} {name}")
    if not report["pass"]:
        print("Failures:")
        for failure in report["failures"]:
            print(f"  - {failure}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
