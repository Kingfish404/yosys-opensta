# KLayout batch script: render DEF layout to PNG images
# Usage: klayout -z -r viz_layout_klayout.py -rd def_file=<path>.def -rd tech_lef=<path>.lef -rd cell_lef=<path>.lef -rd tech_file=<path>.lyt -rd lyp_file=<path>.lyp -rd out_dir=<dir>

import pya
import os
import sys

# Read parameters from -rd command line args
def_file  = os.environ.get("KLAYOUT_DEF", def_file) if "def_file" not in dir() else def_file
tech_lef  = tech_lef  if "tech_lef"  in dir() else ""
cell_lef  = cell_lef  if "cell_lef"  in dir() else ""
tech_file = os.environ.get("KLAYOUT_TECH", tech_file) if "tech_file" not in dir() else tech_file
lyp_file  = os.environ.get("KLAYOUT_LYP", lyp_file) if "lyp_file" not in dir() else lyp_file
out_dir   = os.environ.get("KLAYOUT_OUT", out_dir) if "out_dir" not in dir() else out_dir
design    = os.environ.get("DESIGN", "design") if "design" not in dir() else design

width  = int(os.environ.get("IMG_WIDTH", "4096"))
height = int(os.environ.get("IMG_HEIGHT", "4096"))

print(f"=== KLayout Layout Visualization ===")
print(f"DEF:    {def_file}")
print(f"Tech:   {tech_file}")
print(f"LYP:    {lyp_file}")
print(f"Output: {out_dir}")
print(f"Size:   {width}x{height}")

os.makedirs(out_dir, exist_ok=True)

# Create layout view
main_window = pya.Application.instance().main_window()
view = main_window.create_layout(1)  # creates a new view
layout_view = main_window.current_view()

# Load technology
if os.path.exists(tech_file):
    tech_name = "FreePDK45"
    tech = pya.Technology.technology_by_name(tech_name)
    if tech is None:
        tech = pya.Technology.create_technology(tech_name)
    tech.load(tech_file)

# Load DEF with LEF context for cell resolution
def _load_def_with_lef(lv, def_path, idx=0):
    lo = pya.LoadLayoutOptions()
    lefdef = lo.lefdef_config
    lefdef.read_lef_with_def = False
    lef_paths = []
    if tech_lef and os.path.exists(tech_lef):
        lef_paths.append(tech_lef)
    if cell_lef and os.path.exists(cell_lef):
        lef_paths.append(cell_lef)
    if lef_paths:
        try:
            lefdef.lef_files = lef_paths
        except Exception:
            pass
    lv.load_layout(def_path, lo, idx)

_load_def_with_lef(layout_view, def_file)

# Load layer properties
if os.path.exists(lyp_file):
    layout_view.load_layer_props(lyp_file)

# Fit the view to the full extent of the layout
layout_view.zoom_fit()

# --- Full layout image ---
img_path = os.path.join(out_dir, f"{design}_layout.png")
layout_view.save_image(img_path, width, height)
print(f"Full layout: {img_path}")

# --- Generate per-stage images if intermediate DEFs exist ---
for stage, suffix in [("floorplan", "_floorplan.def"),
                       ("placed", "_placed.def"),
                       ("cts", "_cts.def"),
                       ("grouted", "_grouted.def"),
                       ("final", "_final.def")]:
    stage_def = os.path.join(os.path.dirname(def_file), f"{design}{suffix}")
    if os.path.exists(stage_def) and stage_def != def_file:
        _load_def_with_lef(layout_view, stage_def)
        if os.path.exists(lyp_file):
            layout_view.load_layer_props(lyp_file)
        layout_view.zoom_fit()
        img = os.path.join(out_dir, f"{design}_{stage}.png")
        layout_view.save_image(img, width, height)
        print(f"Stage [{stage}]: {img}")

print("=== KLayout rendering complete ===")
