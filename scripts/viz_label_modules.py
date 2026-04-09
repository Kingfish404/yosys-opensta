#!/usr/bin/env python3
"""
Generate a labeled layout PNG showing module regions on a chip.

Reconstructs module hierarchy from flattened netlist:
1. Maps cells → modules using net naming from synth JSON (gen-arch.py logic)
2. Maps JSON cells → DEF instances via verilog ordering
3. Parses DEF COMPONENTS for instance positions
4. Computes per-module bounding boxes
5. Overlays labeled rectangles on the base PNG

Usage:
  python3 scripts/viz_label_modules.py \\
    --syn-json  result/nangate45-[DESIGN]-50MHz/[DESIGN]_syn.json \\
    --hier-json result/nangate45-[DESIGN]-50MHz/[DESIGN]_hier.json \\
    --netlist-v result/nangate45-[DESIGN]-50MHz/[DESIGN].netlist.syn.v \\
    --def-file  result/nangate45-[DESIGN]-50MHz-pnr/[DESIGN]_final.def \\
    --base-png  result/nangate45-[DESIGN]-50MHz-pnr/[DESIGN]_final.png \\
    -o          result/nangate45-[DESIGN]-50MHz-pnr/[DESIGN]_final.label.png
"""

import argparse
import json
import re
import sys
from collections import defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import matplotlib.patheffects
import matplotlib.image as mpimg
import numpy as np


# ─── Module colors ───────────────────────────────────────────────────

MODULE_COLORS = [
    "#e6194b", "#3cb44b", "#ffe119", "#4363d8", "#f58231",
    "#911eb4", "#42d4f4", "#f032e6", "#bfef45", "#fabed4",
    "#469990", "#dcbeff", "#9A6324", "#fffac8", "#800000",
    "#aaffc3", "#808000", "#ffd8b1", "#000075", "#a9a9a9",
]


def _find_top_module(modules):
    """Find the top module — prefer the one with most cells/ports among top=1 candidates."""
    candidates = []
    for name, mod in modules.items():
        attrs = mod.get("attributes", {})
        top_val = attrs.get("top", "0")
        if top_val in ("1", "00000000000000000000000000000001"):
            size = len(mod.get("cells", {})) + len(mod.get("ports", {})) + len(mod.get("netnames", {}))
            candidates.append((size, name, mod))
    if candidates:
        candidates.sort(reverse=True)
        return candidates[0][2]
    return next(iter(modules.values()))


def extract_module_prefixes(hier_json_path):
    """Extract primary module prefixes from hierarchy JSON net names."""
    with open(hier_json_path) as f:
        data = json.load(f)

    top_mod = _find_top_module(data.get("modules", {}))

    netnames = top_mod.get("netnames", {})
    prefix_count = defaultdict(int)
    for name in netnames:
        if name.startswith("$") or "." not in name:
            continue
        prefix = name.split(".")[0]
        prefix_count[prefix] += 1

    # Separate primary vs bridge modules
    simple = {p for p in prefix_count if "_" not in p}
    primary = dict(prefix_count)  # start with all
    for p in list(primary):
        if "_" in p:
            parts = p.split("_")
            for i in range(1, len(parts)):
                left = "_".join(parts[:i])
                right = "_".join(parts[i:])
                if left in simple and right in simple:
                    del primary[p]
                    break

    return primary


def _compute_hier_cell_proportions(hier_json_path, module_prefixes):
    """Compute per-module cell proportions from the pre-synth hierarchy JSON.

    The hier JSON has accurate module assignments (pre-synthesis cells map
    cleanly to modules via net naming).  We use these proportions as the
    reference for capping propagation in the post-synth mapping.

    Returns: dict {module_prefix: fraction_of_total_cells}
    """
    with open(hier_json_path) as f:
        data = json.load(f)

    top_mod = _find_top_module(data.get("modules", {}))
    netnames = top_mod.get("netnames", {})
    cells = top_mod.get("cells", {})

    # bit → prefix
    bit_to_prefix = defaultdict(set)
    for name, info in netnames.items():
        if name.startswith("$") or "." not in name:
            continue
        prefix = name.split(".")[0]
        if prefix not in module_prefixes:
            continue
        for bit in info.get("bits", []):
            if isinstance(bit, int):
                bit_to_prefix[bit].add(prefix)

    # cell → bits, bit → cells
    cell_bits = {}
    bit_to_cells = defaultdict(set)
    for cell_name, cell_info in cells.items():
        bits = set()
        for conn_bits in cell_info.get("connections", {}).values():
            for bit in conn_bits:
                if isinstance(bit, int):
                    bits.add(bit)
                    bit_to_cells[bit].add(cell_name)
        cell_bits[cell_name] = bits

    # Direct assignment
    cell_module = {}
    for cell_name, bits in cell_bits.items():
        prefix_votes = defaultdict(int)
        for bit in bits:
            for pfx in bit_to_prefix.get(bit, set()):
                prefix_votes[pfx] += 1
        if prefix_votes:
            cell_module[cell_name] = max(prefix_votes, key=lambda m: prefix_votes[m])

    # Propagation (works well on hier JSON since cells are pre-synth)
    for _ in range(5):
        newly = {}
        for cell_name, bits in cell_bits.items():
            if cell_name in cell_module:
                continue
            neighbor_votes = defaultdict(int)
            for bit in bits:
                for neighbor in bit_to_cells.get(bit, set()):
                    if neighbor != cell_name and neighbor in cell_module:
                        neighbor_votes[cell_module[neighbor]] += 1
            if neighbor_votes:
                newly[cell_name] = max(neighbor_votes, key=lambda m: neighbor_votes[m])
        if not newly:
            break
        cell_module.update(newly)

    mod_count = defaultdict(int)
    for mod in cell_module.values():
        mod_count[mod] += 1
    total = max(1, sum(mod_count.values()))
    return {mod: cnt / total for mod, cnt in mod_count.items()}


def map_cells_to_modules(syn_json_path, module_prefixes, hier_proportions=None,
                         hier_json_path=None, max_propagation_iters=0):
    """Map each cell in the synth JSON to a module prefix via net connections.

    Strategy:
    1. Build bit→prefix mapping from BOTH hier JSON (pre-synth, richer hierarchy)
       and syn JSON (post-synth).  Yosys preserves bit numbering through synthesis,
       so hier bit IDs are valid in syn cells.
    2. Direct assignment via bit→prefix mapping (pass 1)
    3. Optional controlled propagation (pass 2+) — disabled by default because
       post-synthesis buffer chains cause module assignments to spread across
       the entire chip.  Use spatial_assign_cells() instead for remaining cells.

    Args:
        syn_json_path: path to post-synth Yosys JSON
        module_prefixes: dict {prefix: net_count} from hier JSON
        hier_proportions: optional dict {prefix: fraction} from hier JSON cell
            distribution, used to cap propagation.
        hier_json_path: optional path to pre-synth hierarchy JSON; its bit→prefix
            mapping greatly improves direct assignment coverage.
        max_propagation_iters: max connectivity propagation rounds (default 0 =
            direct assignment only; use spatial_assign_cells for the rest).

    Returns: ordered list of (json_cell_name, module_or_None)
    """
    print("    loading syn JSON...", flush=True)
    with open(syn_json_path) as f:
        data = json.load(f)
    print("    syn JSON loaded", flush=True)

    top_mod = _find_top_module(data.get("modules", {}))

    netnames = top_mod.get("netnames", {})
    cells = top_mod.get("cells", {})

    # Build bit → module prefix mapping from BOTH hier and syn JSON.
    # The hier JSON has many more hierarchically-named nets (pre-synthesis),
    # and its bit IDs are preserved through synthesis (hier bits ⊂ syn bits).
    bit_to_prefix = defaultdict(set)

    # (a) From hier JSON (primary source — much richer hierarchy info)
    if hier_json_path:
        with open(hier_json_path) as f:
            hier_data = json.load(f)
        hier_top = _find_top_module(hier_data.get("modules", {}))
        for name, info in hier_top.get("netnames", {}).items():
            if name.startswith("$") or "." not in name:
                continue
            prefix = name.split(".")[0]
            if prefix not in module_prefixes:
                continue
            for bit in info.get("bits", []):
                if isinstance(bit, int):
                    bit_to_prefix[bit].add(prefix)

    # (b) From syn JSON (supplements with any post-synth hierarchical nets)
    for name, info in netnames.items():
        if name.startswith("$") or "." not in name:
            continue
        prefix = name.split(".")[0]
        if prefix not in module_prefixes:
            continue
        for bit in info.get("bits", []):
            if isinstance(bit, int):
                bit_to_prefix[bit].add(prefix)

    # Build cell→bits, bit→cells index, and cell pin count
    cell_bits = {}
    cell_pin_count = {}
    bit_to_cells_raw = defaultdict(set)
    for cell_name, cell_info in cells.items():
        bits = set()
        for conn_bits in cell_info.get("connections", {}).values():
            for bit in conn_bits:
                if isinstance(bit, int):
                    bits.add(bit)
                    bit_to_cells_raw[bit].add(cell_name)
        cell_bits[cell_name] = bits
        cell_pin_count[cell_name] = len(cell_info.get("connections", {}))

    # Filter out high-fanout bits (clock, reset, etc.) from the neighbor index.
    # A bit connected to >500 cells is a global signal that provides no module
    # differentiation but causes O(N*F) blowup in propagation.
    MAX_FANOUT = 500
    bit_to_cells = {bit: cells_set for bit, cells_set in bit_to_cells_raw.items()
                    if len(cells_set) <= MAX_FANOUT}
    n_dropped = sum(1 for s in bit_to_cells_raw.values() if len(s) > MAX_FANOUT)
    if n_dropped:
        print(f"    (dropped {n_dropped} high-fanout bits from propagation index)", flush=True)

    # Identify 2-pin cells (buffers/inverters) — these form long chains and
    # must not participate in propagation to prevent flooding.
    is_buffer = {cn for cn, pc in cell_pin_count.items() if pc <= 2}

    # Pass 1: direct assignment — cells with direct hierarchical net connections
    cell_module = {}
    for cell_name, bits in cell_bits.items():
        prefix_votes = defaultdict(int)
        for bit in bits:
            for pfx in bit_to_prefix.get(bit, set()):
                prefix_votes[pfx] += 1
        if prefix_votes:
            cell_module[cell_name] = max(prefix_votes, key=lambda m: prefix_votes[m])

    total_cells = len(cells)
    print(f"    pass 1 (direct): {len(cell_module)}/{total_cells} cells", flush=True)

    # Compute per-module caps from the reference proportions.
    if hier_proportions:
        ref_proportions = hier_proportions
    else:
        pass1_counts = defaultdict(int)
        for mod in cell_module.values():
            pass1_counts[mod] += 1
        p1_total = max(1, sum(pass1_counts.values()))
        ref_proportions = {mod: cnt / p1_total for mod, cnt in pass1_counts.items()}

    module_cap = {}
    for mod in set(list(ref_proportions.keys()) + list(module_prefixes.keys())):
        proportion = ref_proportions.get(mod, 0.01)
        module_cap[mod] = max(int(total_cells * proportion * 2),
                              int(total_cells * 0.01))

    module_cur_count = defaultdict(int)
    for mod in cell_module.values():
        module_cur_count[mod] += 1

    # Pass 2+: controlled propagation with buffer-chain dampening.
    # NOTE: Propagation is disabled by default (max_propagation_iters=0)
    # because post-synthesis buffer chains spread assignments across the
    # entire chip.  Use spatial_assign_cells() after this function instead.
    for iteration in range(max_propagation_iters):
        # Snapshot: only cells assigned before this iteration can vote
        voters = set(cell_module.keys())
        newly = {}
        for cell_name, bits in cell_bits.items():
            if cell_name in cell_module:
                continue
            neighbor_votes = defaultdict(float)
            for bit in bits:
                neighbors = bit_to_cells.get(bit)
                if neighbors is None:
                    continue
                for neighbor in neighbors:
                    if neighbor == cell_name or neighbor not in voters:
                        continue
                    # Dampen buffer votes to prevent chain flooding
                    if neighbor in is_buffer:
                        weight = 1
                    else:
                        weight = max(1, cell_pin_count.get(neighbor, 2) - 1)
                    neighbor_votes[cell_module[neighbor]] += weight
            if not neighbor_votes:
                continue
            best_mod = max(neighbor_votes, key=lambda m: neighbor_votes[m])
            total_weight = sum(neighbor_votes.values())
            if neighbor_votes[best_mod] / total_weight < 0.5:
                continue
            cap = module_cap.get(best_mod, int(total_cells * 0.01))
            if module_cur_count[best_mod] >= cap:
                continue
            newly[cell_name] = best_mod
            module_cur_count[best_mod] += 1
        if not newly:
            break
        cell_module.update(newly)
        print(f"    propagation pass {iteration+1}: +{len(newly)} cells "
              f"({len(cell_module)}/{total_cells} total)", flush=True)
    result = []
    for cell_name in cells:
        result.append((cell_name, cell_module.get(cell_name)))
    return result


def spatial_assign_cells(cell_modules, vlog_instances, positions, die,
                        grid_n=150, sigma_frac=0.05, min_dominance=0.3):
    """Assign unassigned cells to modules using spatial density from DEF positions.

    Builds a per-module Gaussian-smoothed density grid from already-assigned
    cells (the "seed" from direct net-based assignment), then assigns each
    remaining cell to the dominant module at its grid location.

    This replaces connectivity-based propagation, which spreads module
    assignments across the entire chip via buffer chains.

    Returns: updated list of (cell_name, module_or_None), count of newly assigned
    """
    from scipy.ndimage import gaussian_filter

    die_x0, die_y0, die_x1, die_y1 = die
    die_w = die_x1 - die_x0
    die_h = die_y1 - die_y0
    if die_w <= 0 or die_h <= 0:
        return cell_modules, 0

    # Build module index from assigned cells
    mod_names = sorted(set(m for _, m in cell_modules if m is not None))
    if not mod_names:
        return cell_modules, 0
    mod_idx = {m: i for i, m in enumerate(mod_names)}
    n_mods = len(mod_names)

    # Accumulate per-module density grid from assigned cells
    grid = np.zeros((grid_n, grid_n, n_mods), dtype=np.float32)
    for i, (cell_name, mod) in enumerate(cell_modules):
        if mod is None or mod not in mod_idx or i >= len(vlog_instances):
            continue
        inst_name = vlog_instances[i]
        pos = positions.get(inst_name)
        if pos is None:
            continue
        x, y = pos
        gx = int((x - die_x0) / die_w * (grid_n - 1))
        gy = int((y - die_y0) / die_h * (grid_n - 1))
        gx = max(0, min(grid_n - 1, gx))
        gy = max(0, min(grid_n - 1, gy))
        grid[gy, gx, mod_idx[mod]] += 1

    # Gaussian smooth for spatial coherence
    sigma = max(3.0, grid_n * sigma_frac)
    smoothed = np.zeros_like(grid)
    for mi in range(n_mods):
        smoothed[:, :, mi] = gaussian_filter(grid[:, :, mi], sigma=sigma)

    # Precompute dominant module and total density per grid cell
    total_smooth = smoothed.sum(axis=2)
    dominant = np.argmax(smoothed, axis=2)
    dominant_strength = smoothed.max(axis=2)

    # Density threshold: ignore grid cells with negligible total density
    density_thresh = total_smooth.max() * 0.03

    # Assign unassigned cells based on spatial density
    new_modules = list(cell_modules)
    assigned_count = 0
    for i, (cell_name, mod) in enumerate(cell_modules):
        if mod is not None or i >= len(vlog_instances):
            continue
        inst_name = vlog_instances[i]
        pos = positions.get(inst_name)
        if pos is None:
            continue
        x, y = pos
        gx = int((x - die_x0) / die_w * (grid_n - 1))
        gy = int((y - die_y0) / die_h * (grid_n - 1))
        gx = max(0, min(grid_n - 1, gx))
        gy = max(0, min(grid_n - 1, gy))

        ts = total_smooth[gy, gx]
        if ts < density_thresh:
            continue
        ds = dominant_strength[gy, gx]
        if ds / ts < min_dominance:
            continue
        mi = dominant[gy, gx]
        new_modules[i] = (cell_name, mod_names[mi])
        assigned_count += 1

    return new_modules, assigned_count


def parse_verilog_instances(verilog_path):
    """Parse synthesized verilog to get ordered (instance_name, cell_type) list."""
    instances = []
    with open(verilog_path) as f:
        for line in f:
            m = re.match(r"\s+(\S+)\s+(_\d+_)\s*\(", line)
            if m:
                instances.append(m.group(2))  # just the instance name
    return instances


def parse_def_positions(def_path, target_instances):
    """Parse DEF COMPONENTS to get instance positions.

    Args:
        def_path: path to DEF file
        target_instances: set of instance names to extract

    Returns:
        dict {instance_name: (x, y)}, dbu, die tuple, core tuple
        where die = (x0, y0, x1, y1) and core = (x0, y0, x1, y1) from ROW defs
    """
    positions = {}
    dbu = 1000
    die = (0, 0, 0, 0)
    core = None
    in_components = False
    rows_x = []
    rows_y = []

    with open(def_path) as f:
        for line in f:
            # UNITS
            m = re.match(r"UNITS\s+DISTANCE\s+MICRONS\s+(\d+)", line)
            if m:
                dbu = int(m.group(1))
                continue

            # DIEAREA
            m = re.match(
                r"DIEAREA\s*\(\s*([\d.-]+)\s+([\d.-]+)\s*\)\s*\(\s*([\d.-]+)\s+([\d.-]+)\s*\)",
                line,
            )
            if m:
                die = (float(m.group(1)), float(m.group(2)),
                       float(m.group(3)), float(m.group(4)))
                continue

            # ROW definitions — extract placement core boundaries
            rm = re.match(
                r"ROW\s+\S+\s+\S+\s+(\d+)\s+(\d+)\s+\S+\s+DO\s+(\d+)\s+BY\s+\d+\s+STEP\s+(\d+)",
                line,
            )
            if rm:
                rx, ry = int(rm.group(1)), int(rm.group(2))
                rn, rstep = int(rm.group(3)), int(rm.group(4))
                rows_x.append(rx)
                rows_x.append(rx + rn * rstep)
                rows_y.append(ry)
                continue

            if re.match(r"\s*COMPONENTS\s+\d+", line):
                in_components = True
                continue
            if in_components and re.match(r"\s*END\s+COMPONENTS", line):
                break
            if not in_components:
                continue

            # Parse component line
            nm = re.match(r"\s*-\s+(\S+)\s+", line)
            if not nm:
                continue
            inst_name = nm.group(1)
            if inst_name not in target_instances:
                continue
            pm = re.search(
                r"\+\s*(?:PLACED|FIXED|COVER)\s*\(\s*([\d.-]+)\s+([\d.-]+)\s*\)",
                line,
            )
            if pm:
                positions[inst_name] = (float(pm.group(1)), float(pm.group(2)))

    if rows_x and rows_y:
        core = (min(rows_x), min(rows_y), max(rows_x), max(rows_y))

    return positions, dbu, die, core


def compute_module_bboxes(cell_modules, vlog_instances, positions):
    """Compute bounding box per module.

    Returns: {module_name: (x0, y0, x1, y1, count)}
    """
    bboxes = {}
    for i, (cell_name, mod) in enumerate(cell_modules):
        if mod is None or i >= len(vlog_instances):
            continue
        inst_name = vlog_instances[i]
        pos = positions.get(inst_name)
        if pos is None:
            continue
        x, y = pos
        if mod not in bboxes:
            bboxes[mod] = [x, y, x, y, 0]
        bb = bboxes[mod]
        if x < bb[0]: bb[0] = x
        if y < bb[1]: bb[1] = y
        if x > bb[2]: bb[2] = x
        if y > bb[3]: bb[3] = y
        bb[4] += 1
    return bboxes


def render_labeled_image(base_png, bboxes, dbu, die, out_path, min_count=50,
                         cell_modules=None, vlog_instances=None, positions=None,
                         core=None):
    """Overlay module regions and labels on the base PNG.

    Uses Gaussian-smoothed density heatmap for spatially coherent regions:
    1. Accumulate per-module cell counts on a fine grid
    2. Gaussian-blur each module's density layer for spatial coherence
    3. Assign each grid cell to the module with highest smoothed density
    4. Render colored regions via RGBA overlays (vectorized imshow)
    """
    from scipy.ndimage import gaussian_filter, binary_erosion, binary_dilation

    img = mpimg.imread(base_png)
    img_h, img_w = img.shape[:2]

    die_x0, die_y0, die_x1, die_y1 = die
    die_w = die_x1 - die_x0
    die_h = die_y1 - die_y0

    fig, ax = plt.subplots(1, 1, figsize=(img_w / 100, img_h / 100), dpi=100)
    ax.imshow(img, extent=[0, img_w, 0, img_h])
    ax.set_xlim(0, img_w)
    ax.set_ylim(0, img_h)
    ax.set_aspect("equal")
    ax.axis("off")
    fig.subplots_adjust(left=0, right=1, top=1, bottom=0)

    # Filter to significant modules
    sig_mods = sorted(
        [(mod, bb) for mod, bb in bboxes.items() if bb[4] >= min_count],
        key=lambda x: -x[1][4],
    )
    mod_names = [m for m, _ in sig_mods]
    mod_color = {m: MODULE_COLORS[i % len(MODULE_COLORS)] for i, m in enumerate(mod_names)}

    if cell_modules is not None and vlog_instances is not None and positions is not None and mod_names:
        grid_n = 150  # finer grid for better spatial detail
        n_mods = len(mod_names)
        mod_idx = {m: i for i, m in enumerate(mod_names)}
        grid = np.zeros((grid_n, grid_n, n_mods), dtype=np.float32)

        for i, (cell_name, mod) in enumerate(cell_modules):
            if mod is None or mod not in mod_idx or i >= len(vlog_instances):
                continue
            inst_name = vlog_instances[i]
            pos = positions.get(inst_name)
            if pos is None:
                continue
            x, y = pos
            gx = int((x - die_x0) / die_w * (grid_n - 1))
            gy = int((y - die_y0) / die_h * (grid_n - 1))
            gx = max(0, min(grid_n - 1, gx))
            gy = max(0, min(grid_n - 1, gy))
            grid[gy, gx, mod_idx[mod]] += 1

        # Gaussian smooth each module's density for spatial coherence.
        # sigma ~ 5% of grid size creates cohesive blobs.
        sigma = max(3.0, grid_n * 0.05)
        smoothed = np.zeros_like(grid)
        for mi in range(n_mods):
            smoothed[:, :, mi] = gaussian_filter(grid[:, :, mi], sigma=sigma)

        # Total raw density (unsmoothed) — used to mask empty regions
        total_raw = grid.sum(axis=2)
        # Smoothed total for mask threshold
        total_smooth = gaussian_filter(total_raw, sigma=sigma)
        density_thresh = total_smooth.max() * 0.05

        # Cell-presence mask: constrain regions to where cells actually exist.
        # Without this, Gaussian tails bleed into IO rings, power margins, and
        # die-edge padding where no cells are placed.
        presence = (total_raw > 0).astype(np.float32)
        presence_smooth = gaussian_filter(presence, sigma=sigma * 0.4)
        presence_mask = presence_smooth > (presence_smooth.max() * 0.15)
        # Erode the presence mask to pull label regions away from the edge of
        # the placement core (prevents bleeding into power ring / IO area).
        presence_mask = binary_erosion(presence_mask, iterations=2)

        # Core-area mask: if ROW definitions gave us a core boundary, clip the
        # label overlay strictly to the placement core region.
        if core is not None:
            core_x0, core_y0, core_x1, core_y1 = core
            gx_centers = die_x0 + (np.arange(grid_n) + 0.5) / grid_n * die_w
            gy_centers = die_y0 + (np.arange(grid_n) + 0.5) / grid_n * die_h
            gx_grid, gy_grid = np.meshgrid(gx_centers, gy_centers)
            core_mask = ((gx_grid >= core_x0) & (gx_grid <= core_x1) &
                         (gy_grid >= core_y0) & (gy_grid <= core_y1))
            presence_mask = presence_mask & core_mask

        # Dominant module per grid cell from smoothed densities
        dominant = np.argmax(smoothed, axis=2)  # (grid_n, grid_n)
        dominant_strength = smoothed.max(axis=2)

        # Mask: only show where there's meaningful density AND actual cells nearby
        mask_active = (total_smooth > density_thresh) & presence_mask

        cell_w = img_w / grid_n
        cell_h = img_h / grid_n

        # Pre-compute per-cell dominance ratio
        total_safe = np.maximum(total_smooth, 1e-8)
        ratio = dominant_strength / total_safe

        def hex2rgb(h):
            """Convert hex color to RGB floats."""
            h = h.lstrip('#')
            return [int(h[i:i+2], 16) / 255.0 for i in (0, 2, 4)]

        # --- Draw filled regions via RGBA overlay (vectorized) ---
        overlay = np.zeros((grid_n, grid_n, 4), dtype=np.float32)
        for mi, mod in enumerate(mod_names):
            mod_region = mask_active & (dominant == mi) & (ratio >= 0.25)
            if not mod_region.any():
                continue
            rgb = hex2rgb(mod_color[mod])
            alpha = np.where(mod_region, np.minimum(0.50, 0.12 + 0.38 * ratio), 0)
            for c in range(3):
                overlay[:, :, c] = np.where(mod_region,
                    overlay[:, :, c] * (1 - alpha) + rgb[c] * alpha,
                    overlay[:, :, c])
            overlay[:, :, 3] = np.where(mod_region,
                1 - (1 - overlay[:, :, 3]) * (1 - alpha),
                overlay[:, :, 3])

        ax.imshow(overlay, extent=[0, img_w, 0, img_h],
                  interpolation='nearest', origin='lower', zorder=2)

        # --- Draw contour borders via RGBA overlay (vectorized) ---
        border_overlay = np.zeros((grid_n, grid_n, 4), dtype=np.float32)
        for mi, mod in enumerate(mod_names):
            mod_mask = (mask_active & (dominant == mi) &
                        (smoothed[:, :, mi] / total_safe >= 0.3))
            if mod_mask.sum() < 4:
                continue
            # Morphological close then open to smooth boundaries
            mod_mask = binary_dilation(mod_mask, iterations=2)
            mod_mask = binary_erosion(mod_mask, iterations=3)
            mod_mask = binary_dilation(mod_mask, iterations=1)
            # Clip to cell-presence area
            mod_mask = mod_mask & presence_mask
            interior = binary_erosion(mod_mask, iterations=1)
            border = mod_mask & ~interior
            if not border.any():
                continue
            rgb = hex2rgb(mod_color[mod])
            a = 0.75
            for c in range(3):
                border_overlay[:, :, c] = np.where(border,
                    border_overlay[:, :, c] * (1 - a) + rgb[c] * a,
                    border_overlay[:, :, c])
            border_overlay[:, :, 3] = np.where(border,
                1 - (1 - border_overlay[:, :, 3]) * (1 - a),
                border_overlay[:, :, 3])

        ax.imshow(border_overlay, extent=[0, img_w, 0, img_h],
                  interpolation='nearest', origin='lower', zorder=3)

    # --- Compute weighted centroid per module for label placement ---
    centroids = {}
    if cell_modules is not None and vlog_instances is not None and positions is not None and mod_names:
        gy_coords, gx_coords = np.mgrid[0:grid_n, 0:grid_n]
        for mi, mod in enumerate(mod_names):
            mod_density = smoothed[:, :, mi].copy()
            mod_density[~(mask_active & (dominant == mi))] = 0
            if mod_density.max() < 1e-8:
                continue
            total_d = mod_density.sum()
            if total_d < 1e-8:
                continue
            cy_grid = (gy_coords * mod_density).sum() / total_d
            cx_grid = (gx_coords * mod_density).sum() / total_d
            centroids[mod] = (cx_grid * cell_w + cell_w / 2,
                              cy_grid * cell_h + cell_h / 2)

    # --- Draw labels at centroids ---
    for mod in mod_names:
        if mod not in centroids:
            continue
        cx, cy = centroids[mod]
        color = mod_color[mod]
        fontsize = 20
        ax.text(
            cx, cy, mod,
            color=color,
            fontsize=fontsize + 2,
            fontweight="bold",
            ha="center", va="center",
            zorder=4,
            path_effects=[
                matplotlib.patheffects.withStroke(linewidth=7, foreground="white"),
            ],
        )
        ax.text(
            cx, cy, mod,
            color="white",
            fontsize=fontsize,
            fontweight="bold",
            ha="center", va="center",
            zorder=5,
            bbox=dict(
                boxstyle="round,pad=0.5",
                facecolor=color,
                edgecolor="white",
                linewidth=2.0,
                alpha=0.92,
            ),
        )

    plt.savefig(out_path, dpi=100, pad_inches=0)
    plt.close()
    print(f"Saved: {out_path}")


def main():
    parser = argparse.ArgumentParser(description="Generate labeled module layout PNG")
    parser.add_argument("--syn-json", required=True, help="Post-synth JSON from yosys")
    parser.add_argument("--hier-json", required=True, help="Pre-synth hierarchy JSON")
    parser.add_argument("--netlist-v", required=True, help="Synthesized verilog netlist")
    parser.add_argument("--def-file", required=True, help="Final DEF file")
    parser.add_argument("--base-png", required=True, help="Base layout PNG to annotate")
    parser.add_argument("-o", "--output", default=None, help="Output labeled PNG path")
    parser.add_argument("--min-count", type=int, default=50,
                        help="Min instance count to show a module (default 50)")
    args = parser.parse_args()

    if args.output is None:
        args.output = args.base_png.replace(".png", ".label.png")

    print("Step 1: Extract module prefixes from hierarchy JSON...")
    module_prefixes = extract_module_prefixes(args.hier_json)
    print(f"  Found {len(module_prefixes)} primary modules")

    print("Step 1b: Compute reference cell proportions from hierarchy JSON...")
    hier_proportions = _compute_hier_cell_proportions(args.hier_json, module_prefixes)
    for mod, prop in sorted(hier_proportions.items(), key=lambda x: -x[1]):
        print(f"  {mod:20s}: {prop:.1%}")

    print("Step 2: Map cells to modules via net connections (direct only)...")
    cell_modules = map_cells_to_modules(args.syn_json, module_prefixes,
                                        hier_proportions,
                                        hier_json_path=args.hier_json,
                                        max_propagation_iters=0)
    assigned = sum(1 for _, m in cell_modules if m is not None)
    print(f"  {assigned}/{len(cell_modules)} cells directly assigned")

    print("Step 3: Parse verilog instance names...")
    vlog_instances = parse_verilog_instances(args.netlist_v)
    print(f"  {len(vlog_instances)} instances")
    assert len(vlog_instances) == len(cell_modules), \
        f"Count mismatch: verilog={len(vlog_instances)} vs JSON={len(cell_modules)}"

    print("Step 4: Parse DEF for instance positions...")
    target = set(vlog_instances)
    positions, dbu, die, core = parse_def_positions(args.def_file, target)
    print(f"  {len(positions)}/{len(target)} instances located (dbu={dbu})")
    if core:
        cw = (core[2] - core[0]) / dbu
        ch = (core[3] - core[1]) / dbu
        print(f"  Core area: {cw:.1f} x {ch:.1f} um")

    print("Step 4b: Spatial assignment using DEF positions...")
    cell_modules, n_spatial = spatial_assign_cells(
        cell_modules, vlog_instances, positions, die)
    assigned = sum(1 for _, m in cell_modules if m is not None)
    print(f"  +{n_spatial} cells via spatial density ({assigned}/{len(cell_modules)} total)")

    print("Step 5: Compute module bounding boxes...")
    bboxes = compute_module_bboxes(cell_modules, vlog_instances, positions)
    for mod, bb in sorted(bboxes.items(), key=lambda x: -x[1][4]):
        x0, y0, x1, y1, cnt = bb
        w_um = (x1 - x0) / dbu
        h_um = (y1 - y0) / dbu
        print(f"  {mod:20s}: {cnt:6d} cells, {w_um:.0f} x {h_um:.0f} um")

    print("Step 6: Render labeled image...")
    render_labeled_image(
        args.base_png, bboxes, dbu, die, args.output, args.min_count,
        cell_modules=cell_modules, vlog_instances=vlog_instances, positions=positions,
        core=core,
    )
    print("Done.")


if __name__ == "__main__":
    main()
