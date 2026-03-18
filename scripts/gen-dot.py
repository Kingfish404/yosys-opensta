import os
import subprocess
import shutil
from argparse import ArgumentParser

# File size threshold (bytes) for switching to fast layout engine
LARGE_FILE_THRESHOLD = 256 * 1024  # 256KB


def split_dot(file_path):
    """Split a dot file containing multiple digraphs into separate files."""
    print(f"Reading {file_path}")
    dot_files = []
    with open(file_path, "r") as f:
        subgraph = []
        subgraph_count = 0
        subdigraph_name = ""
        for line in f:
            if line.startswith("digraph"):
                if subgraph:
                    out = f"{file_path}_{subgraph_count}_{subdigraph_name}.dot"
                    print(f"Writing digraph {subgraph_count}, {subdigraph_name}")
                    with open(out, "w") as wf:
                        wf.write("".join(subgraph))
                    dot_files.append(out)
                    subgraph_count += 1
                    subgraph = []
                subdigraph_name = line.split()[1].strip('"')
            subgraph.append(line)
        if subgraph:
            out = f"{file_path}_{subgraph_count}_{subdigraph_name}.dot"
            print(f"Writing digraph {subgraph_count}, {subdigraph_name}")
            with open(out, "w") as wf:
                wf.write("".join(subgraph))
            dot_files.append(out)
    return dot_files


def pick_engine(dot_file, engine):
    """Pick layout engine: use user's choice, or auto-select based on file size."""
    if engine != "auto":
        return engine
    size = os.path.getsize(dot_file)
    if size > LARGE_FILE_THRESHOLD:
        print(f"  Large file ({size // 1024}KB), using 'sfdp' engine for speed")
        return "sfdp"
    return "dot"


def convert_dot(dot_files, fmt="svg", engine="auto"):
    """Convert dot files using Graphviz. Auto-selects fast engine for large files."""
    # Check for any graphviz engine
    for cmd_name in ("dot", "sfdp", "fdp", "neato"):
        if shutil.which(cmd_name):
            break
    else:
        print("Warning: Graphviz not found. Skipping conversion.")
        print(
            "  Install with: brew install graphviz (macOS) or apt install graphviz (Linux)"
        )
        return []

    output_files = []
    for dot_file in dot_files:
        eng = pick_engine(dot_file, engine)
        eng_cmd = shutil.which(eng)
        if not eng_cmd:
            print(f"  Engine '{eng}' not found, falling back to 'dot'")
            eng_cmd = shutil.which("dot")
        out_file = dot_file.replace(".dot", f".{fmt}")
        print(f"Generating {out_file} (engine={eng})")
        subprocess.run(
            [eng_cmd, f"-T{fmt}", dot_file, "-o", out_file],
            check=True,
        )
        output_files.append(out_file)
    return output_files


def main():
    parser = ArgumentParser(
        description="Split yosys dot output and convert to SVG/PDF/PNG"
    )
    parser.add_argument("dot_file", help="Input dot file")
    parser.add_argument(
        "-f",
        "--format",
        default="svg",
        choices=["svg", "pdf", "png"],
        help="Output format (default: svg)",
    )
    parser.add_argument(
        "-e",
        "--engine",
        default="auto",
        choices=["auto", "dot", "sfdp", "fdp", "neato"],
        help="Graphviz layout engine (default: auto — uses 'sfdp' for large files, 'dot' otherwise)",
    )
    parser.add_argument(
        "--no-convert",
        action="store_true",
        help="Only split dot files, skip conversion",
    )
    args = parser.parse_args()

    dot_files = split_dot(args.dot_file)

    if not args.no_convert:
        output_files = convert_dot(dot_files, fmt=args.format, engine=args.engine)
        if output_files:
            print(f"\nGenerated {len(output_files)} {args.format.upper()} file(s):")
            for f in output_files:
                print(f"  {f}")


if __name__ == "__main__":
    main()
