"""Generate a clean module-level architecture diagram from yosys JSON output.

Reads the hierarchy JSON exported by `write_json` and produces a simple dot
graph showing sub-module instances and their bus-level connections.

Works with both:
- Multi-module designs (hierarchy preserved in JSON "modules")
- Flat/Chisel designs (hierarchy reconstructed from net naming: module.signal)
"""

import json
import re
from argparse import ArgumentParser
from collections import defaultdict


def find_top_module(modules, design_name=None):
    """Find the top module. Prefers design_name if given, then top=1 attribute."""
    if design_name and design_name in modules:
        return design_name, modules[design_name]
    # Among top=1 modules, pick the one with most cells/ports
    candidates = []
    for name, mod in modules.items():
        attrs = mod.get("attributes", {})
        top_val = attrs.get("top", "0")
        if top_val == "00000000000000000000000000000001" or top_val == "1":
            size = len(mod.get("cells", {})) + len(mod.get("ports", {}))
            candidates.append((size, name, mod))
    if candidates:
        candidates.sort(reverse=True)
        return candidates[0][1], candidates[0][2]
    return next(iter(modules.items()))


def sanitize(name):
    return name.replace("\\", "").strip()


def extract_hierarchy_from_nets(top_mod):
    """Reconstruct module hierarchy from net names in a flattened design.

    Chisel/FIRRTL flattened designs use naming: module.signal, mod_a_mod_b.signal
    Returns: (modules, bridges, hierarchy_tree)
      hierarchy_tree: nested dict {name: {"count": N, "children": {…}}}
    """
    netnames = top_mod.get("netnames", {})
    user_nets = {n: v for n, v in netnames.items() if not n.startswith("$")}

    # Collect level-1 prefixes (before first '.')
    prefix_signals = defaultdict(list)
    for name in user_nets:
        if "." in name:
            prefix = name.split(".")[0]
            signal = name.split(".", 1)[1]
            prefix_signals[prefix].append(signal)

    # Separate into "module" prefixes and "bridge" prefixes
    # Pass 1: exact match against simple (no underscore) prefixes
    all_simple = set()
    for p in prefix_signals:
        if "_" not in p:
            all_simple.add(p)

    modules = {}
    bridges = {}

    for prefix, signals in prefix_signals.items():
        found_bridge = False
        if "_" in prefix:
            parts = prefix.split("_")
            for i in range(1, len(parts)):
                left = "_".join(parts[:i])
                right = "_".join(parts[i:])
                if left in all_simple and right in all_simple:
                    bridges[prefix] = (left, right, len(signals))
                    found_bridge = True
                    break
        if not found_bridge:
            modules[prefix] = len(signals)

    # Pass 2: fuzzy match – resolve abbreviations like l1d->l1d_cache, csr->csrs
    def _fuzzy_resolve(part, exclude):
        """Resolve a bridge part to a known module via prefix matching."""
        if part in modules and part != exclude:
            return part
        # Prefer simple modules whose name starts with part (e.g. csr -> csrs)
        simple_cands = [m for m in all_simple if m.startswith(part) and m != part]
        if len(simple_cands) == 1:
            return simple_cands[0]
        # Compound modules starting with part_ (e.g. l1d -> l1d_cache)
        compound_cands = [m for m in modules if m.startswith(part + "_") and m != exclude]
        if len(compound_cands) == 1:
            return compound_cands[0]
        if compound_cands:
            return max(compound_cands, key=lambda m: modules[m])
        if simple_cands:
            return max(simple_cands, key=lambda m: modules.get(m, 0))
        return None

    newly_bridged = []
    for prefix in list(modules):
        if "_" not in prefix:
            continue
        parts = prefix.split("_")
        for i in range(1, len(parts)):
            left_raw = "_".join(parts[:i])
            right_raw = "_".join(parts[i:])
            left = _fuzzy_resolve(left_raw, prefix)
            right = _fuzzy_resolve(right_raw, prefix)
            if left and right and left != right:
                bridges[prefix] = (left, right, modules[prefix])
                newly_bridged.append(prefix)
                break
    for prefix in newly_bridged:
        del modules[prefix]

    # Pass 3: cell-level tracing for remaining compound modules (e.g. *_bcast)
    # These are often broadcast buses that fan out from one module to many.
    remaining_compound = [p for p in modules if "_" in p]
    if remaining_compound:
        cells = top_mod.get("cells", {})
        netnames = top_mod.get("netnames", {})
        # bit → set of prefixes (only for known module prefixes)
        bit_prefix = defaultdict(set)
        for name, info in netnames.items():
            if name.startswith("$") or "." not in name:
                continue
            pfx = name.split(".")[0]
            for bit in info.get("bits", []):
                if isinstance(bit, int):
                    bit_prefix[bit].add(pfx)
        # For each remaining compound prefix, find which known modules it shares
        # cells with (cell-level connectivity).
        for prefix in remaining_compound:
            connected_mods = defaultdict(int)
            for cell_info in cells.values():
                cell_prefixes = set()
                for bits in cell_info.get("connections", {}).values():
                    for bit in bits:
                        if isinstance(bit, int):
                            cell_prefixes.update(bit_prefix.get(bit, set()))
                if prefix in cell_prefixes:
                    for other in cell_prefixes:
                        if other != prefix and other in modules and "_" not in other:
                            connected_mods[other] += 1
            if connected_mods:
                # Treat as broadcast: source is the best-matching module prefix,
                # destinations are all connected modules.
                parts = prefix.split("_")
                source = None
                for i in range(len(parts), 0, -1):
                    candidate = "_".join(parts[:i])
                    resolved = _fuzzy_resolve(candidate, prefix)
                    if resolved and resolved in modules:
                        source = resolved
                        break
                targets = sorted(connected_mods, key=lambda m: -connected_mods[m])
                sig_count = modules[prefix]
                for tgt in targets:
                    if tgt == source:
                        continue
                    bridges[f"{prefix}>{tgt}"] = (
                        source if source else targets[0],
                        tgt,
                        connected_mods[tgt],
                    )
                del modules[prefix]

    # Build recursive hierarchy tree from dot-separated net names
    # tree[mod] = {"count": N, "children": {child: {"count": M, "children": {…}}}}
    tree = {}
    for name in user_nets:
        parts = name.split(".")
        if len(parts) < 2:
            continue
        mod = parts[0]
        if mod not in modules:
            continue
        # Walk down the path, building tree nodes
        if mod not in tree:
            tree[mod] = {"count": modules[mod], "children": {}}
        node = tree[mod]
        for level in range(1, len(parts) - 1):  # exclude leaf signal name
            child = parts[level]
            if child not in node["children"]:
                node["children"][child] = {"count": 0, "children": {}}
            node["children"][child]["count"] += 1
            node = node["children"][child]

    return modules, bridges, tree


# Colors per nesting level
_LEVEL_COLORS = [
    ("gray40", "cornsilk", "lightyellow", 2, 14),       # level 1
    ("gray60", "lemonchiffon", "lightyellow", 1.5, 11),  # level 2
    ("gray70", "ivory", "floralwhite", 1, 10),           # level 3
    ("gray80", "ghostwhite", "lavender", 1, 9),          # level 4+
]


def _level_style(lvl):
    idx = min(lvl, len(_LEVEL_COLORS) - 1)
    return _LEVEL_COLORS[idx]


def _render_tree_node(lines, node_name, node, prefix_path, depth, current_level,
                      cluster_counter, indent):
    """Recursively render a hierarchy node as cluster or leaf box."""
    has_children = bool(node["children"]) and current_level < depth
    sig_count = node["count"]
    color, bgcolor, fillcolor, pw, fs = _level_style(current_level - 1)

    if has_children:
        cid = f"cluster_{next(cluster_counter)}"
        lines.append(f"{indent}subgraph {cid} {{")
        lines.append(f'{indent}  label="{node_name}\\n({sig_count} sigs)";')
        lines.append(f"{indent}  style=rounded; color={color}; penwidth={pw};")
        lines.append(f"{indent}  bgcolor={bgcolor};")
        lines.append(f'{indent}  fontname="Helvetica"; fontsize={fs};')

        for child_name in sorted(node["children"].keys()):
            child = node["children"][child_name]
            child_path = f"{prefix_path}.{child_name}"
            _render_tree_node(
                lines, child_name, child, child_path,
                depth, current_level + 1, cluster_counter, indent + "  "
            )

        lines.append(f"{indent}}}")
    else:
        node_id = prefix_path
        lines.append(
            f'{indent}"{node_id}" [label="{node_name}\\n({sig_count} sigs)",'
            f" shape=box, style=filled, fillcolor={fillcolor},"
            f" penwidth={pw}];"
        )


def _counter():
    """Simple counter generator for unique cluster IDs."""
    n = 0
    while True:
        yield n
        n += 1


def _common_prefix(names):
    """Find the longest common prefix of a list of strings."""
    if not names:
        return ""
    prefix = names[0]
    for name in names[1:]:
        while not name.startswith(prefix):
            prefix = prefix[:-1]
            if not prefix:
                return ""
    return prefix


def _trace_port_modules(top_mod, modules):
    """Trace port→module connections via shared cell net bits.

    Returns: dict  {port_name: {mod_prefix: count}} excluding global signals.
    """
    ports = top_mod.get("ports", {})
    cells = top_mod.get("cells", {})
    netnames = top_mod.get("netnames", {})

    # bit → user net prefixes
    bit_to_prefix = defaultdict(set)
    for name, info in netnames.items():
        if name.startswith("$") or "." not in name:
            continue
        prefix = name.split(".")[0]
        if prefix not in modules:
            continue
        for bit in info.get("bits", []):
            if isinstance(bit, int):
                bit_to_prefix[bit].add(prefix)

    # bit → port name
    bit_to_port = {}
    for pname, pinfo in ports.items():
        for bit in pinfo.get("bits", []):
            if isinstance(bit, int):
                bit_to_port[bit] = pname

    # Walk cells: if a cell touches both a port bit and a module net bit, link them
    port_mods = defaultdict(lambda: defaultdict(int))
    for cell_info in cells.values():
        cell_ports_hit = set()
        cell_mods_hit = set()
        for bits in cell_info.get("connections", {}).values():
            for bit in bits:
                if isinstance(bit, int):
                    if bit in bit_to_port:
                        cell_ports_hit.add(bit_to_port[bit])
                    cell_mods_hit.update(bit_to_prefix.get(bit, set()))
        for pn in cell_ports_hit:
            for mod in cell_mods_hit:
                port_mods[pn][mod] += 1

    # Filter out global signals (connected to many modules, e.g. clock/reset)
    threshold = len(modules) * 0.3
    result = {}
    for pn, mods in port_mods.items():
        if len(mods) > threshold:
            continue  # skip clock/reset-like globals
        result[pn] = dict(mods)
    return result


def _group_ports_by_module(port_mods, top_ports):
    """Group ports by their primary connected module for bus-level display.

    Returns: dict  {mod_name: {"in": [(port_name, width)], "out": [...]}}
    """
    groups = defaultdict(lambda: {"in": [], "out": []})
    for port_name, mods in port_mods.items():
        if not mods:
            continue
        primary_mod = max(mods, key=lambda m: mods[m])
        direction = top_ports[port_name].get("direction", "input")
        w = len(top_ports[port_name].get("bits", []))
        bucket = "in" if direction == "input" else "out"
        groups[primary_mod][bucket].append((port_name, w))
    return dict(groups)


def _compute_flow_ranks(modules, bridges):
    """Compute topological rank for each module to guide LR layout.

    Uses iterative relaxation on edge weights to find the best flow ordering.
    Returns: dict {mod_name: rank_int}
    """
    all_mods = set(modules.keys())

    # Collect non-broadcast directed edges with signal counts
    edges = []  # (src, dst, weight)
    for bname, (src, dst, cnt) in bridges.items():
        if ">" in bname or src not in all_mods or dst not in all_mods:
            continue
        edges.append((src, dst, cnt))

    if not edges:
        return {m: 0 for m in all_mods}

    # Use a spring-model: each forward edge wants dst_rank > src_rank,
    # weighted by signal count. Find ranks that minimize back-edge weight.
    # Try all possible root modules and pick the ordering with most forward weight.
    best_ranks = None
    best_fwd_weight = -1

    # Find candidate roots: modules with few or no incoming edges
    in_weight = defaultdict(int)
    out_weight = defaultdict(int)
    for s, d, w in edges:
        in_weight[d] += w
        out_weight[s] += w
    # Candidates are modules where out_weight > in_weight (net sources)
    candidates = sorted(all_mods, key=lambda m: out_weight[m] - in_weight[m], reverse=True)[:5]

    for root in candidates:
        # BFS from root, assign increasing ranks
        rank = {root: 0}
        queue = [root]
        visited = {root}
        adj = defaultdict(list)
        for s, d, w in edges:
            adj[s].append((d, w))
            adj[d].append((s, w))  # bidirectional for reachability

        while queue:
            cur = queue.pop(0)
            for nxt, w in adj[cur]:
                if nxt in visited:
                    continue
                # Check if cur→nxt is a forward edge
                is_fwd = any(s == cur and d == nxt for s, d, _ in edges)
                if is_fwd:
                    rank[nxt] = rank[cur] + 1
                else:
                    rank[nxt] = rank[cur] - 1
                visited.add(nxt)
                queue.append(nxt)

        # Assign unreachable modules
        if rank:
            mid = (max(rank.values()) + min(rank.values())) // 2
        else:
            mid = 0
        for m in all_mods:
            if m not in rank:
                rank[m] = mid

        # Score: sum of weights for forward edges (dst_rank > src_rank)
        fwd_weight = sum(w for s, d, w in edges if rank.get(d, 0) > rank.get(s, 0))
        if fwd_weight > best_fwd_weight:
            best_fwd_weight = fwd_weight
            best_ranks = dict(rank)

    # Normalize ranks to start from 0
    if best_ranks:
        min_r = min(best_ranks.values())
        return {m: r - min_r for m, r in best_ranks.items()}
    return {m: 0 for m in all_mods}


def generate_dot_from_nets(top_name, top_mod, depth):
    """Generate arch diagram from net name hierarchy (for flat designs)."""
    top_ports = top_mod.get("ports", {})
    modules, bridges, tree = extract_hierarchy_from_nets(top_mod)

    lines = []
    lines.append(f'digraph "{top_name}" {{')
    lines.append("  rankdir=LR;")
    lines.append("  compound=true;")
    lines.append("  splines=spline;")
    lines.append('  labelloc="t";')
    lines.append(f'  label="{top_name} (depth={depth})";')
    lines.append('  fontsize=20; fontname="Helvetica";')
    lines.append('  node [fontname="Helvetica", fontsize=12, margin="0.2,0.1"];')
    lines.append('  edge [fontname="Helvetica", fontsize=9, color=gray40];')
    lines.append("  nodesep=0.5; ranksep=1.2;")
    lines.append("")

    # Trace actual port→module connections via cells
    port_mods = _trace_port_modules(top_mod, modules)
    port_groups = _group_ports_by_module(port_mods, top_ports)

    # Render grouped port bus nodes (one per module connection, not per signal)
    for mod_name, grp in sorted(port_groups.items()):
        for direction, bucket in [("in", grp["in"]), ("out", grp["out"])]:
            if not bucket:
                continue
            total_w = sum(w for _, w in bucket)
            # Find common prefix for label
            names = [p for p, _ in bucket]
            prefix = _common_prefix(names)
            if len(bucket) == 1:
                p, w = bucket[0]
                label = f"{p} [{w-1}:0]" if w > 1 else p
            else:
                label = f"{prefix}* ({len(bucket)} ports, {total_w} bits)"
            node_id = f"__BUS__{mod_name}_{direction}"
            fillcolor = "lightblue" if direction == "in" else "lightsalmon"
            shape = "cds"
            lines.append(
                f'  "{node_id}" [label="{label}", shape={shape},'
                f" style=filled, fillcolor={fillcolor}];"
            )

    lines.append("")

    # Module nodes (recursive)
    cluster_counter = _counter()
    for mod_name in sorted(tree.keys()):
        node = tree[mod_name]
        _render_tree_node(
            lines, mod_name, node, mod_name,
            depth, 1, cluster_counter, "  "
        )
    # Modules without children in tree (no sub-hierarchy)
    for mod_name in sorted(modules.keys()):
        if mod_name not in tree:
            sig_count = modules[mod_name]
            lines.append(
                f'  "{mod_name}" [label="{mod_name}\\n({sig_count} signals)",'
                ' shape=box, style="filled,rounded", fillcolor=lightyellow,'
                " penwidth=2];"
            )

    lines.append("")

    # Helper to find leaf node for edge targeting
    def _first_leaf(mod_name):
        """Find the first leaf node ID inside a module's tree for edge targeting."""
        if mod_name not in tree:
            return mod_name
        node = tree[mod_name]
        path = mod_name
        cur_depth = 1
        while node["children"] and cur_depth < depth:
            first_child = sorted(node["children"].keys())[0]
            path = f"{path}.{first_child}"
            node = node["children"][first_child]
            cur_depth += 1
        return path

    # Compute flow ranks for edge weight/constraint decisions
    flow_ranks = _compute_flow_ranks(modules, bridges)

    # Add invisible edges between adjacent ranks to enforce flow ordering.
    # This gives Graphviz strong hints without conflicting with clusters.
    rank_groups = defaultdict(list)
    for mod_name, r in flow_ranks.items():
        rank_groups[r].append(mod_name)
    sorted_ranks = sorted(rank_groups.keys())
    for i in range(len(sorted_ranks) - 1):
        r_cur = sorted_ranks[i]
        r_nxt = sorted_ranks[i + 1]
        # Pick one representative from each rank to create a spine
        src_rep = _first_leaf(sorted(rank_groups[r_cur])[0])
        dst_rep = _first_leaf(sorted(rank_groups[r_nxt])[0])
        lines.append(
            f'  "{src_rep}" -> "{dst_rep}"'
            f" [style=invis, weight=10];"
        )
    lines.append("")

    # Edges from bridge signals
    for bridge_name, (src, dst, count) in sorted(bridges.items()):
        src_node = _first_leaf(src)
        dst_node = _first_leaf(dst)

        is_broadcast = ">" in bridge_name
        # Determine if this edge goes forward or backward in the pipeline
        src_rank = flow_ranks.get(src, 0)
        dst_rank = flow_ranks.get(dst, 0)
        is_back_edge = dst_rank <= src_rank and not is_broadcast

        if is_broadcast:
            bus_name = bridge_name.split(">")[0]
            label = f"{bus_name}\\n({count} sigs)"
            lines.append(
                f'  "{src_node}" -> "{dst_node}"'
                f' [label="{label}", penwidth=1.5, style=dashed,'
                f" color=coral3, weight=1, constraint=false];"
            )
        else:
            label = f"{bridge_name}\\n({count} sigs)"
            if is_back_edge:
                lines.append(
                    f'  "{src_node}" -> "{dst_node}"'
                    f' [label="{label}", penwidth=2, color=steelblue,'
                    f" weight=1, constraint=false, style=dashed];"
                )
            else:
                lines.append(
                    f'  "{src_node}" -> "{dst_node}"'
                    f' [label="{label}", penwidth=2, color=steelblue, weight=5];'
                )

    # Port bus edges (from traced connections)
    for mod_name, grp in sorted(port_groups.items()):
        mod_node = _first_leaf(mod_name)
        if grp["in"]:
            node_id = f"__BUS__{mod_name}_in"
            lines.append(
                f'  "{node_id}" -> "{mod_node}" [style=dashed, color=gray60, penwidth=1.5];'
            )
        if grp["out"]:
            node_id = f"__BUS__{mod_name}_out"
            lines.append(
                f'  "{mod_node}" -> "{node_id}" [style=dashed, color=gray60, penwidth=1.5];'
            )

    lines.append("}")
    return "\n".join(lines)


def generate_dot_from_modules(top_name, top_mod, modules, depth):
    """Generate arch diagram from multi-module JSON (non-flat designs)."""
    design_modules = set(modules.keys())
    lines = []
    lines.append(f'digraph "{top_name}" {{')
    lines.append("  rankdir=LR;")
    lines.append("  compound=true;")
    lines.append('  labelloc="t";')
    lines.append(f'  label="{top_name} (depth={depth})";')
    lines.append('  fontsize=20; fontname="Helvetica";')
    lines.append('  node [fontname="Helvetica", fontsize=12];')
    lines.append('  edge [fontname="Helvetica", fontsize=9];')
    lines.append("")

    top_ports = top_mod.get("ports", {})
    in_ports = {p: i for p, i in top_ports.items() if i.get("direction") == "input"}
    out_ports = {p: i for p, i in top_ports.items() if i.get("direction") == "output"}

    if in_ports:
        lines.append("  subgraph cluster_inputs {")
        lines.append('    label="Inputs"; style=dashed; color=gray60;')
        for p, info in in_ports.items():
            w = len(info.get("bits", []))
            label = f"{p} [{w-1}:0]" if w > 1 else p
            lines.append(
                f'    "__PORT__{p}" [label="{label}", shape=cds,'
                " style=filled, fillcolor=lightblue];"
            )
        lines.append("  }")
    if out_ports:
        lines.append("  subgraph cluster_outputs {")
        lines.append('    label="Outputs"; style=dashed; color=gray60;')
        for p, info in out_ports.items():
            w = len(info.get("bits", []))
            label = f"{p} [{w-1}:0]" if w > 1 else p
            lines.append(
                f'    "__PORT__{p}" [label="{label}", shape=cds,'
                " style=filled, fillcolor=lightsalmon];"
            )
        lines.append("  }")
    lines.append("")

    # Sub-module instances
    top_cells = top_mod.get("cells", {})
    cluster_idx = 0
    for cell_name, cell in top_cells.items():
        cell_type = cell.get("type", "")
        if cell_type not in design_modules:
            continue
        child_mod = modules.get(cell_type, {})
        child_cells = [
            (cn, c.get("type", ""))
            for cn, c in child_mod.get("cells", {}).items()
            if c.get("type", "") in design_modules
        ]

        if child_cells and depth >= 2:
            lines.append(f"  subgraph cluster_{cluster_idx} {{")
            lines.append(f'    label="{sanitize(cell_name)}\\n({cell_type})";')
            lines.append("    style=rounded; color=gray40; penwidth=2;")
            lines.append("    bgcolor=cornsilk;")
            lines.append('    fontname="Helvetica"; fontsize=14;')
            for cn, ct in child_cells:
                nid = f"{cell_name}/{cn}"
                lines.append(
                    f'    "{nid}" [label="{{{sanitize(cn)}|{ct}}}",'
                    " shape=record, style=filled, fillcolor=lightyellow,"
                    " penwidth=1.5];"
                )
            lines.append("  }")
            cluster_idx += 1
        else:
            lines.append(
                f'  "{cell_name}" [label="{{{sanitize(cell_name)}|{cell_type}}}",'
                " shape=record, style=filled, fillcolor=lightyellow,"
                " penwidth=1.5];"
            )

    lines.append("")

    # Build net-based connections at level 1
    net_to_pins = defaultdict(list)
    for port_name, port_info in top_ports.items():
        direction = port_info.get("direction", "input")
        for bit in port_info.get("bits", []):
            if isinstance(bit, int):
                net_to_pins[bit].append((f"__PORT__{port_name}", port_name, direction))
    for cell_name, cell in top_cells.items():
        if cell.get("type", "") not in design_modules:
            continue
        port_dirs = cell.get("port_directions", {})
        for port, bits in cell.get("connections", {}).items():
            direction = port_dirs.get(port, "input")
            for bit in bits:
                if isinstance(bit, int):
                    net_to_pins[bit].append((cell_name, port, direction))

    connections = defaultdict(set)
    for _, pins in net_to_pins.items():
        if len(pins) < 2:
            continue
        sources = [(c, p) for c, p, d in pins if d in ("output", "inout")]
        sinks = [(c, p) for c, p, d in pins if d in ("input", "inout")]
        for src, _ in sources:
            for dst, dp in sinks:
                if src != dst:
                    connections[(src, dst)].add(dp)

    for (src, dst), sigs in connections.items():
        names = sorted(set(sigs))
        label = f"{len(names)} signals" if len(names) > 4 else "\\n".join(names)
        lines.append(f'  "{src}" -> "{dst}" [label="{label}"];')

    lines.append("}")
    return "\n".join(lines)


def main():
    parser = ArgumentParser(
        description="Generate module-level architecture diagram from yosys JSON"
    )
    parser.add_argument("json_file", help="Input JSON file from yosys write_json")
    parser.add_argument(
        "-o",
        "--output",
        default=None,
        help="Output dot file (default: <json_file>_arch.dot)",
    )
    parser.add_argument(
        "-d",
        "--depth",
        type=int,
        default=3,
        choices=range(1, 9),
        help="Hierarchy depth to display (1-8, default: 3)",
    )
    parser.add_argument(
        "-t",
        "--top",
        default=None,
        help="Top module name (auto-detected if not given)",
    )
    args = parser.parse_args()

    with open(args.json_file, "r") as f:
        data = json.load(f)

    modules = data.get("modules", {})
    if not modules:
        print("Error: No modules found in JSON")
        return

    top_name, top_mod = find_top_module(modules, args.top)
    design_modules = set(modules.keys())

    # Check if sub-module instances exist in top cells
    has_submod = any(
        c.get("type", "") in design_modules for c in top_mod.get("cells", {}).values()
    )

    print(f"Top module: {top_name}")
    print(f"Design modules in JSON: {len(design_modules)}")

    if has_submod and len(design_modules) > 1:
        print("Mode: multi-module (hierarchy from JSON structure)")
        dot_content = generate_dot_from_modules(top_name, top_mod, modules, args.depth)
    else:
        print("Mode: flat design (hierarchy reconstructed from net names)")
        dot_content = generate_dot_from_nets(top_name, top_mod, args.depth)

    output_path = args.output or args.json_file.replace(".json", "_arch.dot")
    with open(output_path, "w") as f:
        f.write(dot_content)
    print(f"Architecture diagram written to: {output_path}")


if __name__ == "__main__":
    main()
