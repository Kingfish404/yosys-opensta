# yosys-opensta

Use open-source EDA tools for ASIC synthesis ([YosysHQ/yosys](https://github.com/YosysHQ/yosys)), timing analysis ([parallaxsw/OpenSTA](https://github.com/parallaxsw/OpenSTA)), and physical design ([The-OpenROAD-Project/OpenROAD](https://github.com/The-OpenROAD-Project/OpenROAD)), providing a complete RTL-to-layout flow.

Inspired by [OSCPU/yosys-sta](https://github.com/OSCPU/yosys-sta).

## Dependency and Environment

Install [YosysHQ/yosys](https://github.com/YosysHQ/yosys) first, then choose **one** of the following setup methods:

### Option A: Local build (no Docker)

`make init_local` will download and build CUDD, NANGATE45, OpenSTA, OpenROAD, and yosys-slang in one step:

```shell
apt install -y yosys  # or: brew install yosys
make init_local
```

> **Note**: Building OpenROAD from source requires many dependencies (cmake, boost, swig, tcl, etc.).
> See [OpenROAD build instructions](https://github.com/The-OpenROAD-Project/OpenROAD/blob/master/docs/user/Build.md) for full dependency list.
> On Ubuntu: `sudo ./OpenROAD/etc/DependencyInstaller.sh`

### Option B: Docker-based

```shell
apt install -y yosys docker  # or: brew install yosys docker
make init_opensta  # clone OpenSTA and build Docker image
make init          # download NANGATE45

# install yosys-slang manually
git clone --recursive https://github.com/povik/yosys-slang
cd yosys-slang && make -j$(nproc) && make install
```

For PnR via Docker, also set up OpenROAD:
```shell
# Option 1: Pull pre-built image (recommended)
docker pull openroad/openroad:latest
docker tag openroad/openroad:latest openroad
# or build using dockerfile (takes much longer)
make init_openroad_docker

# Option 2: Build from source
make init_openroad
```

## Usage Example

```shell
# run sta (Docker) and show result with default gcd.v
make sta show

# run sta locally (no Docker) and show result
make sta_local show

# run sta with custom frequency with default gcd.v
make sta CLK_FREQ_MHZ=100

# run with custom design
make sta DESIGN=top_of_design RTL_FILES="/path/to/top.v /path/to/perip.v ..." VERILOG_INCLUDE_DIRS="/path/to/top.vh" CLK_FREQ_MHZ=100

# support system verilog
make sta DESIGN=top_of_design RTL_FILES="/path/to/top.sv /path/to/perip.sv ..." VERILOG_INCLUDE_DIRS="/path/to/top.svh" CLK_FREQ_MHZ=500

# detailed timing report (Docker / local)
make sta_detail
make sta_detail_local

# generate dot diagrams (default svg, or specify format)
make dot
make dot DOT_FORMAT=svg

# or see the example `Makefile` in the `benchmark/`
```

Hint: Don't forget to remove the `DPI-C` and `$` macro related code in the system verilog file.

## Physical Design (Place & Route)

After synthesis and STA, run OpenROAD for floorplanning, placement, CTS, and routing:

```shell
# Full flow: synthesis → STA → PnR (local)
make flow_local

# Or run PnR separately (after syn + sta_local)
make pnr_local

# PnR via Docker
make pnr

# Tunable parameters
make pnr_local CORE_UTILIZATION=50 PLACE_DENSITY=0.70

# Clean PnR results only (keep synthesis/STA)
make clean_pnr
```

**Tunable PnR parameters:**

| Parameter           | Default | Description               |
| ------------------- | ------- | ------------------------- |
| `CORE_UTILIZATION`  | 40      | Core area utilization (%) |
| `CORE_ASPECT_RATIO` | 1.0     | Floorplan aspect ratio    |
| `PLACE_DENSITY`     | 0.60    | Global placement density  |
| `MIN_ROUTING_LAYER` | metal2  | Bottom routing layer      |
| `MAX_ROUTING_LAYER` | metal7  | Top routing layer         |

**Output files** (in `result/<DESIGN>-<FREQ>MHz/pnr/`):

| File                   | Description               |
| ---------------------- | ------------------------- |
| `<DESIGN>_final.def`   | Final layout (DEF format) |
| `<DESIGN>_final.odb`   | OpenROAD database         |
| `<DESIGN>_final.v`     | Post-layout netlist       |
| `timing_max_final.rpt` | Setup timing report       |
| `timing_min_final.rpt` | Hold timing report        |
| `power_final.rpt`      | Power report              |
| `clock_skew_final.rpt` | Clock tree skew           |

## Layout Visualization

Generate chip layout images (like those on [theopenroadproject.org](https://theopenroadproject.org/)):

```shell
# Via OpenROAD (headless, requires xvfb-run on Linux)
make viz_layout

# Via KLayout (batch mode, no X11 needed)
make viz_layout_klayout

# Interactive GUI
make gui            # OpenROAD GUI
make gui_klayout    # KLayout GUI
```

Generated images (in `result/<DESIGN>-<FREQ>MHz/images/`):

| Image | Description |
|-------|-------------|
| `<DESIGN>_chip_full.png` | Complete chip layout (all layers) |
| `<DESIGN>_chip_placement.png` | Cell placement view |
| `<DESIGN>_chip_routing.png` | Routing layers only |
| `<DESIGN>_chip_power.png` | Power distribution network |
| `<DESIGN>_chip_clock.png` | Clock tree network |
| `<DESIGN>_<stage>_full.png` | Per-stage snapshots (floorplan → placed → cts → routed → final) |

## Documentation

See the source code or [OSCPU/yosys-sta](https://github.com/OSCPU/yosys-sta).

## Benchmark

See the [benchmark](benchmark) directory. And the [third_party IP cores](benchmark/third_party/README.md).

## Reference & Acknowledgement
- [OSCPU/yosys-sta](https://github.com/OSCPU/yosys-sta)
- [YosysHQ/yosys: Yosys Open SYnthesis Suite](https://github.com/YosysHQ/yosys)
- [parallaxsw/OpenSTA](https://github.com/parallaxsw/OpenSTA)
- [The-OpenROAD-Project/OpenROAD](https://github.com/The-OpenROAD-Project/OpenROAD)
