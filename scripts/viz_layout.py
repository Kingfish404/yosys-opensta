#!/usr/bin/env python3
"""
Pure-Python DEF layout visualizer using matplotlib.
No GUI, X11, or Xvfb needed — works in headless CLI mode.
Generates ISSCC/academic-paper style chip layout images.

Usage:
  python3 viz_layout.py <pnr_result_dir> [--design NAME] [--dpi DPI] [-o OUT_DIR]
                        [--lef LEF_FILE ...] [--format svg|png|pdf]

Reads DEF files from the PnR result directory and generates images for
each stage (floorplan, placed, cts, grouted, final).
"""

import argparse
import os
import re
import sys
from dataclasses import dataclass, field

import matplotlib
matplotlib.use("Agg")  # headless backend — no display needed
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.collections import PatchCollection, LineCollection

# ─── DEF data structures ─────────────────────────────────────────────

@dataclass
class Component:
    name: str
    cell: str
    x: float
    y: float
    orient: str
    status: str = ""  # PLACED / FIXED / COVER

@dataclass
class Pin:
    name: str
    direction: str = ""
    x: float = 0.0
    y: float = 0.0
    layer: str = ""

@dataclass
class RouteSeg:
    layer: str
    x0: float
    y0: float
    x1: float
    y1: float
    net: str = ""

@dataclass
class Row:
    name: str
    site: str
    x: float
    y: float
    orient: str
    num: int
    step_x: float
    step_y: float

@dataclass
class DEFData:
    design: str = ""
    dbu: int = 1000
    die_xl: float = 0
    die_yl: float = 0
    die_xh: float = 0
    die_yh: float = 0
    rows: list = field(default_factory=list)
    components: list = field(default_factory=list)
    pins: list = field(default_factory=list)
    nets_routes: list = field(default_factory=list)
    special_routes: list = field(default_factory=list)
    net_io_direction: dict = field(default_factory=dict)  # net_name -> "INPUT"/"OUTPUT"/"INOUT"


# ─── DEF parser ──────────────────────────────────────────────────────

def _join_continued_lines(text: str) -> list:
    """Split DEF text into individual statements (joined across line breaks, split on ';')."""
    statements = []
    buf = ""
    for raw in text.splitlines():
        stripped = raw.strip()
        if not stripped:
            continue
        buf += " " + stripped if buf else stripped
        if stripped.endswith(";"):
            # A single buf may contain e.g. "END FOO COMPONENTS 1017 ;"
            # Split on section keywords that appear mid-buffer
            _flush_buf(buf, statements)
            buf = ""
    if buf:
        _flush_buf(buf, statements)
    return statements


# Keywords that start DEF sections — must appear at word boundary
# followed by whitespace+digit (section headers) or end-of marker.
# Avoid matching inside net statements (e.g. NONDEFAULTRULE attribute).
_SECTION_RE = re.compile(
    r'(?:^|\s)(END\s+\w+|COMPONENTS\s+\d|PINS\s+\d|'
    r'NETS\s+\d|SPECIALNETS\s+\d|NONDEFAULTRULES\s+\d|'
    r'DIEAREA|DESIGN\s|UNITS\s|VERSION\s|ROW\s|TRACKS\s|'
    r'DIVIDERCHAR|BUSBITCHARS|PROPERTYDEFINITIONS\s)'
)

def _flush_buf(buf: str, statements: list):
    """Split a joined buffer that may contain multiple statements separated by keywords."""
    buf = buf.strip()
    if not buf:
        return
    # Find all keyword matches and split on them
    splits = list(_SECTION_RE.finditer(buf))
    if len(splits) <= 1:
        statements.append(buf)
        return
    # Check if first keyword is not at position 0 — emit the prefix
    prev = 0
    for m in splits:
        if m.start() > prev:
            part = buf[prev:m.start()].strip()
            if part:
                statements.append(part)
        prev = m.start()
    if prev < len(buf):
        statements.append(buf[prev:].strip())


def parse_def(filepath: str) -> DEFData:
    data = DEFData()
    with open(filepath, "r") as f:
        text = f.read()

    lines = _join_continued_lines(text)

    i = 0
    while i < len(lines):
        line = lines[i]

        # DESIGN name
        m = re.match(r"DESIGN\s+(\S+)\s*;", line)
        if m:
            data.design = m.group(1)
            i += 1; continue

        # UNITS
        m = re.match(r"UNITS\s+DISTANCE\s+MICRONS\s+(\d+)\s*;", line)
        if m:
            data.dbu = int(m.group(1))
            i += 1; continue

        # DIEAREA
        m = re.match(r"DIEAREA\s*\(\s*([\d.-]+)\s+([\d.-]+)\s*\)\s*\(\s*([\d.-]+)\s+([\d.-]+)\s*\)\s*;", line)
        if m:
            data.die_xl = float(m.group(1))
            data.die_yl = float(m.group(2))
            data.die_xh = float(m.group(3))
            data.die_yh = float(m.group(4))
            i += 1; continue

        # ROW
        m = re.match(r"ROW\s+(\S+)\s+(\S+)\s+(\d+)\s+(\d+)\s+(\S+)\s+DO\s+(\d+)\s+BY\s+\d+\s+STEP\s+(\d+)\s+(\d+)\s*;", line)
        if m:
            data.rows.append(Row(
                name=m.group(1), site=m.group(2),
                x=float(m.group(3)), y=float(m.group(4)),
                orient=m.group(5), num=int(m.group(6)),
                step_x=float(m.group(7)), step_y=float(m.group(8)),
            ))
            i += 1; continue

        # COMPONENTS section
        if re.match(r"COMPONENTS\s+\d+\s*;", line):
            i += 1
            while i < len(lines):
                cl = lines[i]
                if re.match(r"END\s+COMPONENTS", cl):
                    break
                # - name cell ... [+ SOURCE DIST] + PLACED/FIXED ( x y ) orient ;
                nm = re.match(r"-\s+(\S+)\s+(\S+)", cl)
                pm = re.search(r"\+\s*(?:PLACED|FIXED|COVER)\s*\(\s*([\d.-]+)\s+([\d.-]+)\s*\)\s*(\S+)", cl)
                if nm and pm:
                    status = "FIXED" if "FIXED" in cl else "PLACED"
                    data.components.append(Component(
                        name=nm.group(1), cell=nm.group(2),
                        x=float(pm.group(1)), y=float(pm.group(2)),
                        orient=pm.group(3), status=status,
                    ))
                i += 1
            i += 1; continue

        # PINS section
        if re.match(r"PINS\s+\d+\s*;", line):
            i += 1
            while i < len(lines):
                cl = lines[i]
                if re.match(r"END\s+PINS", cl):
                    break
                nm = re.match(r"-\s+(\S+)", cl)
                if not nm:
                    i += 1; continue
                name = nm.group(1)
                dm = re.search(r"\+\s*DIRECTION\s+(INPUT|OUTPUT|INOUT)", cl)
                direction = dm.group(1) if dm else ""
                # extract PLACED/FIXED ( x y ) — last occurrence
                pm = list(re.finditer(r"\+\s*(?:PLACED|FIXED)\s*\(\s*([\d.-]+)\s+([\d.-]+)\s*\)", cl))
                x, y = (float(pm[-1].group(1)), float(pm[-1].group(2))) if pm else (0, 0)
                lm = re.search(r"\+\s*LAYER\s+(\S+)", cl)
                layer = lm.group(1) if lm else ""
                data.pins.append(Pin(name=name, direction=direction, x=x, y=y, layer=layer))
                i += 1
            i += 1; continue

        # NETS / SPECIALNETS — parse routed paths
        nets_match = re.match(r"(NETS|SPECIALNETS)\s+\d+\s*;", line)
        if nets_match:
            section = nets_match.group(1)
            is_special = section == "SPECIALNETS"
            # Build pin name -> direction lookup (for I/O net coloring)
            pin_dir_map = {p.name: p.direction for p in data.pins}
            i += 1
            while i < len(lines):
                cl = lines[i]
                if re.match(rf"END\s+{section}", cl):
                    break
                # Extract net name
                net_nm = re.match(r"-\s+(\S+)", cl)
                net_name = net_nm.group(1) if net_nm else ""
                # Detect I/O pin connections: ( PIN pin_name )
                if not is_special and net_name:
                    io_pins = re.findall(r"\(\s*PIN\s+(\S+)\s*\)", cl)
                    for pname in io_pins:
                        d = pin_dir_map.get(pname, "")
                        if d:
                            data.net_io_direction[net_name] = d
                # Parse routed segments: ROUTED/NEW layer [TAPER] ( x y [ext] ) ...
                for rm in re.finditer(r"(?:ROUTED|NEW)\s+(\S+?)(?:\s+TAPER)?\s+(.+?)(?=(?:NEW|;|$))", cl):
                    layer = rm.group(1)
                    seg_text = rm.group(2)
                    # Match ( x y ) or ( x y ext ) — take first 2 values, ignore optional 3rd
                    coords = re.findall(r"\(\s*([\d.*-]+)\s+([\d.*-]+)(?:\s+\d+)?\s*\)", seg_text)
                    prev_x, prev_y = None, None
                    for cx, cy in coords:
                        cur_x = float(cx) if cx != "*" else prev_x
                        cur_y = float(cy) if cy != "*" else prev_y
                        if cur_x is None or cur_y is None:
                            prev_x, prev_y = cur_x, cur_y
                            continue
                        if prev_x is not None and prev_y is not None:
                            seg = RouteSeg(layer=layer, x0=prev_x, y0=prev_y,
                                           x1=cur_x, y1=cur_y, net=net_name)
                            if is_special:
                                data.special_routes.append(seg)
                            else:
                                data.nets_routes.append(seg)
                        prev_x, prev_y = cur_x, cur_y
                i += 1
            i += 1; continue

        i += 1

    return data


# ─── LEF cell-size parser ────────────────────────────────────────────

def parse_lef_sizes(lef_paths: list) -> dict:
    """Parse LEF files to extract cell name -> (width, height) in microns."""
    sizes = {}
    for path in lef_paths:
        if not os.path.exists(path):
            continue
        with open(path) as f:
            cell_name = None
            for raw in f:
                line = raw.strip()
                m = re.match(r"MACRO\s+(\S+)", line)
                if m:
                    cell_name = m.group(1)
                    continue
                if cell_name and re.match(r"END\s+" + re.escape(cell_name), line):
                    cell_name = None
                    continue
                if cell_name:
                    m = re.match(r"SIZE\s+([\d.]+)\s+BY\s+([\d.]+)\s*;", line)
                    if m:
                        sizes[cell_name] = (float(m.group(1)), float(m.group(2)))
    return sizes


# ─── ISSCC-style color scheme (dark bg, bright neon layers) ──────────

BG_COLOR     = "#0d1117"       # deep dark (GitHub-dark inspired)
DIE_BG       = "#161b22"       # slightly lighter die area
ROW_COLOR    = "#21262d"       # subtle row bands
ROW_EDGE     = "#30363d"
CELL_COLOR   = "#1f6feb"       # muted blue cells (subtler for small die)
CELL_ALPHA   = 0.25
FIXED_COLOR  = "#f78166"       # orange for fixed/filler
FIXED_ALPHA  = 0.50

# Cell category colors — distinct hues for different functional groups
CELL_CAT_COLORS = {
    "DFF":    "#e3b341",   # gold — flip-flops / registers
    "LATCH":  "#d4a017",   # dark gold — latches
    "BUF":    "#58a6ff",   # blue — buffers
    "INV":    "#79c0ff",   # light blue — inverters
    "MUX":    "#b392f0",   # purple — multiplexers
    "AND":    "#3fb950",   # green — AND gates
    "OR":     "#85e89d",   # light green — OR gates
    "NAND":   "#f97583",   # pink-red — NAND gates
    "NOR":    "#f85149",   # red — NOR gates
    "XOR":    "#f692ce",   # magenta — XOR/XNOR gates
    "AOI":    "#ffab70",   # orange — AND-OR-Invert
    "OAI":    "#56d4dd",   # cyan — OR-AND-Invert
    "HA":     "#d29922",   # amber — half/full adders
    "FA":     "#d29922",
    "other":  "#8b949e",   # grey — uncategorized
}
CELL_CAT_ALPHA = 0.45

# Priority-ordered prefixes for cell categorization
_CELL_CAT_PREFIXES = [
    ("DFF", "DFF"), ("DFFR", "DFF"), ("DFFS", "DFF"), ("SDFF", "DFF"),
    ("LATCH", "LATCH"), ("DLATCH", "LATCH"),
    ("MUX", "MUX"),
    ("XNOR", "XOR"), ("XOR", "XOR"),
    ("AOI", "AOI"), ("OAI", "OAI"),
    ("NAND", "NAND"), ("NOR", "NOR"),
    ("AND", "AND"), ("OR", "OR"),
    ("BUF", "BUF"), ("CLKBUF", "BUF"),
    ("INV", "INV"),
    ("HA", "HA"), ("FA", "FA"),
]

def cell_category(cell_name: str) -> str:
    """Classify a standard cell name into a functional category."""
    base = cell_name.split("_")[0]  # e.g. AND2 from AND2_X1
    for prefix, cat in _CELL_CAT_PREFIXES:
        if base.startswith(prefix):
            return cat
    return "other"
PIN_IN_COLOR = "#3fb950"       # green
PIN_OUT_COLOR= "#f85149"       # red
PIN_IO_COLOR = "#d29922"       # amber
DIE_EDGE     = "#c9d1d9"       # light grey die outline

# Neon palette for metal layers — resembles EDA tool screenshots
METAL_COLORS = {
    "metal1":  "#58a6ff",  # blue
    "metal2":  "#f97583",  # pink-red
    "metal3":  "#85e89d",  # green
    "metal4":  "#ffab70",  # orange
    "metal5":  "#b392f0",  # purple
    "metal6":  "#79c0ff",  # light blue
    "metal7":  "#f692ce",  # magenta
    "metal8":  "#56d4dd",  # cyan
    "metal9":  "#e3b341",  # gold
    "metal10": "#8b949e",  # grey
    # ASAP7 layer names
    "M1":  "#58a6ff",
    "M2":  "#f97583",
    "M3":  "#85e89d",
    "M4":  "#ffab70",
    "M5":  "#b392f0",
    "M6":  "#79c0ff",
    "M7":  "#f692ce",
    "M8":  "#56d4dd",
    "M9":  "#e3b341",
}

# Line widths in points scaled per metal layer (higher = thicker)
METAL_LW = {
    "metal1": 0.15, "metal2": 0.20, "metal3": 0.25,
    "metal4": 0.35, "metal5": 0.40, "metal6": 0.50,
    "metal7": 0.70, "metal8": 0.80, "metal9": 1.0, "metal10": 1.0,
    # ASAP7 layer names
    "M1": 0.15, "M2": 0.20, "M3": 0.25,
    "M4": 0.35, "M5": 0.40, "M6": 0.50,
    "M7": 0.70, "M8": 0.80, "M9": 1.0,
}

def metal_color(layer: str) -> str:
    return METAL_COLORS.get(layer, "#8b949e")

def metal_lw(layer: str) -> float:
    return METAL_LW.get(layer, 0.3)


# ─── Rendering (ISSCC style) ────────────────────────────────────────

def render_def(data: DEFData, title: str, out_path: str, dpi: int = 300,
               show_routes: bool = True, show_special: bool = True,
               show_components: bool = True, show_pins: bool = True,
               cell_sizes: dict = None):
    """Render a DEF stage to an ISSCC-style layout image."""
    dbu = data.dbu if data.dbu > 0 else 1000
    die_w = (data.die_xh - data.die_xl) / dbu
    die_h = (data.die_yh - data.die_yl) / dbu

    if die_w <= 0 or die_h <= 0:
        print(f"  [SKIP] Invalid die area for {title}")
        return

    if cell_sizes is None:
        cell_sizes = {}

    # Figure setup — no spines, dark background
    aspect = die_w / die_h
    fig_h = 10
    fig_w = fig_h * aspect
    fig_w = max(fig_w, 6)
    fig_h = max(fig_h, 6)

    fig, ax = plt.subplots(1, 1, figsize=(fig_w, fig_h), dpi=dpi)
    fig.patch.set_facecolor(BG_COLOR)
    ax.set_facecolor(DIE_BG)
    ax.set_xlim(data.die_xl / dbu, data.die_xh / dbu)
    ax.set_ylim(data.die_yl / dbu, data.die_yh / dbu)
    ax.set_aspect("equal")

    # Remove all axes decorations
    ax.set_xticks([])
    ax.set_yticks([])
    for spine in ax.spines.values():
        spine.set_visible(False)

    # Die outline (subtle)
    die_rect = mpatches.FancyBboxPatch(
        (data.die_xl / dbu, data.die_yl / dbu), die_w, die_h,
        boxstyle="round,pad=0",
        linewidth=1.2, edgecolor=DIE_EDGE, facecolor=DIE_BG,
    )
    ax.add_patch(die_rect)

    # Row bands (alternating very subtle stripes)
    if data.rows:
        row_patches = []
        # Compute row height from consecutive rows or fallback
        default_rh = 2800 / dbu
        if len(data.rows) > 1:
            default_rh = abs(data.rows[1].y - data.rows[0].y) / dbu
        for idx, row in enumerate(data.rows):
            if idx % 2 != 0:
                continue  # alternate rows only for subtlety
            rw = row.num * row.step_x / dbu
            rh = row.step_y / dbu if row.step_y > 0 else default_rh  # row height from DEF
            row_patches.append(mpatches.Rectangle(
                (row.x / dbu, row.y / dbu), rw, rh,
            ))
        if row_patches:
            ax.add_collection(PatchCollection(
                row_patches, facecolor=ROW_COLOR, edgecolor="none",
                linewidth=0, alpha=0.4,
            ))

    # Special nets (power/ground) — draw BELOW cells so they appear as grid
    if show_special and data.special_routes:
        layer_segs = {}
        for seg in data.special_routes:
            layer_segs.setdefault(seg.layer, []).append(
                [(seg.x0 / dbu, seg.y0 / dbu), (seg.x1 / dbu, seg.y1 / dbu)]
            )
        for layer, segs in layer_segs.items():
            ax.add_collection(LineCollection(
                segs, colors=metal_color(layer), linewidths=metal_lw(layer) * 2,
                alpha=0.25, zorder=1,
            ))

    # Components (standard cells) — with real sizes from LEF
    # Skip filler and tap cells (they fill empty space — invisible in ISSCC images)
    _SKIP_PREFIXES = ("FILLCELL", "FILLER", "TAPCELL", "WELLTAP", "ENDCAP", "DECAP")
    if show_components and data.components:
        # Group cells by category for per-category coloring
        cat_patches = {}   # category -> list of patches
        cell_info = []     # (cx, cy, cw, ch, cell_type) for labeling
        for comp in data.components:
            if any(comp.cell.startswith(p) for p in _SKIP_PREFIXES):
                continue
            sz = cell_sizes.get(comp.cell)
            cw = sz[0] if sz else 0.38  # default ~1 site width
            ch = sz[1] if sz else 1.4
            cx = comp.x / dbu
            cy = comp.y / dbu
            cat = cell_category(comp.cell)
            rect = mpatches.Rectangle((cx, cy), cw, ch)
            cat_patches.setdefault(cat, []).append(rect)
            cell_info.append((cx, cy, cw, ch, comp.cell, cat))
        # Draw each category with its own color
        for cat, patches in cat_patches.items():
            color = CELL_CAT_COLORS.get(cat, CELL_CAT_COLORS["other"])
            ax.add_collection(PatchCollection(
                patches, facecolor=color, edgecolor=color,
                alpha=CELL_CAT_ALPHA, linewidth=0.3, zorder=2,
            ))
        # Label cells — scale font to fit inside the cell rectangle
        if cell_info:
            for cx, cy, cw, ch, ctype, cat in cell_info:
                # Strip drive suffix for shorter label (e.g. AND2_X1 -> AND2)
                base = ctype.rsplit("_", 1)[0] if "_" in ctype else ctype
                # Estimate label width: ~0.6 * fontsize per char (in points)
                # Map cell width in data coords to approximate points
                pts_per_unit = (fig_w * 72) / die_w  # points per micron
                cell_w_pts = cw * pts_per_unit
                # Font size: fill ~40% of cell width, clamped
                fs = min(cell_w_pts * 0.4 / max(len(base), 1) / 0.6, ch * pts_per_unit * 0.3)
                fs = max(0.8, min(fs, 3.5))
                cat_color = CELL_CAT_COLORS.get(cat, CELL_CAT_COLORS["other"])
                ax.text(cx + cw / 2, cy + ch / 2, base,
                        fontsize=fs, color="white",
                        fontfamily="monospace", alpha=0.85,
                        ha="center", va="center", zorder=2,
                        clip_on=True)

    # Signal routes — per metal layer with distinct colors
    # Separate I/O-connected nets from internal nets
    io_dir_color = {
        "INPUT":  PIN_IN_COLOR,
        "OUTPUT": PIN_OUT_COLOR,
        "INOUT":  PIN_IO_COLOR,
    }
    if show_routes and data.nets_routes:
        layer_segs = {}       # internal nets: layer -> segments
        io_segs = {}          # I/O nets: direction -> segments
        for seg in data.nets_routes:
            direction = data.net_io_direction.get(seg.net, "")
            pt = [(seg.x0 / dbu, seg.y0 / dbu), (seg.x1 / dbu, seg.y1 / dbu)]
            if direction in io_dir_color:
                io_segs.setdefault(direction, []).append(pt)
            else:
                layer_segs.setdefault(seg.layer, []).append(pt)
        # Draw internal nets — lower metals first, higher on top
        for layer in sorted(layer_segs.keys(),
                            key=lambda l: int(re.search(r'\d+', l).group()) if re.search(r'\d+', l) else 0):
            segs = layer_segs[layer]
            ax.add_collection(LineCollection(
                segs, colors=metal_color(layer), linewidths=metal_lw(layer),
                alpha=0.75, zorder=3,
            ))
        # Draw I/O-connected nets with direction colors (on top)
        for direction, segs in io_segs.items():
            ax.add_collection(LineCollection(
                segs, colors=io_dir_color[direction], linewidths=0.5,
                alpha=0.85, zorder=4,
            ))

    # I/O Pins — bright diamonds on die edge with labels
    # Compute scale bar region to avoid label overlap
    _scale_bar_xl = data.die_xl / dbu + die_w * 0.01
    _scale_bar_xh = data.die_xl / dbu + die_w * 0.25
    _scale_bar_yh = data.die_yl / dbu + die_h * 0.10
    if show_pins and data.pins:
        for group, color, marker in [
            ("INPUT",  PIN_IN_COLOR,  "D"),
            ("OUTPUT", PIN_OUT_COLOR, "D"),
            ("INOUT",  PIN_IO_COLOR,  "D"),
        ]:
            pins_g = [p for p in data.pins if p.direction == group]
            xs = [p.x / dbu for p in pins_g]
            ys = [p.y / dbu for p in pins_g]
            if xs:
                ax.scatter(xs, ys, s=18, c=color, marker=marker,
                           zorder=6, edgecolors="white", linewidths=0.3, alpha=0.95)
                # Label a subset of pins (skip if too many)
                step = max(1, len(pins_g) // 12)
                for idx in range(0, len(pins_g), step):
                    p = pins_g[idx]
                    px, py = p.x / dbu, p.y / dbu
                    # Skip labels that would overlap with scale bar
                    if px < _scale_bar_xh and py < _scale_bar_yh:
                        continue
                    label = p.name.split('[')[0] if '[' in p.name else p.name
                    ha = 'right' if px < die_w / 2 else 'left'
                    offset = -die_w * 0.015 if ha == 'right' else die_w * 0.015
                    ax.annotate(label, (px, py),
                                xytext=(px + offset, py),
                                fontsize=3.5, color=color, alpha=0.8,
                                fontfamily='monospace', va='center', ha=ha,
                                zorder=7)

    # ─── Overlay: title + legend ─────────────────────────────────────
    # Title (top-left, within die area)
    ax.text(data.die_xl / dbu + die_w * 0.02,
            data.die_yh / dbu - die_h * 0.03,
            title, fontsize=11, fontweight="bold",
            color="#e6edf3", fontfamily="monospace",
            va="top", ha="left", zorder=10,
            bbox=dict(boxstyle="round,pad=0.3", facecolor=BG_COLOR, alpha=0.7, edgecolor="none"))

    # Legend (bottom-right, compact)
    legend_handles = []
    if show_components and data.components:
        # Show legend entries for each cell category present
        _CAT_LABELS = {
            "DFF": "Flip-Flop", "LATCH": "Latch", "BUF": "Buffer", "INV": "Inverter",
            "MUX": "MUX", "AND": "AND", "OR": "OR", "NAND": "NAND", "NOR": "NOR",
            "XOR": "XOR/XNOR", "AOI": "AOI", "OAI": "OAI",
            "HA": "Adder", "FA": "Adder", "other": "Other",
        }
        cats_present = set()
        for comp in data.components:
            if not any(comp.cell.startswith(p) for p in _SKIP_PREFIXES):
                cats_present.add(cell_category(comp.cell))
        # Stable ordering
        _CAT_ORDER = ["DFF", "LATCH", "BUF", "INV", "MUX", "AND", "OR",
                       "NAND", "NOR", "XOR", "AOI", "OAI", "HA", "FA", "other"]
        for cat in _CAT_ORDER:
            if cat in cats_present:
                legend_handles.append(mpatches.Patch(
                    color=CELL_CAT_COLORS.get(cat, CELL_CAT_COLORS["other"]),
                    alpha=0.6, label=_CAT_LABELS.get(cat, cat)))
    if show_routes and data.nets_routes:
        # Metal layer entries (only for internal nets)
        seen = set()
        for seg in data.nets_routes:
            if seg.net not in data.net_io_direction and seg.layer not in seen:
                seen.add(seg.layer)
        for layer in sorted(seen, key=lambda l: int(re.search(r'\d+', l).group()) if re.search(r'\d+', l) else 0):
            legend_handles.append(mpatches.Patch(color=metal_color(layer), label=layer))
        # I/O net route entries
        io_dirs_present = set(data.net_io_direction.get(s.net, "") for s in data.nets_routes)
        if "INPUT" in io_dirs_present:
            legend_handles.append(mpatches.Patch(color=PIN_IN_COLOR, label="Input Net"))
        if "OUTPUT" in io_dirs_present:
            legend_handles.append(mpatches.Patch(color=PIN_OUT_COLOR, label="Output Net"))
        if "INOUT" in io_dirs_present:
            legend_handles.append(mpatches.Patch(color=PIN_IO_COLOR, label="I/O Net"))
    if show_special and data.special_routes:
        legend_handles.append(mpatches.Patch(color="#8b949e", alpha=0.3, label="Power Grid"))
    if show_pins and data.pins:
        legend_handles.append(mpatches.Patch(color=PIN_IN_COLOR, label="Input Pin"))
        legend_handles.append(mpatches.Patch(color=PIN_OUT_COLOR, label="Output Pin"))

    if legend_handles:
        leg = ax.legend(handles=legend_handles, loc="lower right", fontsize=6,
                        framealpha=0.7, facecolor=BG_COLOR, edgecolor="#30363d",
                        labelcolor="#c9d1d9", handlelength=1.2, handleheight=0.8,
                        borderpad=0.5, labelspacing=0.3)
        leg.set_zorder(10)

    # Scale bar (bottom-left)
    _add_scale_bar(ax, die_w, die_h, data.die_xl / dbu, data.die_yl / dbu)

    plt.subplots_adjust(left=0.01, right=0.99, top=0.99, bottom=0.01)
    fig.savefig(out_path, dpi=dpi, bbox_inches="tight",
                facecolor=fig.get_facecolor(), edgecolor="none", pad_inches=0.05)
    plt.close(fig)
    print(f"  -> {out_path}")


def _add_scale_bar(ax, die_w, die_h, x0, y0):
    """Add a μm scale bar at the bottom-left of the die."""
    # Pick a nice round scale length (~10-20% of die width)
    raw = die_w * 0.15
    nice = 10 ** int(f"{raw:.0e}".split("e+")[1]) if raw >= 1 else 1
    for candidate in [0.5, 1, 2, 5, 10, 20, 50, 100]:
        if candidate >= raw * 0.5 and candidate <= raw * 1.5:
            nice = candidate
            break

    margin_x = die_w * 0.03
    margin_y = die_h * 0.05   # push up from bottom to avoid pin labels
    bar_x = x0 + margin_x
    bar_y = y0 + margin_y
    tick_h = die_h * 0.008
    ax.plot([bar_x, bar_x + nice], [bar_y, bar_y],
            color="#c9d1d9", linewidth=1.5, zorder=10, solid_capstyle="butt")
    ax.plot([bar_x, bar_x], [bar_y - tick_h, bar_y + tick_h],
            color="#c9d1d9", linewidth=1.0, zorder=10)
    ax.plot([bar_x + nice, bar_x + nice], [bar_y - tick_h, bar_y + tick_h],
            color="#c9d1d9", linewidth=1.0, zorder=10)
    label_text = f"{nice} μm" if nice >= 1 else f"{nice*1000:.0f} nm"
    ax.text(bar_x + nice / 2, bar_y + die_h * 0.015,
            label_text, fontsize=6, color="#c9d1d9",
            ha="center", va="bottom", fontfamily="monospace", zorder=10,
            bbox=dict(boxstyle="round,pad=0.15", facecolor=BG_COLOR, alpha=0.7, edgecolor="none"))


# ─── Multi-stage rendering ───────────────────────────────────────────

STAGES = [
    ("floorplan", "_floorplan.def", dict(show_routes=False, show_special=False)),
    ("placed",    "_placed.def",    dict(show_routes=False, show_special=False)),
    ("cts",       "_cts.def",       dict(show_routes=False, show_special=False)),
    ("grouted",   "_grouted.def",   dict(show_routes=True,  show_special=True)),
    ("final",     "_final.def",     dict(show_routes=True,  show_special=True)),
]


def main():
    parser = argparse.ArgumentParser(description="ISSCC-style DEF layout visualizer (no GUI needed)")
    parser.add_argument("pnr_dir", help="Path to PnR result directory containing DEF files")
    parser.add_argument("--design", "-d", default=None, help="Design name (auto-detected from DEF if omitted)")
    parser.add_argument("--dpi", type=int, default=300, help="Image resolution (default: 300)")
    parser.add_argument("-o", "--output", default=None, help="Output directory (default: <pnr_dir>/images)")
    parser.add_argument("--format", choices=["svg", "png", "pdf"], default="svg", help="Output format")
    parser.add_argument("--lef", nargs="*", default=[], help="LEF files for cell sizes (auto-detected if omitted)")
    args = parser.parse_args()

    pnr_dir = os.path.abspath(args.pnr_dir)
    out_dir = args.output or os.path.join(pnr_dir, "images")
    os.makedirs(out_dir, exist_ok=True)

    # Auto-detect design name from first DEF found
    design = args.design
    if not design:
        for _, suffix, _ in STAGES:
            candidates = [f for f in os.listdir(pnr_dir) if f.endswith(suffix)]
            if candidates:
                design = candidates[0].replace(suffix, "")
                break
    if not design:
        print("ERROR: Cannot auto-detect design name. Use --design.", file=sys.stderr)
        sys.exit(1)

    # Auto-detect LEF files if not provided
    lef_paths = args.lef
    if not lef_paths:
        # Look for LEF in the standard project layout
        proj_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        platform = os.environ.get("PLATFORM", "nangate45")
        platform_lef_dir = os.path.join(proj_root, "lib", platform, "lef")
        if os.path.isdir(platform_lef_dir):
            for f in sorted(os.listdir(platform_lef_dir)):
                if f.endswith(".lef"):
                    lef_paths.append(os.path.join(platform_lef_dir, f))

    cell_sizes = parse_lef_sizes(lef_paths)

    fmt = args.format
    print(f"=== ISSCC-style Layout Visualizer ===")
    print(f"  Design:  {design}")
    print(f"  PnR dir: {pnr_dir}")
    print(f"  Output:  {out_dir}")
    print(f"  Format:  {fmt}, DPI: {args.dpi}")
    print(f"  LEFs:    {len(lef_paths)} files, {len(cell_sizes)} cell sizes loaded")
    print()

    rendered = 0
    for stage, suffix, opts in STAGES:
        def_path = os.path.join(pnr_dir, f"{design}{suffix}")
        if not os.path.exists(def_path):
            print(f"  [skip] {stage}: {design}{suffix} not found")
            continue
        print(f"  Parsing {stage} ...")
        data = parse_def(def_path)
        out_path = os.path.join(out_dir, f"{design}_{stage}.{fmt}")
        render_def(data, f"{design} — {stage}", out_path, dpi=args.dpi,
                   cell_sizes=cell_sizes, **opts)
        rendered += 1

    # Also render routing-only and placement-only views of final stage
    final_def = os.path.join(pnr_dir, f"{design}_final.def")
    if os.path.exists(final_def):
        print(f"  Parsing final (extra views) ...")
        data = parse_def(final_def)

        # Placement-only view
        out_path = os.path.join(out_dir, f"{design}_placement.{fmt}")
        render_def(data, f"{design} — placement", out_path, dpi=args.dpi,
                   show_routes=False, show_special=False, cell_sizes=cell_sizes)

        # Routing-only view
        out_path = os.path.join(out_dir, f"{design}_routing.{fmt}")
        render_def(data, f"{design} — routing", out_path, dpi=args.dpi,
                   show_components=False, show_pins=False, cell_sizes=cell_sizes)
        rendered += 2

    print(f"\nDone — {rendered} images in {out_dir}/")


if __name__ == "__main__":
    main()
