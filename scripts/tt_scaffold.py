#!/usr/bin/env python3
"""Generate a TinyTapeout project scaffold from Makefile design variables."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import shlex
from pathlib import Path
from dataclasses import dataclass


@dataclass(frozen=True)
class Port:
    name: str
    direction: str
    width: int


def yaml_string(value: str) -> str:
    return json.dumps(value)


def parse_file_list(value: str) -> list[Path]:
    return [Path(item).expanduser() for item in shlex.split(value)]


def unique_dest_name(path: Path, used: set[str], index: int) -> str:
    name = path.name
    if name not in used:
        used.add(name)
        return name

    stem = path.stem or "source"
    suffix = path.suffix
    name = f"rtl_{index:02d}_{stem}{suffix}"
    while name in used:
        index += 1
        name = f"rtl_{index:02d}_{stem}{suffix}"
    used.add(name)
    return name


def copy_source(src: Path, dst: Path) -> None:
    if not src.exists():
        raise FileNotFoundError(f"source file not found: {src}")
    if src.resolve() == dst.resolve():
        return
    shutil.copyfile(src, dst)


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    return re.sub(r"//.*", "", text)


def split_top_level_commas(text: str) -> list[str]:
    parts: list[str] = []
    start = 0
    depth = 0
    for index, char in enumerate(text):
        if char in "([{":
            depth += 1
        elif char in ")]}" and depth > 0:
            depth -= 1
        elif char == "," and depth == 0:
            parts.append(text[start:index].strip())
            start = index + 1
    tail = text[start:].strip()
    if tail:
        parts.append(tail)
    return parts


def find_matching_paren(text: str, open_index: int) -> int:
    depth = 0
    for index in range(open_index, len(text)):
        char = text[index]
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return index
    raise ValueError("unterminated module port list")


def find_module_sections(text: str, module_name: str) -> tuple[str, str]:
    clean = strip_comments(text)
    match = re.search(rf"\bmodule\s+{re.escape(module_name)}\b", clean)
    if not match:
        raise ValueError(f"module {module_name} not found")

    cursor = match.end()
    while cursor < len(clean) and clean[cursor].isspace():
        cursor += 1
    if cursor < len(clean) and clean[cursor] == "#":
        cursor += 1
        while cursor < len(clean) and clean[cursor].isspace():
            cursor += 1
        if cursor >= len(clean) or clean[cursor] != "(":
            raise ValueError(f"unsupported parameter list for module {module_name}")
        cursor = find_matching_paren(clean, cursor) + 1
        while cursor < len(clean) and clean[cursor].isspace():
            cursor += 1

    if cursor >= len(clean) or clean[cursor] != "(":
        raise ValueError(f"module {module_name} has no explicit port list")
    ports_end = find_matching_paren(clean, cursor)
    port_list = clean[cursor + 1:ports_end]

    header_end = clean.find(";", ports_end)
    if header_end < 0:
        raise ValueError(f"module {module_name} header has no semicolon")
    body_end_match = re.search(r"\bendmodule\b", clean[header_end + 1:])
    if not body_end_match:
        raise ValueError(f"module {module_name} has no endmodule")
    body_end = header_end + 1 + body_end_match.start()
    return port_list, clean[header_end + 1:body_end]


def parse_width(text: str) -> int:
    match = re.search(r"\[\s*(-?\d+)\s*:\s*(-?\d+)\s*\]", text)
    if not match:
        return 1
    left = int(match.group(1))
    right = int(match.group(2))
    return abs(left - right) + 1


def parse_names(text: str) -> list[str]:
    text = re.sub(r"\[[^\]]+\]", " ", text)
    text = re.sub(r"\b(?:wire|reg|logic|signed|unsigned|tri|supply0|supply1)\b", " ", text)
    names: list[str] = []
    for item in split_top_level_commas(text):
        item = item.split("=", 1)[0].strip()
        match = re.search(r"(\\\S+|[A-Za-z_$][A-Za-z0-9_$]*)\s*$", item)
        if match:
            names.append(match.group(1))
    return names


def parse_port_decl(direction: str, text: str) -> list[Port]:
    width = parse_width(text)
    return [Port(name=name, direction=direction, width=width) for name in parse_names(text)]


def extract_module_ports(module_name: str, rtl_files: list[Path]) -> list[Port]:
    found_module = False
    for rtl_file in rtl_files:
        text = rtl_file.read_text(errors="replace")
        try:
            port_list, body = find_module_sections(text, module_name)
        except ValueError:
            continue
        found_module = True

        ports_by_name: dict[str, Port] = {}
        header_order: list[str] = []
        for item in split_top_level_commas(port_list):
            item = item.strip()
            if not item:
                continue
            direction_match = re.match(r"\b(input|output|inout)\b(.*)", item, flags=re.DOTALL)
            if direction_match:
                for port in parse_port_decl(direction_match.group(1), direction_match.group(2)):
                    ports_by_name[port.name] = port
                    header_order.append(port.name)
            else:
                name_match = re.search(r"(\\\S+|[A-Za-z_$][A-Za-z0-9_$]*)\s*$", item)
                if name_match:
                    header_order.append(name_match.group(1))

        for direction, decl_text in re.findall(r"\b(input|output|inout)\b([^;]*);", body, flags=re.DOTALL):
            for port in parse_port_decl(direction, decl_text):
                ports_by_name[port.name] = port

        ports: list[Port] = []
        for name in header_order:
            port = ports_by_name.get(name)
            if port is not None and port not in ports:
                ports.append(port)
        if ports:
            return ports

    if found_module:
        raise ValueError(f"module {module_name} has no parseable ports")
    raise ValueError(f"module {module_name} not found in RTL files")


def verilog_range(width: int) -> str:
    return "" if width == 1 else f"[{width - 1}:0] "


def sanitize_identifier(name: str) -> str:
    clean = re.sub(r"[^A-Za-z0-9_$]", "_", name.strip("\\"))
    if not re.match(r"[A-Za-z_]", clean):
        clean = f"p_{clean}"
    return clean


def is_clock_port(name: str) -> bool:
    lower = name.lower().strip("\\")
    return lower in {"clk", "clock", "clk_i", "clock_i"}


def reset_expression(name: str) -> str | None:
    lower = name.lower().strip("\\")
    if lower in {"rst_n", "reset_n", "resetn", "rst_ni", "reset_ni"}:
        return "rst_n"
    if lower in {"rst", "reset", "rst_i", "reset_i"}:
        return "~rst_n"
    return None


def generate_driver_assignments(signal_name: str, width: int) -> list[str]:
    if width == 1:
        return [f"  wire {signal_name};", f"  assign {signal_name} = tt_eval_input_bus[0];"]
    lines = [f"  wire [{width - 1}:0] {signal_name};"]
    for bit in range(width):
        lines.append(f"  assign {signal_name}[{bit}] = tt_eval_input_bus[{bit % 17}];")
    return lines


def generate_fold_assignments(output_name: str, output_bits: int, offset: int) -> list[str]:
    lines: list[str] = []
    for bit in range(8):
        indices = list(range((bit + offset) % 8, output_bits, 8))
        terms = [f"tt_eval_output_bus[{index}]" for index in indices]
        expr = " ^ ".join(terms) if terms else "1'b0"
        lines.append(f"  assign {output_name}[{bit}] = {expr};")
    return lines


def generate_auto_wrapper(top: str, design: str, ports: list[Port]) -> str:
    if top == design:
        raise ValueError("auto-wrapper top must differ from design; use TT_NATIVE=1 for native TT tops")

    input_driver_lines: list[str] = []
    output_wires: list[str] = []
    inout_wires: list[str] = []
    connections: list[str] = []
    output_terms: list[str] = []

    for port in ports:
        safe_name = sanitize_identifier(port.name)
        if port.direction == "input":
            if is_clock_port(port.name):
                expr = "clk"
            else:
                expr = reset_expression(port.name)
            if expr is None:
                driver_name = f"tt_eval_{safe_name}"
                input_driver_lines.extend(generate_driver_assignments(driver_name, port.width))
                expr = driver_name
            connections.append(f"      .{port.name}({expr})")
        elif port.direction == "output":
            wire_name = f"tt_eval_{safe_name}"
            output_wires.append(f"  wire {verilog_range(port.width)}{wire_name};")
            output_terms.append(wire_name)
            connections.append(f"      .{port.name}({wire_name})")
        else:
            wire_name = f"tt_eval_{safe_name}"
            inout_wires.extend(generate_driver_assignments(wire_name, port.width))
            connections.append(f"      .{port.name}({wire_name})")

    output_width = sum(port.width for port in ports if port.direction == "output")
    if output_terms:
        output_bus = "{" + ", ".join(reversed(output_terms)) + "}"
        output_bus_decl = f"  wire [{output_width - 1}:0] tt_eval_output_bus = {output_bus};"
    else:
        output_width = 1
        output_bus_decl = "  wire [0:0] tt_eval_output_bus = 1'b0;"

    joined_connections = ",\n".join(connections)
    lines = [
        "`default_nettype none",
        "",
        "// AUTO-GENERATED EVALUATION WRAPPER.",
        "// This is for scaffold/link/PPA checks only; it is not a protocol-correct",
        "// product wrapper. Use TT_WRAPPER_FILE or TT_NATIVE=1 for functional IO.",
        "",
        f"module {top} (",
        "    input  wire [7:0] ui_in,",
        "    output wire [7:0] uo_out,",
        "    input  wire [7:0] uio_in,",
        "    output wire [7:0] uio_out,",
        "    output wire [7:0] uio_oe,",
        "    input  wire       ena,",
        "    input  wire       clk,",
        "    input  wire       rst_n",
        ");",
        "",
        "  wire [16:0] tt_eval_input_bus = {ena, uio_in, ui_in};",
        "",
    ]
    lines.extend(input_driver_lines)
    if input_driver_lines:
        lines.append("")
    lines.extend(inout_wires)
    if inout_wires:
        lines.append("")
    lines.extend(output_wires)
    if output_wires:
        lines.append("")
    lines.extend([
        f"  {design} user_design (",
        joined_connections,
        "  );",
        "",
        output_bus_decl,
        "",
    ])
    lines.extend(generate_fold_assignments("uo_out", output_width, 0))
    lines.append("")
    lines.extend(generate_fold_assignments("uio_out", output_width, 4))
    lines.extend([
        "  assign uio_oe = 8'h00;",
        "",
        "endmodule",
        "",
        "`default_nettype wire",
    ])
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate TinyTapeout scaffold files")
    parser.add_argument("--project-dir", required=True, type=Path)
    parser.add_argument("--design", required=True)
    parser.add_argument("--top", required=True)
    parser.add_argument("--rtl-files", required=True)
    parser.add_argument("--clock-hz", required=True, type=int)
    parser.add_argument("--title", required=True)
    parser.add_argument("--author", required=True)
    parser.add_argument("--description", required=True)
    parser.add_argument("--language", default="Verilog")
    parser.add_argument("--tiles", default="1x1")
    parser.add_argument("--wrapper-file", type=Path)
    parser.add_argument("--native", action="store_true")
    parser.add_argument("--auto-wrapper", action="store_true")
    args = parser.parse_args()

    project_dir = args.project_dir
    src_dir = project_dir / "src"
    rtl_files = parse_file_list(args.rtl_files)

    if not args.native and args.wrapper_file is None and not args.auto_wrapper:
        raise SystemExit(
            "non-native TinyTapeout projects need --wrapper-file; "
            "set TT_NATIVE=1 if DESIGN already has the TinyTapeout interface, "
            "or set TT_AUTO_WRAP=1 for an evaluation wrapper"
        )

    if src_dir.exists():
        shutil.rmtree(src_dir)
    src_dir.mkdir(parents=True, exist_ok=True)

    source_files: list[str] = []
    used_names: set[str] = set()

    if args.wrapper_file is not None:
        wrapper_src = args.wrapper_file.expanduser()
        wrapper_name = unique_dest_name(wrapper_src, used_names, 0)
        copy_source(wrapper_src, src_dir / wrapper_name)
        source_files.append(wrapper_name)
    elif args.auto_wrapper:
        ports = extract_module_ports(args.design, rtl_files)
        wrapper_name = unique_dest_name(Path(f"{args.top}.v"), used_names, 0)
        (src_dir / wrapper_name).write_text(generate_auto_wrapper(args.top, args.design, ports))
        source_files.append(wrapper_name)

    for index, rtl_file in enumerate(rtl_files, start=1):
        rtl_name = unique_dest_name(rtl_file, used_names, index)
        copy_source(rtl_file, src_dir / rtl_name)
        source_files.append(rtl_name)

    info_yaml = [
        "project:",
        f"  title: {yaml_string(args.title)}",
        f"  author: {yaml_string(args.author)}",
        f"  description: {yaml_string(args.description)}",
        f"  language: {yaml_string(args.language)}",
        f"  clock_hz: {args.clock_hz}",
        f"  tiles: {yaml_string(args.tiles)}",
        f"  top_module: {yaml_string(args.top)}",
        "  source_files:",
    ]
    info_yaml.extend(f"    - {yaml_string(source_file)}" for source_file in source_files)
    (project_dir / "info.yaml").write_text("\n".join(info_yaml) + "\n")

    rtl_file_list = " ".join(str(src_dir / source_file) for source_file in source_files)
    (project_dir / "rtl_files.mk").write_text(f"TT_GENERATED_RTL_FILES := {rtl_file_list}\n")

    print(f"TinyTapeout scaffold generated: {project_dir}")
    print(f"Top module: {args.top}")
    print("Source files:")
    for source_file in source_files:
        print(f"  - src/{source_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())