# Tests

Smoke tests for the yosys-opensta synthesis, timing analysis, PnR, and visualization flow.

## Usage

```shell
# Run all tests (synthesis + STA + PnR + visualization)
make test

# Individual test groups
make test-syn           # synthesis only
make test-sta           # STA (includes synthesis)
make test-show          # PPA summary (includes STA)
make test-pnr           # PnR (includes STA)
make test-viz           # visualization (arch + timing + layout)
make test-flow          # full flow end-to-end (syn → sta → pnr)

# Extra visualization tests (require xvfb + OpenROAD GUI)
make test-viz-png       # export layout PNG
make test-viz-label     # labeled module overlay PNG

# Test with ASAP7 platform
make test PLATFORM=asap7

# Clean test results
make clean
```

## Test Cases

| Target             | Description                            | Prerequisites        | Checks                                         |
| ------------------ | -------------------------------------- | -------------------- | ---------------------------------------------- |
| `test-syn-counter` | Synthesize minimal 8-bit counter       | yosys + slang        | Netlist + synth_stat.txt exist                  |
| `test-syn-op`      | Synthesize example ALU (`op.v`)        | yosys + slang        | Netlist + synth_stat/check.txt exist            |
| `test-sta-counter` | Run STA on counter                     | OpenSTA              | SDC, SDF, sta.log exist                         |
| `test-sta-op`      | Run STA on `op.v`                      | OpenSTA              | SDC, SDF, timing_model, sta.log exist           |
| `test-show`        | Run PPA summary on `op.v`              | Python3              | Command completes successfully                  |
| `test-pnr-counter` | Run PnR on counter                     | OpenROAD             | DEF, ODB, netlist, timing/area/power rpts exist |
| `test-viz-arch`    | Architecture diagram (dot → svg)       | Python3 + graphviz   | .dot + .svg files exist                         |
| `test-viz-timing`  | Timing model plots                     | Python3 + matplotlib | Command completes successfully                  |
| `test-viz-layout`  | Layout images (Python/matplotlib)      | Python3 + matplotlib | images/ directory exists                        |
| `test-viz-png`     | Export layout PNG via OpenROAD         | xvfb + OpenROAD GUI  | _final.png exists                               |
| `test-viz-label`   | Labeled module overlay                 | xvfb + OpenROAD GUI  | _final.label.png exists                         |
| `test-flow`        | Full end-to-end flow (syn → sta → pnr) | All tools            | Netlist, sta.log, _final.def exist              |

## Test Designs

- [designs/counter.v](designs/counter.v) — Minimal 8-bit counter for fast smoke testing (used for PnR/viz tests).
- `../example/op.v` — The default example ALU (used for STA/show/arch/timing tests).

## Prerequisites

- `yosys` with `slang` plugin installed
- OpenSTA built (run `make setup-opensta` from the project root)
- OpenROAD built (run `make setup-openroad` for PnR tests)
- At least one platform PDK downloaded (`make setup-nangate45` or `make setup-asap7`)
- `graphviz` for architecture diagram tests
- `xvfb-run` for `test-viz-png` and `test-viz-label` (optional)
