# yosys-opensta

Use open-source EDA tools for ASIC synthesis ([YosysHQ/yosys](https://github.com/YosysHQ/yosys)), timing analysis ([parallaxsw/OpenSTA](https://github.com/parallaxsw/OpenSTA)), and physical design ([The-OpenROAD-Project/OpenROAD](https://github.com/The-OpenROAD-Project/OpenROAD)), providing a complete RTL-to-layout flow.

Inspired by [OSCPU/yosys-sta](https://github.com/OSCPU/yosys-sta).

## Quick Start

```shell
# 1. Install prerequisites
apt install -y yosys klayout  # or: brew install yosys klayout

# 2. Build all tools + download NanGate45 PDK
make setup

# 3. Run the full flow (synthesis -> STA -> PnR)
make flow

# 4. View results
make show          # print synthesis + STA summary
make viz           # generate layout images
make gui           # open interactive OpenROAD GUI
```

Run `make help` to see all available targets.

## Setup

### Local build

```shell
make setup
```

This builds CUDD, OpenSTA, sv-elab (formerly yosys-slang), OpenROAD, and downloads the NanGate45 PDK.

> **Note**: Building OpenROAD requires many dependencies (cmake, boost, swig, tcl, etc.).
> See [OpenROAD build instructions](https://github.com/The-OpenROAD-Project/OpenROAD/blob/master/docs/user/Build.md).
> On Ubuntu: `sudo ./OpenROAD/etc/DependencyInstaller.sh`

Alternatively, build individual components:

```shell
make setup-nangate45    # Download NanGate45 PDK only
make setup-opensta      # Build CUDD + OpenSTA only
make setup-openroad     # Build OpenROAD only
```

### ASAP7 Platform (7nm)

The default platform is NanGate45 (45nm). To use ASAP7 instead:

```shell
make setup-asap7                # Download ASAP7 PDK files
make flow PLATFORM=asap7        # Run full flow with ASAP7
```

> **Directory layout**: Platform build configs live in `platforms/<platform>/` (tracked in git).
> Downloaded PDK data lives in `third_party/lib/<platform>/` (gitignored).

### SKY130HD Platform / TinyTapeout Preflight

SKY130 support targets the `sky130_fd_sc_hd` standard-cell library from the SKY130A PDK packaging used by OpenROAD-flow-scripts. This is the digital library expected by TinyTapeout projects; `sky130hd` is the flow platform/library name, while SKY130A is the full PDK distribution.

```shell
make setup-sky130hd
make flow-gds PLATFORM=sky130hd
make signoff PLATFORM=sky130hd
```

For TinyTapeout-style local preflight, the Makefile generates a TinyTapeout project under `result/sky130hd-<TT_TOP>-<FREQ>MHz-tt/` from `DESIGN`, `RTL_FILES`, and either a wrapper file or TT-native RTL:

```shell
# Default: auto-wrapper is generated for DESIGN; scaffold written to result/sky130hd-<TT_TOP>-<FREQ>MHz-tt/
make tt-scaffold
make tt-preflight

# Custom non-native design: provide a TT wrapper Verilog file
make tt-preflight DESIGN=my_core \
    RTL_FILES="rtl/my_core.v rtl/submodule.v" \
    TT_TOP=tt_um_my_core \
    TT_WRAPPER_FILE=path/to/tt_um_my_core.v

# TT-native design: RTL top already has ui_in/uo_out/uio_in/uio_out/uio_oe/ena/clk/rst_n
make tt-preflight DESIGN=tt_um_my_core \
    RTL_FILES="rtl/tt_um_my_core.v" \
    TT_NATIVE=1

# Existing generated netlist: scaffold and link-check a large design such as rapt
make tt-check DESIGN=rapt CLK_FREQ_MHZ=50
```

`DESIGN` and `RTL_FILES` are enough to generate the scaffold, which lands in `result/sky130hd-<TT_TOP>-<FREQ>MHz-tt/`. By default `TT_AUTO_WRAP=1` so an evaluation wrapper is generated automatically. When `result/sky130hd-<DESIGN>-<FREQ>MHz/<DESIGN>.netlist.src.v` exists it is used as `TT_RTL_FILES` automatically. Provide `TT_WRAPPER_FILE` (explicit path) for a protocol-correct wrapper, or use `TT_NATIVE=1` when the RTL top already exposes the TinyTapeout interface.

This runs the local SKY130HD RTL-to-GDS flow and the OpenROAD signoff precheck for `TT_TOP`. It is a block-flow preflight, not a replacement for the official TinyTapeout hardening/signoff. Before submitting to a shuttle, run the TinyTapeout support tooling/LibreLane flow and use its generated reports as the final authority.

See [docs/tinytapeout-evaluation.md](docs/tinytapeout-evaluation.md) for TinyTapeout-specific examples, including `rapt`.
See [docs/tapeout-engineering-flow.md](docs/tapeout-engineering-flow.md) for the end-to-end engineering flow from RTL preparation to local tapeout-style deliverables.

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

# SystemVerilog is supported via sv-elab (formerly yosys-slang)
make sta DESIGN=my_core RTL_FILES="/path/to/top.sv"

# Hierarchical synthesis (preserve sub-module boundaries)
make syn SYNTH_HIERARCHICAL=1

# Custom ABC optimization script
make syn ABC_SCRIPT="+strash;dch;map;topo;dnsize;buffer;upsize;"

# Architecture diagrams
make viz-arch-dot                # generate dot -> svg
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
# Full flow: syn -> sta -> pnr
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

| Parameter                   | Default (nangate45) | Default (asap7) | Default (sky130hd) | Description                                         |
| --------------------------- | ------------------- | --------------- | ------------------ | --------------------------------------------------- |
| `CORE_UTILIZATION`          | 40                  | 40              | 40                 | Core area utilization (%)                           |
| `CORE_ASPECT_RATIO`         | 1.0                 | 1.0             | 1.0                | Floorplan aspect ratio                              |
| `PLACE_DENSITY`             | 0.60                | 0.60            | 0.60               | Global placement density                            |
| `MIN_ROUTING_LAYER`         | metal2              | M2              | met1               | Bottom routing layer                                |
| `MAX_ROUTING_LAYER`         | metal10             | M7              | met5               | Top routing layer                                   |
| `DR_THREADS`                | 0 (auto)            | 0 (auto)        | 0 (auto)           | Detailed routing threads                            |
| `PIN_CONSTRAINT_FILE`       | (empty)             | (empty)         | (empty)            | Pin constraint TCL file (optional)                  |
| `PNR_RESUME_FROM`           | (empty)             | (empty)         | (empty)            | Resume from stage: floorplan/place/cts/route/finish |
| `REPAIR_ANTENNAS`           | 1                   | 1               | 1                  | Run antenna repair around routing                   |
| `ANTENNA_REPAIR_ITERS`      | 5                   | 5               | 5                  | Global-route antenna repair iterations              |
| `ANTENNA_REPAIR_DRT_ITERS`  | 5                   | 5               | 5                  | Post-detailed-route antenna repair iterations       |
| `ANTENNA_RATIO_MARGIN`      | 10                  | 10              | 10                 | Antenna ratio repair margin (%)                     |
| `ANTENNA_REPAIR_EXTRA_ARGS` | (empty)             | (empty)         | `-diode_only`      | Extra OpenROAD `repair_antennas` arguments          |

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

### Signoff Precheck

`make signoff-openroad` runs a local report gate over the generated synthesis and OpenROAD artifacts. It checks for missing files, Yosys `check` warnings/problems, non-empty route DRC, antenna violations, OpenROAD errors, missing SPEF where required, RCX fallback, timing violations, and forbidden standard cells.

```shell
make signoff-openroad PLATFORM=sky130hd
make signoff PLATFORM=sky130hd
```

The JSON report is written to `result/<PLATFORM>-<DESIGN>-<FREQ>MHz-pnr/signoff_openroad.json`. For `sky130hd`, the gate requires extracted SPEF and forbids `sky130_fd_sc_hd__lpflow_*`/`probe` cells by default.

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
| `<DESIGN>_<stage>_full.png`   | Per-stage snapshots (floorplan -> final) |

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
make test-signoff       # OpenROAD signoff precheck smoke test
make test-viz           # Visualization tests only
make test-flow          # Full flow end-to-end (syn -> sta -> pnr)
make test PLATFORM=asap7  # Test with ASAP7 platform
```

See the [tests](tests) directory for details.

## Project Structure

```
scripts/
|-- yosys.tcl               # Yosys synthesis (supports ABC_SCRIPT, SYNTH_HIERARCHICAL)
|-- opensta_common.tcl      # Shared STA setup (env, platform, liberty, SDC)
|-- opensta.tcl             # STA summary + fmax report (sources common)
|-- opensta_detail.tcl      # Detailed timing with source attribution (sources common)
|-- openroad_pnr_common.tcl # Shared PnR flow (stage checkpoints, resume support)
|-- openroad_pnr.tcl        # Standard PnR mode (sources common)
|-- openroad_pnr_fast.tcl   # Fast PnR mode (sources common)
|-- ppa_summary.py          # PPA report generator
`-- ...                     # Visualization and utility scripts
platforms/
|-- nangate45/              # NanGate FreePDK45 (45nm)
|   |-- config.tcl          # OpenROAD/OpenSTA platform config
|   |-- yosys_config.tcl    # Yosys synthesis config
|   |-- platform.mk         # Makefile variables
|   `-- setRC.tcl           # RC extraction values
|-- asap7/                  # ASAP7 7nm FinFET
|   |-- config.tcl
|   |-- yosys_config.tcl
|   |-- platform.mk
|   `-- setRC.tcl
`-- sky130hd/               # SKY130 sky130_fd_sc_hd digital flow
    |-- config.tcl
    |-- yosys_config.tcl
    |-- platform.mk
    `-- setRC.tcl
tinytapeout/
`-- tt/                     # Optional TinyTapeout support tools clone
tests/
|-- Makefile                # Test runner
|-- README.md               # Test documentation
`-- designs/
    `-- counter.v           # Minimal test design (8-bit counter)
```

The PnR scripts use a **common + wrapper** pattern: `openroad_pnr.tcl` and `openroad_pnr_fast.tcl` are thin wrappers that set mode-specific defaults and `source` the shared `openroad_pnr_common.tcl`. Similarly, `opensta.tcl` and `opensta_detail.tcl` share setup logic via `opensta_common.tcl`.

## Benchmark

See the [benchmark](benchmark) directory and [third-party IP cores](benchmark/third_party/README.md).

## Reference & Acknowledgement

- [OSCPU/yosys-sta](https://github.com/OSCPU/yosys-sta)
- [YosysHQ/yosys: Yosys Open SYnthesis Suite](https://github.com/YosysHQ/yosys)
- [parallaxsw/OpenSTA](https://github.com/parallaxsw/OpenSTA)
- [The-OpenROAD-Project/OpenROAD](https://github.com/The-OpenROAD-Project/OpenROAD)
