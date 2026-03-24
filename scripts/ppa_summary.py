#!/usr/bin/env python3
"""
PPA Summary Report for yosys-opensta Flow

Parses synthesis (Yosys) and timing analysis (OpenSTA) outputs to generate
a consolidated PPA (Power, Performance, Area) report.

Supports multiple platforms:
  - nangate45:  NanGate FreePDK45 (45nm)
  - asap7:      ASAP7 7nm FinFET PDK

Usage:
  python3 ppa_summary.py result/nangate45-op-50MHz
  python3 ppa_summary.py result/asap7-op-50MHz --platform asap7
  python3 ppa_summary.py result/nangate45-op-50MHz --json
"""

import re
import os
import sys
import json
import argparse
from collections import defaultdict

# ── Platform Configurations ─────────────────────────────────────────────────
PLATFORMS = {
    "nangate45": {
        "name": "NanGate FreePDK45",
        "node": "45nm",
        "supply_voltage_v": 1.1,
        "nand2_area_um2": 0.798,
        "time_unit": "ns",
        "citation": "NanGate FreePDK45 Open Cell Library, Si2/Nangate, 2008.",
    },
    "asap7": {
        "name": "ASAP7 7nm FinFET PDK",
        "node": "7nm",
        "supply_voltage_v": 0.7,
        "nand2_area_um2": 0.08748,
        "time_unit": "ps",
        "citation": (
            "L. T. Clark et al., 'ASAP7: A 7-nm FinFET Predictive Process "
            "Design Kit,' Microelectronics J., vol. 53, pp. 105-115, 2016."
        ),
    },
}


# ── Parsers ─────────────────────────────────────────────────────────────────

def parse_input_json(filepath):
    """Parse Yosys stat JSON for structured area/cell data."""
    with open(filepath, "r") as f:
        data = json.load(f)

    # Yosys JSON has modules and a top-level "design" summary
    design = data.get("design", {})
    if not design:
        # Fallback: pick first module
        modules = data.get("modules", {})
        if modules:
            design = next(iter(modules.values()))

    return {
        "num_cells": design.get("num_cells", 0),
        "num_wires": design.get("num_wires", 0),
        "num_wire_bits": design.get("num_wire_bits", 0),
        "num_ports": design.get("num_ports", 0),
        "num_port_bits": design.get("num_port_bits", 0),
        "num_memories": design.get("num_memories", 0),
        "num_memory_bits": design.get("num_memory_bits", 0),
        "area": design.get("area", 0.0),
        "sequential_area": design.get("sequential_area", 0.0),
        "cells_by_type": design.get("num_cells_by_type", {}),
    }


def parse_sta_log(filepath):
    """Parse OpenSTA log for timing and power data."""
    with open(filepath, "r") as f:
        content = f.read()

    result = {
        "slack": None,
        "slack_met": None,
        "critical_path_delay": None,
        "fmax_mhz": None,
        "period_min_ns": None,
        "startpoint": None,
        "endpoint": None,
        "power": {},
        "clock_name": None,
        "clock_period_ns": None,
    }

    # Parse timing path
    m = re.search(r"Startpoint:\s+(\S+)", content)
    if m:
        result["startpoint"] = m.group(1)
    m = re.search(r"Endpoint:\s+(\S+)", content)
    if m:
        result["endpoint"] = m.group(1)

    # Parse slack
    m = re.search(r"([\d.-]+)\s+slack\s+\((MET|VIOLATED)\)", content)
    if m:
        result["slack"] = float(m.group(1))
        result["slack_met"] = m.group(2) == "MET"

    # Parse data arrival time
    m = re.search(r"([\d.]+)\s+data arrival time", content)
    if m:
        result["critical_path_delay"] = float(m.group(1))

    # Parse clock period
    m = re.search(r"clock\s+(\S+)\s+\(rise edge\)\s*\n\s*([\d.]+)", content)
    if m:
        result["clock_name"] = m.group(1)
        result["clock_period_ns"] = float(m.group(2))

    # Parse fmax line: "core_clock period_min = X.XX fmax = YYYY.YY"
    m = re.search(r"period_min\s*=\s*([\d.]+)\s+fmax\s*=\s*([\d.]+)", content)
    if m:
        result["period_min_ns"] = float(m.group(1))
        result["fmax_mhz"] = float(m.group(2))

    # Parse power table
    power_groups = {}
    for m in re.finditer(
        r"^(Sequential|Combinational|Clock|Macro|Pad)\s+"
        r"([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.]+)%",
        content, re.MULTILINE
    ):
        power_groups[m.group(1)] = {
            "internal_w": float(m.group(2)),
            "switching_w": float(m.group(3)),
            "leakage_w": float(m.group(4)),
            "total_w": float(m.group(5)),
            "pct": float(m.group(6)),
        }

    # Parse total power
    m = re.search(
        r"^Total\s+([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.e+-]+)\s+([\d.e+-]+)\s+100\.0%",
        content, re.MULTILINE
    )
    if m:
        power_groups["Total"] = {
            "internal_w": float(m.group(1)),
            "switching_w": float(m.group(2)),
            "leakage_w": float(m.group(3)),
            "total_w": float(m.group(4)),
        }

    result["power"] = power_groups
    return result


def categorize_cells(cells_by_type):
    """Categorize cells into functional groups for summary."""
    categories = defaultdict(lambda: {"count": 0, "types": []})

    for cell_type, count in sorted(cells_by_type.items()):
        name_upper = cell_type.upper()
        if "DFF" in name_upper or "LATCH" in name_upper or "SEQ" in name_upper:
            cat = "Sequential (DFF/Latch)"
        elif "BUF" in name_upper or "CLKBUF" in name_upper or name_upper.startswith("HB"):
            cat = "Buffer"
        elif "INV" in name_upper:
            cat = "Inverter"
        elif "AND" in name_upper and "NAND" not in name_upper:
            cat = "AND"
        elif "OR" in name_upper and "NOR" not in name_upper and "XOR" not in name_upper and "XNOR" not in name_upper:
            cat = "OR"
        elif "NAND" in name_upper:
            cat = "NAND"
        elif "NOR" in name_upper:
            cat = "NOR"
        elif "XOR" in name_upper or "XNOR" in name_upper:
            cat = "XOR/XNOR"
        elif "AOI" in name_upper or "AO" in name_upper or "A2O" in name_upper:
            cat = "AND-OR-INV"
        elif "OAI" in name_upper or "OA" in name_upper or "O2A" in name_upper:
            cat = "OR-AND-INV"
        elif "MUX" in name_upper:
            cat = "Multiplexer"
        elif "MAJ" in name_upper:
            cat = "Majority"
        else:
            cat = "Other"

        categories[cat]["count"] += count
        categories[cat]["types"].append((cell_type, count))

    return dict(categories)


def format_power(watts):
    """Format power value with auto-scaling."""
    if watts == 0:
        return "0 W"
    abs_w = abs(watts)
    if abs_w >= 1:
        return f"{watts:.3f} W"
    elif abs_w >= 1e-3:
        return f"{watts*1e3:.3f} mW"
    elif abs_w >= 1e-6:
        return f"{watts*1e6:.3f} uW"
    elif abs_w >= 1e-9:
        return f"{watts*1e9:.3f} nW"
    else:
        return f"{watts:.3e} W"


# ── Report Generator ───────────────────────────────────────────────────────

def generate_report(result_dir, platform_name, design_name):
    """Generate consolidated PPA report from result directory."""
    stat_json = os.path.join(result_dir, "input.json")
    sta_log = os.path.join(result_dir, "sta.log")

    # Validate files exist
    missing = []
    if not os.path.exists(stat_json):
        missing.append(stat_json)
    if not os.path.exists(sta_log):
        missing.append(sta_log)
    if missing:
        print(f"Error: Missing files: {', '.join(missing)}")
        print("Run 'make syn' and 'make sta' first.")
        sys.exit(1)

    plat = PLATFORMS.get(platform_name)
    if not plat:
        print(f"Error: Unknown platform '{platform_name}'.")
        print(f"Available: {', '.join(PLATFORMS.keys())}")
        sys.exit(1)

    synth = parse_input_json(stat_json)
    timing = parse_sta_log(sta_log)
    categories = categorize_cells(synth["cells_by_type"])

    # Derived values
    area = synth["area"]
    seq_area = synth["sequential_area"]
    comb_area = area - seq_area
    nand2_area = plat["nand2_area_um2"]
    ge = area / nand2_area if nand2_area > 0 else 0

    fmax_mhz = timing.get("fmax_mhz", 0)
    fmax_ghz = fmax_mhz / 1000.0

    total_power = timing["power"].get("Total", {})
    total_power_w = total_power.get("total_w", 0)

    # Build report
    r = []
    r.append("=" * 72)
    r.append(f"  PPA Summary — {design_name}")
    r.append("=" * 72)

    # ── Platform
    r.append(f"\n--- PLATFORM ---")
    r.append(f"  Name:           {plat['name']} ({platform_name})")
    r.append(f"  Tech node:      {plat['node']}")
    r.append(f"  Supply voltage: {plat['supply_voltage_v']} V")
    r.append(f"  Citation:       {plat['citation']}")

    # ── Area
    r.append(f"\n--- AREA ---")
    r.append(f"  Chip area:       {area:,.2f} um2 (at {plat['node']})")
    r.append(f"  Gate equivalent: {ge:,.0f} GE (NAND2 = {nand2_area} um2)")
    r.append(f"  Sequential:      {seq_area:,.2f} um2 ({seq_area/area*100:.1f}%)" if area else "")
    r.append(f"  Combinational:   {comb_area:,.2f} um2 ({comb_area/area*100:.1f}%)" if area else "")
    r.append(f"  Total cells:     {synth['num_cells']}")
    r.append(f"  Wires:           {synth['num_wires']} ({synth['num_wire_bits']} bits)")
    r.append(f"  Ports:           {synth['num_ports']} ({synth['num_port_bits']} bits)")

    # ── Cell category breakdown
    r.append(f"\n  Cell Breakdown by Category:")
    r.append(f"    {'Category':<22} {'Count':>8} {'%':>7}")
    r.append(f"    {'-'*22} {'-'*8} {'-'*7}")
    total_cells = synth["num_cells"]
    for cat_name, cat_data in sorted(categories.items(), key=lambda x: -x[1]["count"]):
        pct = cat_data["count"] / total_cells * 100 if total_cells else 0
        r.append(f"    {cat_name:<22} {cat_data['count']:>8} {pct:>6.1f}%")

    # ── Top cells (by count)
    top_cells = sorted(synth["cells_by_type"].items(), key=lambda x: -x[1])[:15]
    r.append(f"\n  Top Cells (by count):")
    r.append(f"    {'Cell Type':<30} {'Count':>8} {'%':>7}")
    r.append(f"    {'-'*30} {'-'*8} {'-'*7}")
    for cell_type, count in top_cells:
        pct = count / total_cells * 100 if total_cells else 0
        r.append(f"    {cell_type:<30} {count:>8} {pct:>6.1f}%")

    # ── Timing
    r.append(f"\n--- TIMING ---")
    if timing["clock_name"]:
        r.append(f"  Clock:           {timing['clock_name']}"
                 f" (period = {timing['clock_period_ns']:.2f} ns"
                 f" / {1000.0/timing['clock_period_ns']:.1f} MHz)" if timing["clock_period_ns"] else "")
    if timing["startpoint"]:
        r.append(f"  Startpoint:      {timing['startpoint']}")
        r.append(f"  Endpoint:        {timing['endpoint']}")
    if timing["critical_path_delay"] is not None:
        delay = timing["critical_path_delay"]
        unit = plat["time_unit"]
        if unit == "ps":
            r.append(f"  Critical path:   {delay:.2f} ps ({delay/1000:.3f} ns)")
        else:
            r.append(f"  Critical path:   {delay:.3f} ns ({delay*1000:.0f} ps)")
    if timing["slack"] is not None:
        status = "MET" if timing["slack_met"] else "VIOLATED"
        r.append(f"  Slack:           {timing['slack']:.2f} {plat['time_unit']} ({status})")
    if fmax_mhz:
        if timing["period_min_ns"] is not None:
            r.append(f"  Min period:      {timing['period_min_ns']:.2f} {plat['time_unit']}")
        r.append(f"  *** Max Freq:    {fmax_mhz:.2f} MHz ({fmax_ghz:.3f} GHz) ***")

    # ── Power
    if timing["power"]:
        r.append(f"\n--- POWER ---")
        r.append(f"    {'Group':<16} {'Internal':>12} {'Switching':>12} {'Leakage':>12} {'Total':>12} {'%':>7}")
        r.append(f"    {'-'*16} {'-'*12} {'-'*12} {'-'*12} {'-'*12} {'-'*7}")
        for group_name in ["Sequential", "Combinational", "Clock", "Macro", "Pad"]:
            g = timing["power"].get(group_name)
            if g and g["total_w"] > 0:
                r.append(f"    {group_name:<16} {format_power(g['internal_w']):>12}"
                         f" {format_power(g['switching_w']):>12}"
                         f" {format_power(g['leakage_w']):>12}"
                         f" {format_power(g['total_w']):>12}"
                         f" {g['pct']:>6.1f}%")
        if total_power:
            r.append(f"    {'-'*16} {'-'*12} {'-'*12} {'-'*12} {'-'*12} {'-'*7}")
            r.append(f"    {'Total':<16} {format_power(total_power['internal_w']):>12}"
                     f" {format_power(total_power['switching_w']):>12}"
                     f" {format_power(total_power['leakage_w']):>12}"
                     f" {format_power(total_power['total_w']):>12} {'100.0%':>7}")

    # ── Summary box
    r.append(f"\n--- SUMMARY ---")
    r.append(f"  Design:     {design_name}")
    r.append(f"  Platform:   {plat['name']} ({plat['node']})")
    r.append(f"  Area:       {area:,.2f} um2 ({ge:,.0f} GE)")
    r.append(f"  Cells:      {synth['num_cells']}")
    if fmax_mhz:
        r.append(f"  Fmax:       {fmax_mhz:.2f} MHz ({fmax_ghz:.3f} GHz)")
    if timing["slack"] is not None:
        r.append(f"  Slack:      {timing['slack']:.2f} {plat['time_unit']} ({'MET' if timing['slack_met'] else 'VIOLATED'})")
    if total_power_w:
        r.append(f"  Power:      {format_power(total_power_w)}")
    r.append("=" * 72)

    return "\n".join(r)


def generate_json(result_dir, platform_name, design_name):
    """Generate structured JSON summary."""
    stat_json = os.path.join(result_dir, "input.json")
    sta_log = os.path.join(result_dir, "sta.log")

    plat = PLATFORMS.get(platform_name, {})
    synth = parse_input_json(stat_json)
    timing = parse_sta_log(sta_log)

    area = synth["area"]
    nand2_area = plat.get("nand2_area_um2", 1.0)
    ge = area / nand2_area if nand2_area > 0 else 0

    total_power = timing["power"].get("Total", {})

    return {
        "design": design_name,
        "platform": {
            "name": plat.get("name", platform_name),
            "node": plat.get("node", ""),
            "supply_voltage_v": plat.get("supply_voltage_v", 0),
        },
        "area": {
            "total_um2": round(area, 3),
            "sequential_um2": round(synth["sequential_area"], 3),
            "combinational_um2": round(area - synth["sequential_area"], 3),
            "gate_equivalents": round(ge, 0),
            "num_cells": synth["num_cells"],
            "cells_by_type": synth["cells_by_type"],
        },
        "timing": {
            "clock_name": timing.get("clock_name"),
            "clock_period_ns": timing.get("clock_period_ns"),
            "critical_path_delay": timing.get("critical_path_delay"),
            "time_unit": plat.get("time_unit", "ns"),
            "slack": timing.get("slack"),
            "slack_met": timing.get("slack_met"),
            "fmax_mhz": timing.get("fmax_mhz"),
            "period_min": timing.get("period_min_ns"),
            "startpoint": timing.get("startpoint"),
            "endpoint": timing.get("endpoint"),
        },
        "power": {
            "total_w": total_power.get("total_w", 0),
            "internal_w": total_power.get("internal_w", 0),
            "switching_w": total_power.get("switching_w", 0),
            "leakage_w": total_power.get("leakage_w", 0),
            "groups": {
                k: v for k, v in timing["power"].items() if k != "Total"
            },
        },
    }


# ── CLI ─────────────────────────────────────────────────────────────────────

def detect_platform(result_dir):
    """Auto-detect platform from result directory name."""
    basename = os.path.basename(os.path.normpath(result_dir))
    for plat in PLATFORMS:
        if basename.startswith(plat):
            return plat
    return None


def detect_design(result_dir):
    """Auto-detect design name from result directory name."""
    basename = os.path.basename(os.path.normpath(result_dir))
    # Expected format: <platform>-<design>-<freq>MHz
    parts = basename.split("-")
    if len(parts) >= 3:
        return parts[1]
    return "unknown"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="PPA Summary Report for yosys-opensta flow")
    parser.add_argument("result_dir",
                        help="Result directory (e.g., result/nangate45-op-50MHz)")
    parser.add_argument("--platform", default=None,
                        help="Platform name (auto-detected from dir name)")
    parser.add_argument("--design", default=None,
                        help="Design name (auto-detected from dir name)")
    parser.add_argument("--json", action="store_true",
                        help="Output structured JSON instead of text report")
    parser.add_argument("--save", action="store_true",
                        help="Save report to result directory")
    args = parser.parse_args()

    platform_name = args.platform or detect_platform(args.result_dir)
    design_name = args.design or detect_design(args.result_dir)

    if not platform_name:
        print("Error: Cannot auto-detect platform. Use --platform <name>.")
        print(f"Available: {', '.join(PLATFORMS.keys())}")
        sys.exit(1)

    if args.json:
        data = generate_json(args.result_dir, platform_name, design_name)
        output = json.dumps(data, indent=2)
    else:
        output = generate_report(args.result_dir, platform_name, design_name)

    print(output)

    if args.save:
        ext = "json" if args.json else "txt"
        out_path = os.path.join(args.result_dir, f"ppa_summary.{ext}")
        with open(out_path, "w") as f:
            f.write(output)
        print(f"\nSaved to {out_path}")
