# KLayout batch script: merge DEF + cell GDS library → final GDS
#
# Usage:
#   klayout -z -r klayout_gds_merge.py \
#     -rd def_file=<routed>.def \
#     -rd cell_gds=<cell_library>.gds \
#     -rd tech_lef=<tech>.lef \
#     -rd cell_lef=<cell>.lef \
#     -rd tech_file=<platform>.lyt \
#     -rd out_gds=<output>.gds \
#     [-rd design=<name>]
#
# This corresponds to ORFS stage 6 (6_1_merge → 6_final.gds).

import pya
import os
import sys

# Read variables passed via -rd
def_file  = def_file   if "def_file"  in dir() else ""
cell_gds  = cell_gds   if "cell_gds"  in dir() else ""
tech_lef  = tech_lef   if "tech_lef"  in dir() else ""
cell_lef  = cell_lef   if "cell_lef"  in dir() else ""
tech_file = tech_file   if "tech_file" in dir() else ""
out_gds   = out_gds    if "out_gds"   in dir() else ""
design    = design     if "design"    in dir() else "design"

if not def_file or not cell_gds or not out_gds:
    print("ERROR: Required parameters: def_file, cell_gds, out_gds")
    sys.exit(1)

print("=" * 60)
print(f"  KLayout GDS Merge")
print(f"  DEF:      {def_file}")
print(f"  Cell GDS: {cell_gds}")
print(f"  Tech LEF: {tech_lef}")
print(f"  Cell LEF: {cell_lef}")
print(f"  Tech:     {tech_file}")
print(f"  Output:   {out_gds}")
print("=" * 60)

# Load technology if provided
tech = pya.Technology()
if tech_file and os.path.exists(tech_file):
    tech.load(tech_file)
    print(f"Loaded technology: {tech_file}")

# Create layout and read the cell GDS library
layout = pya.Layout()
layout.read(cell_gds)
print(f"Read cell GDS: {cell_gds} ({layout.cells()} cells)")

# Read DEF with LEF files so KLayout can resolve all cell references
load_options = pya.LoadLayoutOptions()
lefdef = load_options.lefdef_config
lefdef.read_lef_with_def = False

# Provide LEF files for cell geometry resolution
lef_paths = []
if tech_lef and os.path.exists(tech_lef):
    lef_paths.append(tech_lef)
    print(f"Added tech LEF: {tech_lef}")
if cell_lef and os.path.exists(cell_lef):
    lef_paths.append(cell_lef)
    print(f"Added cell LEF: {cell_lef}")

if lef_paths:
    try:
        # KLayout >= 0.28: lef_files is a list-like property
        lefdef.lef_files = lef_paths
    except Exception:
        # Fallback: read LEF files into layout first, then DEF
        for lp in lef_paths:
            layout.read(lp, load_options)
            print(f"Read LEF (fallback): {lp}")

layout.read(def_file, load_options)
print(f"Read DEF: {def_file}")

# Write merged GDS
save_options = pya.SaveLayoutOptions()
layout.write(out_gds, save_options)
print(f"GDS written: {out_gds}")

# Report file size
gds_size = os.path.getsize(out_gds)
if gds_size > 1024 * 1024:
    print(f"GDS size: {gds_size / (1024*1024):.1f} MB")
else:
    print(f"GDS size: {gds_size / 1024:.1f} KB")

print("=" * 60)
print(f"  GDS generation complete: {out_gds}")
print("=" * 60)
