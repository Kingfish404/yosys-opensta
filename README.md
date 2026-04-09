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
> Downloaded PDK data lives in `third_party/lib/<platform>/` (gitignored).

## Usage

### Synthesis & Timing Analysis

```shell
# Synthesis + STA with default example (op.v @ 50MHz)
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

# Hierarchical synthesis (preserve sub-module boundaries)
make syn SYNTH_HIERARCHICAL=1

# Custom ABC optimization script
make syn ABC_SCRIPT="+strash;dch;map;topo;dnsize;buffer;upsize;"

# Architecture diagrams
make viz-arch-dot                # generate dot → svg
make viz-arch-dot DOT_FORMAT=png
```

**Synthesis Parameters:**

| Parameter            | Default | Description                                           |
| -------------------- | ------- | ----------------------------------------------------- |
| `SYNTH_HIERARCHICAL` | 0       | Hierarchical synthesis (0=flat, 1=preserve hierarchy) |
| `ABC_SCRIPT`         | (empty) | ABC optimization script override (empty=default)      |

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

# Resume PnR from a specific stage (uses ODB checkpoints)
make pnr-from-place     # re-run from placement onwards
make pnr-from-cts       # re-run from CTS onwards
make pnr-from-route     # re-run from routing onwards
make pnr-from-finish    # re-run finish stage only (reports + outputs)

# Or use PNR_RESUME_FROM with any PnR target
make pnr PNR_RESUME_FROM=cts
```

**PnR Parameters:**

| Parameter             | Default (nangate45) | Default (asap7) | Description                                         |
| --------------------- | ------------------- | --------------- | --------------------------------------------------- |
| `CORE_UTILIZATION`    | 40                  | 40              | Core area utilization (%)                           |
| `CORE_ASPECT_RATIO`   | 1.0                 | 1.0             | Floorplan aspect ratio                              |
| `PLACE_DENSITY`       | 0.60                | 0.60            | Global placement density                            |
| `MIN_ROUTING_LAYER`   | metal2              | M2              | Bottom routing layer                                |
| `MAX_ROUTING_LAYER`   | metal10             | M7              | Top routing layer                                   |
| `DR_THREADS`          | 0 (auto)            | 0 (auto)        | Detailed routing threads                            |
| `PIN_CONSTRAINT_FILE` | (empty)             | (empty)         | Pin constraint TCL file (optional)                  |
| `PNR_RESUME_FROM`     | (empty)             | (empty)         | Resume from stage: floorplan/place/cts/route/finish |

**PnR Output Files** (in `result/<PLATFORM>-<DESIGN>-<FREQ>MHz-pnr/`):

| File                   | Description                         |
| ---------------------- | ----------------------------------- |
| `<DESIGN>_final.def`   | Final layout (DEF format)           |
| `<DESIGN>_final.odb`   | OpenROAD database                   |
| `<DESIGN>_final.v`     | Post-layout netlist                 |
| `<DESIGN>_final.spef`  | Extracted parasitics (if RCX rules) |
| `timing_max_final.rpt` | Setup timing report                 |
| `timing_min_final.rpt` | Hold timing report                  |
| `timing_violators.rpt` | All timing violators                |
| `power_final.rpt`      | Power report                        |
| `area_final.rpt`       | Design area report                  |
| `clock_skew_final.rpt` | Clock tree skew                     |
| `antenna_final.rpt`    | Antenna check report                |
| `1_floorplan.odb`      | Stage checkpoint (for resume)       |
| `2_place.odb`          | Stage checkpoint (for resume)       |
| `3_cts.odb`            | Stage checkpoint (for resume)       |
| `4_route.odb`          | Stage checkpoint (for resume)       |

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

| Image                         | Description                             |
| ----------------------------- | --------------------------------------- |
| `<DESIGN>_chip_full.png`      | Complete chip layout (all layers)       |
| `<DESIGN>_chip_placement.png` | Cell placement view                     |
| `<DESIGN>_chip_routing.png`   | Routing layers only                     |
| `<DESIGN>_chip_power.png`     | Power distribution network              |
| `<DESIGN>_chip_clock.png`     | Clock tree network                      |
| `<DESIGN>_<stage>_full.png`   | Per-stage snapshots (floorplan → final) |

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

### Testing

Smoke tests verify that the full flow works correctly.

```shell
make test               # Run all tests (syn + STA + PnR + viz)
make test-syn           # Synthesis tests only
make test-sta           # STA tests only
make test-pnr           # PnR tests only
make test-viz           # Visualization tests only
make test-flow          # Full flow end-to-end (syn → sta → pnr)
make test PLATFORM=asap7  # Test with ASAP7 platform
```

See the [tests](tests) directory for details.

## Project Structure

```
scripts/
├── yosys.tcl               # Yosys synthesis (supports ABC_SCRIPT, SYNTH_HIERARCHICAL)
├── opensta_common.tcl      # Shared STA setup (env, platform, liberty, SDC)
├── opensta.tcl             # STA summary + fmax report (sources common)
├── opensta_detail.tcl      # Detailed timing with source attribution (sources common)
├── openroad_pnr_common.tcl # Shared PnR flow (stage checkpoints, resume support)
├── openroad_pnr.tcl        # Standard PnR mode (sources common)
├── openroad_pnr_fast.tcl   # Fast PnR mode (sources common)
├── ppa_summary.py          # PPA report generator
└── ...                     # Visualization and utility scripts
platforms/
├── nangate45/              # NanGate FreePDK45 (45nm)
│   ├── config.tcl          # OpenROAD/OpenSTA platform config
│   ├── yosys_config.tcl    # Yosys synthesis config
│   ├── platform.mk         # Makefile variables
│   └── setRC.tcl           # RC extraction values
└── asap7/                  # ASAP7 7nm FinFET
    ├── config.tcl
    ├── yosys_config.tcl
    ├── platform.mk
    └── setRC.tcl
tests/
├── Makefile                # Test runner
├── README.md               # Test documentation
└── designs/
    └── counter.v           # Minimal test design (8-bit counter)
```

The PnR scripts use a **common + wrapper** pattern: `openroad_pnr.tcl` and `openroad_pnr_fast.tcl` are thin wrappers that set mode-specific defaults and `source` the shared `openroad_pnr_common.tcl`. Similarly, `opensta.tcl` and `opensta_detail.tcl` share setup logic via `opensta_common.tcl`.

## Benchmark

See the [benchmark](benchmark) directory and [third-party IP cores](benchmark/third_party/README.md).

## Reference & Acknowledgement

- [OSCPU/yosys-sta](https://github.com/OSCPU/yosys-sta)
- [YosysHQ/yosys: Yosys Open SYnthesis Suite](https://github.com/YosysHQ/yosys)
- [parallaxsw/OpenSTA](https://github.com/parallaxsw/OpenSTA)
- [The-OpenROAD-Project/OpenROAD](https://github.com/The-OpenROAD-Project/OpenROAD)
