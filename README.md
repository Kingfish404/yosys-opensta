# yosys-opensta

Use open-source EDA tools for ASIC synthesis ([YosysHQ/yosys](https://github.com/YosysHQ/yosys)), timing analysis ([parallaxsw/OpenSTA](https://github.com/parallaxsw/OpenSTA)), and physical design ([The-OpenROAD-Project/OpenROAD](https://github.com/The-OpenROAD-Project/OpenROAD)), providing a complete RTL-to-layout flow.

Inspired by [OSCPU/yosys-sta](https://github.com/OSCPU/yosys-sta).

## Quick Start

```shell
# 1. Install prerequisites
apt install -y yosys klayout  # or: brew install yosys klayout

# 2. Build all tools + download NanGate45 PDK
make setup

# 3. Run the full flow (synthesis → STA → PnR)
make flow

# 4. View results
make show          # print synthesis + STA summary
make viz           # generate layout images
make gui           # open interactive OpenROAD GUI
```

Run `make help` to see all available targets.

## Setup

### Option A: Full local build (recommended)

```shell
make setup
```

This builds CUDD, OpenSTA, yosys-slang, OpenROAD, and downloads the NanGate45 PDK.

> **Note**: Building OpenROAD requires many dependencies (cmake, boost, swig, tcl, etc.).
> See [OpenROAD build instructions](https://github.com/The-OpenROAD-Project/OpenROAD/blob/master/docs/user/Build.md).
> On Ubuntu: `sudo ./OpenROAD/etc/DependencyInstaller.sh`

Alternatively, build individual components:

```shell
make setup-nangate45    # Download NanGate45 PDK only
make setup-opensta      # Build CUDD + OpenSTA only
make setup-openroad     # Build OpenROAD only
```

### Option B: Docker

```shell
make setup-docker       # Pull/build OpenSTA + OpenROAD Docker images
make setup-nangate45    # Download NanGate45 PDK

# Then use '-docker' suffix for flow targets:
make sta-docker show
make pnr-docker
```

### ASAP7 Platform (7nm)

The default platform is NanGate45 (45nm). To use ASAP7 instead:

```shell
make setup-asap7                # Download ASAP7 PDK files
make flow PLATFORM=asap7        # Run full flow with ASAP7
```

> **Directory layout**: Platform build configs live in `platforms/<platform>/` (tracked in git).
> Downloaded PDK data lives in `lib/<platform>/` (gitignored).

## Usage

### Synthesis & Timing Analysis

```shell
# Synthesis + STA with default example (gcd.v @ 50MHz)
make syn                # synthesis only
make sta                # STA (requires syn)
make sta-detail         # detailed timing report
make show               # print summary

# Custom design
make sta DESIGN=my_core \
    RTL_FILES="/path/to/top.v /path/to/sub.v" \
    VERILOG_INCLUDE_DIRS="/path/to/inc" \
    CLK_PORT_NAME=clk \
    CLK_FREQ_MHZ=100

# SystemVerilog is supported via yosys-slang
make sta DESIGN=my_core RTL_FILES="/path/to/top.sv"

# Architecture diagrams
make viz-arch-dot                # generate dot → svg
make viz-arch-dot DOT_FORMAT=png
```

> **Hint**: Remove `DPI-C` and `$` macro code from SystemVerilog files before synthesis.

### Place & Route

```shell
# Full flow: syn → sta → pnr
make flow

# Or run PnR step separately (after syn + sta)
make pnr
make pnr-fast           # faster: fewer iterations, multi-threaded routing

# Tunable parameters
make pnr CORE_UTILIZATION=50 PLACE_DENSITY=0.70

# Full RTL-to-GDS
make flow-gds
```

**PnR Parameters:**

| Parameter           | Default (nangate45) | Default (asap7) | Description              |
| ------------------- | ------------------- | --------------- | ------------------------ |
| `CORE_UTILIZATION`  | 40                  | 40              | Core area utilization (%) |
| `CORE_ASPECT_RATIO` | 1.0                 | 1.0             | Floorplan aspect ratio   |
| `PLACE_DENSITY`     | 0.60                | 0.60            | Global placement density |
| `MIN_ROUTING_LAYER` | metal2              | M2              | Bottom routing layer     |
| `MAX_ROUTING_LAYER` | metal7              | M7              | Top routing layer        |
| `DR_THREADS`        | 0 (auto)            | 0 (auto)        | Detailed routing threads |

**PnR Output Files** (in `result/<PLATFORM>-<DESIGN>-<FREQ>MHz-pnr/`):

| File                   | Description               |
| ---------------------- | ------------------------- |
| `<DESIGN>_final.def`   | Final layout (DEF format) |
| `<DESIGN>_final.odb`   | OpenROAD database         |
| `<DESIGN>_final.v`     | Post-layout netlist       |
| `timing_max_final.rpt` | Setup timing report       |
| `timing_min_final.rpt` | Hold timing report        |
| `power_final.rpt`      | Power report              |
| `clock_skew_final.rpt` | Clock tree skew           |

### Visualization

```shell
# Layout images (after PnR)
make viz                # Python/matplotlib (no X11 needed)
make viz-klayout        # KLayout batch mode (no X11 needed)
make viz-openroad       # OpenROAD headless (requires xvfb)

# Timing model plots (after STA)
make viz-timing

# Interactive GUI
make gui                # OpenROAD GUI
make gui-klayout        # KLayout GUI
```

**Layout Images** (in `result/<PLATFORM>-<DESIGN>-<FREQ>MHz-pnr/images/`):

| Image                        | Description                              |
| ---------------------------- | ---------------------------------------- |
| `<DESIGN>_chip_full.png`     | Complete chip layout (all layers)        |
| `<DESIGN>_chip_placement.png`| Cell placement view                      |
| `<DESIGN>_chip_routing.png`  | Routing layers only                      |
| `<DESIGN>_chip_power.png`    | Power distribution network               |
| `<DESIGN>_chip_clock.png`    | Clock tree network                       |
| `<DESIGN>_<stage>_full.png`  | Per-stage snapshots (floorplan → final)  |

### Docker Variants

Append `-docker` to flow targets:

```shell
make sta-docker show
make sta-detail-docker
make pnr-docker
make pnr-fast-docker
make viz-openroad-docker
```

### Clean

```shell
make clean              # Remove all results
make clean-pnr          # Remove PnR results only (keep synthesis/STA)
```

## Benchmark

See the [benchmark](benchmark) directory and [third-party IP cores](benchmark/third_party/README.md).

## Reference & Acknowledgement

- [OSCPU/yosys-sta](https://github.com/OSCPU/yosys-sta)
- [YosysHQ/yosys: Yosys Open SYnthesis Suite](https://github.com/YosysHQ/yosys)
- [parallaxsw/OpenSTA](https://github.com/parallaxsw/OpenSTA)
- [The-OpenROAD-Project/OpenROAD](https://github.com/The-OpenROAD-Project/OpenROAD)
