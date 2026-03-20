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
import re
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

# Enable label and pin production so KLayout generates TEXT for pin names
lefdef.produce_labels = True
lefdef.labels_suffix = ".LABEL"
lefdef.labels_datatype = 1
lefdef.produce_pins = True
lefdef.pins_suffix = ".PIN"
lefdef.pins_datatype = 2

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

# --- Add top-level I/O pin labels from DEF PINS section ---
# The LEF/DEF reader may not produce TEXT labels on the correct GDS layers.
# Explicitly parse the DEF to insert pin name labels on pin metal layers.

def parse_lyt_layer_map(lyt_path):
    """Parse .lyt technology file to extract LEF layer name → (gds_layer, gds_datatype) mapping."""
    name_to_gds = {}
    if not lyt_path or not os.path.exists(lyt_path):
        return name_to_gds
    with open(lyt_path, 'r') as f:
        lyt_content = f.read()
    # Find the layer map inside the <lefdef> section
    lefdef_m = re.search(r'<lefdef>(.*?)</lefdef>', lyt_content, re.DOTALL)
    if not lefdef_m:
        return name_to_gds
    lmap_m = re.search(r"<layer-map>layer_map\((.*?)\)</layer-map>", lefdef_m.group(1), re.DOTALL)
    if not lmap_m:
        return name_to_gds
    # Entries like: 'metal3 : 15/0'
    for entry in re.findall(r"'([^']+)'", lmap_m.group(1)):
        parts = entry.split(':')
        if len(parts) == 2:
            lef_name = parts[0].strip()
            gds_part = parts[1].strip()
            gds_split = gds_part.split('/')
            if len(gds_split) == 2 and gds_split[0].isdigit():
                gds_layer = int(gds_split[0])
                gds_dt = int(gds_split[1])
                name_to_gds[lef_name] = (gds_layer, gds_dt)
    return name_to_gds

def add_pin_labels_from_def(layout, def_path, design_name, lyt_path=""):
    """Parse DEF PINS and insert TEXT labels on pin metal layers in the top cell."""
    top = layout.cell(design_name)
    if top is None:
        top = layout.top_cell()
    if top is None:
        print("Warning: no top cell found, skipping pin labels")
        return 0

    # Build LEF layer name → GDS number mapping from .lyt technology file
    name_to_gds = parse_lyt_layer_map(lyt_path)
    print(f"Pin labels: parsed {len(name_to_gds)} layer mappings from .lyt")

    # Dedicated pin marker layer (GDS 200/0) — bright, won't collide with routing
    PIN_MARKER_GDS_LAYER = 200
    PIN_MARKER_GDS_DT = 0
    pin_marker_li = layout.layer(PIN_MARKER_GDS_LAYER, PIN_MARKER_GDS_DT)

    with open(def_path, 'r') as f:
        content = f.read()

    # DEF database units per micron (e.g. 2000 → 1 DEF unit = 0.5 nm)
    m = re.search(r'UNITS\s+DISTANCE\s+MICRONS\s+(\d+)', content)
    def_units_per_um = int(m.group(1)) if m else 1000

    # Scale factor: DEF units → layout database units
    scale = 1.0 / (def_units_per_um * layout.dbu)

    # Extract PINS section
    pins_match = re.search(r'\nPINS\s+\d+\s*;(.*?)\nEND PINS', content, re.DOTALL)
    if not pins_match:
        print("Warning: no PINS section found in DEF")
        return 0

    pins_text = pins_match.group(1)
    count = 0

    for pin_block in re.split(r'\n\s*-\s+', pins_text):
        pin_block = pin_block.strip()
        if not pin_block:
            continue

        pin_name = pin_block.split()[0]

        lm = re.search(
            r'LAYER\s+(\S+)\s*\(\s*(-?\d+)\s+(-?\d+)\s*\)\s*\(\s*(-?\d+)\s+(-?\d+)\s*\)',
            pin_block)
        pm = re.search(
            r'(?:PLACED|FIXED|COVER)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)',
            pin_block)
        if not lm or not pm:
            continue

        layer_name = lm.group(1)
        rx1, ry1 = int(lm.group(2)), int(lm.group(3))
        rx2, ry2 = int(lm.group(4)), int(lm.group(5))
        px, py = int(pm.group(1)), int(pm.group(2))

        cx = int((px + (rx1 + rx2) / 2.0) * scale)
        cy = int((py + (ry1 + ry2) / 2.0) * scale)

        # Resolve layer index via GDS number from .lyt mapping
        gds_info = name_to_gds.get(layer_name)
        if gds_info:
            li = layout.layer(gds_info[0], gds_info[1])
        else:
            # Fallback: try finding by name in case layers have names
            li = None
            for idx in layout.layer_indices():
                info = layout.get_info(idx)
                if info.name == layer_name:
                    li = idx
                    break
            if li is None:
                print(f"Warning: layer '{layer_name}' not found for pin '{pin_name}'")
                continue

        top.shapes(li).insert(pya.Text(pin_name, pya.Trans(pya.Point(cx, cy))))

        # Add a visible pin marker box on a dedicated layer (200/0)
        # so pins stand out from routing at full-die zoom.
        die_bbox = top.bbox()
        marker_half = max(int(die_bbox.height() * 0.015), 500)
        top.shapes(pin_marker_li).insert(pya.Box(
            cx - marker_half, cy - marker_half,
            cx + marker_half, cy + marker_half))
        # Also place the label on the marker layer for visibility
        top.shapes(pin_marker_li).insert(
            pya.Text(pin_name, pya.Trans(pya.Point(cx, cy))))

        count += 1

    return count

n_labels = add_pin_labels_from_def(layout, def_file, design, tech_file)
print(f"Pin labels added: {n_labels}")

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

# --- Export layout preview image ---
out_png = os.path.splitext(out_gds)[0] + ".png"
lyp_file = os.path.join(os.path.dirname(tech_file), "klayout.lyp") if tech_file else ""

try:
    lv = pya.LayoutView()
    lv.load_layout(out_gds, False)

    if lyp_file and os.path.exists(lyp_file):
        lv.load_layer_props(lyp_file)
    # Make .PIN / .LABEL layers (datatype 2/1) visible even if not in lyp
    lv.add_missing_layers()

    # Style the pin marker layer (200/0) with bright red so it stands out
    iter = lv.begin_layers()
    while not iter.at_end():
        lp = iter.current()
        if lp.source_layer == 200 and lp.source_datatype == 0:
            lp.fill_color = 0xff0000
            lp.frame_color = 0xff0000
            lp.visible = True
            lp.transparent = False
            lp.width = 3
            lp.name = "PIN_MARKERS"
            lv.set_layer_properties(iter, lp)
        iter.next()

    lv.max_hier()
    lv.zoom_fit()

    # Show text labels in the view
    try:
        lv.set_config("text-visible", "true")
        lv.set_config("text-default-font", "3")
    except Exception:
        pass

    img_w, img_h = 4096, 4096
    lv.save_image(out_png, img_w, img_h)
    print(f"PNG preview: {out_png} ({img_w}x{img_h})")
except Exception as e:
    print(f"Note: PNG export skipped ({e})")

print("=" * 60)
print(f"  GDS generation complete: {out_gds}")
print("=" * 60)
