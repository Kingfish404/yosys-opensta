#!/usr/bin/env python3
"""Per-module area visualization (no PnR required).

Consumes only post-synthesis artifacts:
  - <design>_hier.json  (pre-synth hierarchy / net naming)
  - <design>_syn.json   (post-synth flattened netlist)
  - merged.lib          (Liberty file with cell areas)

Produces:
  - <out>/<design>_area_treemap.svg  (squarified treemap, physical aspect)
  - <out>/<design>_area_bar.svg      (horizontal bar chart, matplotlib)
  - <out>/<design>_area.json         (per-module area table)
  - <out>/<design>_area.csv          (same table, CSV)

Reuses area-extraction helpers from gen-arch.py (imported via importlib since
the source file name contains a hyphen).

Usage:
  python3 scripts/viz_module_area.py \\
      --hier-json result/<plat>-<d>-<f>MHz/<d>_hier.json \\
      --syn-json  result/<plat>-<d>-<f>MHz/<d>_syn.json \\
      --liberty   third_party/lib/<plat>/lib/merged.lib \\
      --design    <d> \\
      -o          result/<plat>-<d>-<f>MHz
"""

import argparse
import csv
import importlib.util
import json
import os
import sys
from pathlib import Path


def _load_gen_arch():
    """Import gen-arch.py by path (hyphenated filename)."""
    here = Path(__file__).resolve().parent
    path = here / "gen-arch.py"
    spec = importlib.util.spec_from_file_location("gen_arch", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build_area_map(hier_json_path, syn_json_path, liberty_path, design=None,
                   prefix_depth=1):
    ga = _load_gen_arch()

    with open(hier_json_path, "r") as f:
        hier = json.load(f)
    with open(syn_json_path, "r") as f:
        syn = json.load(f)

    hier_modules = hier.get("modules", {})
    syn_modules = syn.get("modules", {})
    if not hier_modules or not syn_modules:
        raise SystemExit("Error: empty modules in hier or syn JSON")

    top_name, top_mod = ga.find_top_module(hier_modules, design)
    _, syn_top_mod = ga.find_top_module(syn_modules, design)

    cell_areas = ga._parse_liberty_areas(liberty_path)
    modules_for_area, _, _ = ga.extract_hierarchy_from_nets(top_mod)
    area_map = ga._compute_module_areas(
        syn_top_mod, modules_for_area, cell_areas, prefix_depth=prefix_depth
    )
    return top_name, area_map, ga


def write_treemap(ga, top_name, area_map, out_path):
    svg = ga.generate_area_treemap_svg(top_name, area_map)
    with open(out_path, "w") as f:
        f.write(svg)


def write_bar_chart(top_name, area_map, out_path, fmt="svg"):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    items = sorted(
        [(k, v) for k, v in area_map.items() if k != "__unassigned__" and v > 0],
        key=lambda kv: kv[1],
    )
    unassigned = area_map.get("__unassigned__", 0.0)

    if not items and unassigned <= 0:
        return False

    names = [k for k, _ in items]
    values = [v for _, v in items]
    total = sum(values) + unassigned

    fig_h = max(2.5, 0.35 * len(items) + 1.5)
    fig, ax = plt.subplots(figsize=(9, fig_h))

    colors = plt.get_cmap("tab20").colors
    bar_colors = [colors[i % len(colors)] for i in range(len(names))]
    ax.barh(names, values, color=bar_colors, edgecolor="#333", linewidth=0.6)

    for i, v in enumerate(values):
        pct = v / total * 100 if total > 0 else 0
        label = (
            f"{v/1000:.1f}K um^2 ({pct:.1f}%)"
            if v >= 1000
            else f"{v:.0f} um^2 ({pct:.1f}%)"
        )
        ax.text(v, i, " " + label, va="center", fontsize=9)

    ax.set_xlabel("Area (um^2)")
    title = f"{top_name} -- Module Area Breakdown (total: {total/1000:.1f}K um^2"
    if unassigned > 0:
        title += f", unassigned: {unassigned/1000:.1f}K um^2"
    title += ")"
    ax.set_title(title)
    ax.grid(axis="x", linestyle="--", alpha=0.4)
    ax.margins(x=0.18)
    fig.tight_layout()
    fig.savefig(out_path, format=fmt)
    plt.close(fig)
    return True


def write_table(top_name, area_map, json_path, csv_path):
    items = sorted(
        [(k, v) for k, v in area_map.items()],
        key=lambda kv: -kv[1],
    )
    total = sum(v for k, v in items if k != "__unassigned__")
    rows = []
    for name, area in items:
        pct = (area / total * 100) if (total > 0 and name != "__unassigned__") else 0.0
        rows.append(
            {
                "module": name,
                "area_um2": round(area, 3),
                "pct_of_assigned": round(pct, 3),
            }
        )
    with open(json_path, "w") as f:
        json.dump(
            {"top": top_name, "total_assigned_um2": total, "modules": rows}, f, indent=2
        )
    with open(csv_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["module", "area_um2", "pct_of_assigned"])
        for r in rows:
            w.writerow([r["module"], r["area_um2"], r["pct_of_assigned"]])


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--hier-json", required=True, help="<design>_hier.json from yosys")
    p.add_argument(
        "--syn-json", required=True, help="<design>_syn.json from yosys (post-synth)"
    )
    p.add_argument("--liberty", required=True, help="merged.lib with cell areas")
    p.add_argument("--design", default=None, help="Top module name (auto if omitted)")
    p.add_argument("-o", "--out-dir", required=True, help="Output directory")
    p.add_argument(
        "--prefix", default=None, help="Output file prefix (default: <design>)"
    )
    p.add_argument(
        "--depth",
        type=int,
        default=1,
        help=(
            "Hierarchy depth for area buckets: 1 = top-level modules only "
            "(default), 2 = also split one submodule level (e.g. core.idu, "
            "core.exu), 3 = two submodule levels, etc."
        ),
    )
    args = p.parse_args()
    if args.depth < 1:
        print(f"Error: --depth must be >= 1 (got {args.depth})", file=sys.stderr)
        return 1

    for path in (args.hier_json, args.syn_json, args.liberty):
        if not os.path.isfile(path):
            print(f"Error: not a file: {path}", file=sys.stderr)
            return 1

    os.makedirs(args.out_dir, exist_ok=True)

    top_name, area_map, ga = build_area_map(
        args.hier_json, args.syn_json, args.liberty, args.design,
        prefix_depth=args.depth,
    )
    prefix = args.prefix or top_name
    if args.depth > 1:
        prefix = f"{prefix}_d{args.depth}"

    total = sum(v for k, v in area_map.items() if k != "__unassigned__")
    unassigned = area_map.get("__unassigned__", 0.0)
    print(f"Top module:    {top_name}")
    print(f"Prefix depth:  {args.depth}")
    print(f"Modules found: {sum(1 for k in area_map if k != '__unassigned__')}")
    print(f"Total area:    {total:.0f} um^2 (assigned)")
    if unassigned > 0:
        print(f"Unassigned:    {unassigned:.0f} um^2")
    for mod, a in sorted(area_map.items(), key=lambda x: -x[1]):
        if mod == "__unassigned__":
            continue
        pct = (a / total * 100) if total > 0 else 0
        print(f"  {mod:<30s} {a:>12.0f} um^2  ({pct:5.1f}%)")

    tree_path = os.path.join(args.out_dir, f"{prefix}_area_treemap.svg")
    bar_path = os.path.join(args.out_dir, f"{prefix}_area_bar.svg")
    json_path = os.path.join(args.out_dir, f"{prefix}_area.json")
    csv_path = os.path.join(args.out_dir, f"{prefix}_area.csv")

    write_treemap(ga, top_name, area_map, tree_path)
    print(f"Treemap SVG:   {tree_path}")

    if write_bar_chart(top_name, area_map, bar_path, fmt="svg"):
        print(f"Bar chart SVG: {bar_path}")

    write_table(top_name, area_map, json_path, csv_path)
    print(f"Table JSON:    {json_path}")
    print(f"Table CSV:     {csv_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
