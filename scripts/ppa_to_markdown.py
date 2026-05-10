#!/usr/bin/env python3
"""Render a PPA markdown summary across one or more result directories.

Reads ``ppa_summary.json`` produced by ``scripts/ppa_summary.py --json --save``
(or generates it on the fly) and prints a single Markdown table to stdout
suitable for ``$GITHUB_STEP_SUMMARY``.

Usage::

    python3 scripts/ppa_to_markdown.py result/nangate45-op-50MHz [more dirs ...] \
        --title "Synthesis + STA PPA"
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def ensure_json(result_dir: Path, platform: str, design: str) -> dict | None:
    """Return the PPA JSON for *result_dir*, generating it if missing."""
    cached = result_dir / "ppa_summary.json"
    if not cached.is_file():
        try:
            subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "scripts" / "ppa_summary.py"),
                    str(result_dir),
                    "--platform", platform,
                    "--design", design,
                    "--json", "--save",
                ],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.STDOUT,
            )
        except subprocess.CalledProcessError as exc:
            print(f"WARN: ppa_summary failed for {result_dir}: {exc}",
                  file=sys.stderr)
            return None
    if not cached.is_file():
        return None
    try:
        return json.loads(cached.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        print(f"WARN: cannot read {cached}: {exc}", file=sys.stderr)
        return None


def parse_dir_name(name: str) -> tuple[str, str, str]:
    """Best-effort split of ``<platform>-<design>-<freq>MHz``.

    The design name may contain hyphens (e.g. ``hazard3_core``), so we anchor
    on the first segment (platform) and the trailing ``-<freq>MHz`` segment.
    """
    parts = name.split("-")
    platform = parts[0]
    freq = ""
    if parts and parts[-1].endswith("MHz"):
        freq = parts[-1].removesuffix("MHz")
        design = "-".join(parts[1:-1]) or parts[-1]
    else:
        design = "-".join(parts[1:]) or name
    return platform, design, freq


def fmt_w(value: float | None) -> str:
    if not value or value <= 0:
        return "--"
    if value >= 1e-3:
        return f"{value * 1e3:.2f} mW"
    if value >= 1e-6:
        return f"{value * 1e6:.2f} uW"
    return f"{value * 1e9:.2f} nW"


def fmt_num(value, suffix: str = "", precision: int = 0) -> str:
    if value is None:
        return "--"
    try:
        v = float(value)
    except (TypeError, ValueError):
        return str(value)
    if precision == 0:
        return f"{int(round(v)):,}{suffix}"
    return f"{v:,.{precision}f}{suffix}"


def render(rows: list[tuple[Path, dict]], title: str) -> str:
    out: list[str] = []
    out.append(f"## {title}\n")
    out.append("| Design | Platform | Freq target | Cells | Area (um^2) | "
               "GE (NAND2 eq.) | f_max (MHz) | Slack | Power |")
    out.append("|---|---|---|---:|---:|---:|---:|---|---:|")
    for result_dir, j in rows:
        plat, des, freq = parse_dir_name(result_dir.name)
        platform = (j.get("platform") or {}).get("name") or plat
        timing = j.get("timing") or {}
        area = j.get("area") or {}
        power = j.get("power") or {}

        fmax = timing.get("fmax_mhz")
        slack = timing.get("slack")
        slack_met = timing.get("slack_met")
        slack_str = "--"
        if slack is not None:
            mark = "[OK]" if slack_met else "[WARN]"
            slack_str = f"{mark} {slack:+.2f} ns"

        out.append(
            "| {des} | {plat} | {freq} MHz | {cells} | {area} | {ge} | "
            "{fmax} | {slack} | {power} |".format(
                des=j.get("design") or des,
                plat=platform,
                freq=freq or "?",
                cells=fmt_num(area.get("num_cells")),
                area=fmt_num(area.get("total_um2"), precision=1),
                ge=fmt_num(area.get("gate_equivalents")),
                fmax=fmt_num(fmax, precision=1),
                slack=slack_str,
                power=fmt_w(power.get("total_w")),
            )
        )
    out.append("")
    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("result_dirs", nargs="+", type=Path,
                    help="result/<platform>-<design>-<freq>MHz directories")
    ap.add_argument("--title", default="PPA Summary",
                    help="Markdown section title")
    args = ap.parse_args()

    rows: list[tuple[Path, dict]] = []
    for d in args.result_dirs:
        if not d.is_dir():
            print(f"WARN: skipping missing dir {d}", file=sys.stderr)
            continue
        plat, des, _ = parse_dir_name(d.name)
        j = ensure_json(d, plat, des)
        if j is None:
            continue
        rows.append((d, j))

    if not rows:
        print(f"## {args.title}\n\n_(no PPA data available)_\n")
        return 0

    print(render(rows, args.title))
    return 0


if __name__ == "__main__":
    sys.exit(main())
