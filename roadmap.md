# Roadmap: Towards a Production-Grade Open-Source IC Flow

> **Current status:** Educational / PPA-estimation RTL-to-GDS flow  
> **Target:** A commercially viable, tape-out-capable open-source ASIC flow

---

## 0. Current Flow Overview

```
RTL (.v)
  │  Yosys + ABC (synthesis)
  ▼
Gate-level Netlist
  │  OpenSTA (pre-layout STA)
  ▼
Timing Reports / SDC / SDF
  │  OpenROAD (floorplan → place → CTS → route → fill)
  ▼
DEF / ODB / GDS
```

**Supported platforms:** NanGate45 (45nm academic), ASAP7 (7nm predictive)  
**Benchmark designs:** simple ALU (`op`), Hazard3, PicoRV32, SERV

---

## Phase 1 — Constraint & Timing Closure (High Priority)

These items have the highest impact-to-effort ratio and are prerequisites for any meaningful timing closure.

### 1.1 Complete SDC Constraints

| Item | Status | Description |
|------|--------|-------------|
| IO delay | ❌ Missing | Add `set_input_delay` / `set_output_delay` on all primary ports |
| Clock uncertainty | ❌ Missing | Add `set_clock_uncertainty` (jitter + pre-CTS skew margin) |
| Max transition / fanout | ❌ Missing | Add `set_max_transition`, `set_max_fanout`, `set_max_capacitance` |
| Driving cell / load | ❌ Missing | Add `set_driving_cell` on inputs, `set_load` on outputs |
| False / multicycle paths | ❌ Missing | Add `set_false_path`, `set_multicycle_path` where applicable |
| Clock groups | ❌ Missing | `set_clock_groups` for multi-clock designs |
| SDC template | ❌ Missing | Provide a reusable SDC template per platform |

### 1.2 Hold Timing Fix

| Item | Status | Description |
|------|--------|-------------|
| Post-CTS hold repair | ❌ **Critical** | Add `repair_timing -hold` after CTS in PnR scripts |
| Post-route hold repair | ❌ Missing | Secondary hold fix after detailed routing |

> **Impact:** Without hold fix, any fabricated chip **will fail**. This is the single most critical gap.

### 1.3 Multi-Corner Multi-Mode (MMMC)

| Item | Status | Description |
|------|--------|-------------|
| SS corner for setup | ❌ Missing | Slow-slow corner Liberty for worst-case setup analysis |
| FF corner for hold | ❌ Missing | Fast-fast corner Liberty for worst-case hold analysis |
| Multi-corner STA | ❌ Missing | Run OpenSTA across ≥ 2 PVT corners |
| OCV / timing derate | ❌ Missing | `set_timing_derate` for on-chip variation |
| AOCV / POCV support | ❌ Missing | Advanced OCV models (library-dependent) |

---

## Phase 2 — Physical Design Quality

### 2.1 Floorplan Improvements

| Item | Status | Description |
|------|--------|-------------|
| Manual floorplan support | ❌ Missing | Allow user-specified die size, macro placement, blockage regions |
| IO pad ring | ❌ Missing | IO pad placement, pad-limited die support |
| Macro placement | ❌ Missing | SRAM / hard IP macro integration and placement |
| Rectilinear die shape | ❌ Missing | Non-rectangular die boundary support |

### 2.2 Power Network

| Item | Status | Description |
|------|--------|-------------|
| Multi-layer PDN | ⚠️ Basic | Current: followpin + 2-layer straps. Need robust multi-layer mesh |
| IR drop analysis | ❌ Missing | Static / dynamic IR drop checking (OpenROAD has `analyze_power_grid`) |
| EM analysis | ❌ Missing | Electromigration checking on power/signal nets |

### 2.3 CTS Enhancements

| Item | Status | Description |
|------|--------|-------------|
| Useful skew | ❌ Missing | Intentional skew for timing optimization |
| Multi-corner CTS | ❌ Missing | Balance clock tree across PVT corners |
| Clock gating integration | ❌ Missing | ICG cell insertion and CTS-aware placement |
| Insertion delay target | ❌ Missing | Specify max clock insertion delay |

### 2.4 Routing & Optimization

| Item | Status | Description |
|------|--------|-------------|
| Post-route timing opt | ❌ Missing | Post-route buffer insertion / gate sizing ECO |
| SI-aware routing | ❌ Missing | Crosstalk-aware timing analysis and net spacing |
| Metal fill (dummy metal) | ❌ Missing | Density-driven metal fill for CMP uniformity |
| Via optimization | ❌ Missing | Double-via insertion for yield |

---

## Phase 3 — Signoff

### 3.1 Timing Signoff

| Item | Status | Description |
|------|--------|-------------|
| Multi-corner signoff | ❌ Missing | ≥ 3 PVT corners with OCV |
| CPPR | ⚠️ Partial | Clock Path Pessimism Removal — verify enabled post-CTS |
| SI signoff | ❌ Missing | Crosstalk noise and delay analysis |
| CCS / ECSM Liberty | ❌ Missing | Current: NLDM only. Advanced nodes need CCS/ECSM |

### 3.2 Physical Verification

| Item | Status | Description |
|------|--------|-------------|
| DRC (full) | ⚠️ Basic | Current: OpenROAD built-in DRC. Need full-deck DRC (KLayout DRC or Magic) |
| LVS | ❌ **Critical** | Layout vs Schematic completely missing |
| ERC | ❌ Missing | Electrical Rule Check |
| Antenna check | ✅ Done | `check_antennas` in PnR script |
| Density check | ❌ Missing | Metal / via density rule compliance |

### 3.3 Parasitic Extraction

| Item | Status | Description |
|------|--------|-------------|
| OpenRCX | ✅ Done | Rule-based extraction integrated in PnR flow |
| Accuracy validation | ❌ Missing | Correlation with field-solver results |
| SPEF back-annotation | ✅ Done | Final SPEF written and read back for timing |

---

## Phase 4 — DFT (Design for Test)

| Item | Status | Description |
|------|--------|-------------|
| Scan chain insertion | ❌ Missing | Scan flip-flop replacement, chain stitching |
| ATPG | ❌ Missing | Automatic Test Pattern Generation |
| JTAG / boundary scan | ❌ Missing | IEEE 1149.1 interface |
| MBIST | ❌ Missing | Memory Built-In Self-Test for SRAM macros |
| Compression | ❌ Missing | Test data compression for reduced test time |

> **Note:** Open-source DFT tools are limited. [Fault](https://github.com/AUCOHL/Fault) provides basic scan insertion for Yosys-based flows.

---

## Phase 5 — Verification & Analysis

### 5.1 Functional Verification

| Item | Status | Description |
|------|--------|-------------|
| RTL simulation | ❌ Missing | Verilator / iverilog integration for regression |
| Gate-level simulation | ❌ Missing | Post-synthesis and post-PnR netlist simulation with SDF back-annotation |
| Formal verification | ❌ Missing | Equivalence checking (syn vs RTL, PnR vs syn) |
| UVM testbench | ❌ Missing | Constrained-random verification framework |

### 5.2 Static Analysis

| Item | Status | Description |
|------|--------|-------------|
| CDC analysis | ❌ Missing | Clock Domain Crossing checks |
| RDC analysis | ❌ Missing | Reset Domain Crossing checks |
| RTL lint | ❌ Missing | Coding style and common bug detection |
| Power intent (UPF) | ❌ Missing | Multi-voltage domain specification |

### 5.3 Power Analysis

| Item | Status | Description |
|------|--------|-------------|
| Activity-driven power | ❌ Missing | VCD/SAIF-based switching activity for accurate power |
| Leakage optimization | ❌ Missing | Multi-Vt cell swapping (HVT/SVT/LVT) |
| Power gating | ❌ Missing | UPF-driven power domain shutoff |
| Dynamic IR drop | ❌ Missing | Transient current analysis |

---

## Phase 6 — PDK & Library Maturity

| Item | Status | Description |
|------|--------|-------------|
| Real foundry PDK | ❌ Blocked | NanGate45 / ASAP7 are academic; tape-out requires TSMC/Samsung/GF PDK (under NDA) |
| Multi-Vt libraries | ❌ Missing | SVT + LVT + HVT + ULVT variants for power-performance trade-off |
| Multiple PVT corners | ❌ Missing | SS/FF/TT × voltage × temperature Liberty files |
| Memory compiler | ❌ Missing | SRAM/ROM/RF macro generation (e.g., OpenRAM for academic use) |
| IO library | ❌ Missing | IO pad cells with ESD protection |
| Hard IP models | ❌ Missing | PLL, ADC, SerDes, USB PHY timing/power/physical models |

> **Open-source options:** [SkyWater SKY130](https://github.com/google/skywater-pdk) and [IHP SG13G2](https://github.com/IHP-GmbH/IHP-Open-PDK) are open PDKs that can be taped out through [Efabless](https://efabless.com/).

---

## Phase 7 — Infrastructure & Automation

| Item | Status | Description |
|------|--------|-------------|
| ECO flow | ❌ Missing | Engineering Change Order — incremental netlist fixes without full re-run |
| Incremental compile | ❌ Missing | Avoid full re-synthesis when only part of the design changes |
| CI/CD integration | ❌ Missing | Automated regression (syn → sta → pnr) on design changes |
| Design database | ❌ Missing | Versioned design checkpoint management |
| Report dashboard | ⚠️ Basic | `ppa_summary.py` exists; need trend tracking, comparison across runs |
| Packaging | ❌ Missing | Die-to-package interface (bump map, wire bond, RDL) |

---

## Maturity Summary

| Dimension | Current | Target | Gap |
|-----------|---------|--------|-----|
| RTL → Gate synthesis | ★★★☆☆ | ★★★★★ | MMMC, advanced optimization, DFT |
| SDC / Constraints | ★☆☆☆☆ | ★★★★★ | **Largest gap** — only `create_clock` today |
| Pre-layout STA | ★★☆☆☆ | ★★★★★ | Multi-corner, OCV, IO delay |
| Floorplan | ★★☆☆☆ | ★★★★☆ | Macro/IO/manual control |
| Placement + CTS | ★★★☆☆ | ★★★★☆ | Hold fix, useful skew |
| Routing | ★★★☆☆ | ★★★★☆ | Post-route opt, SI, metal fill |
| Timing signoff | ★☆☆☆☆ | ★★★★★ | Multi-corner + OCV + SI |
| Physical verification | ★☆☆☆☆ | ★★★★★ | LVS, full DRC, density |
| DFT | ☆☆☆☆☆ | ★★★★☆ | Scan, ATPG, JTAG, MBIST |
| Verification | ☆☆☆☆☆ | ★★★★☆ | Sim, formal, CDC |
| PDK readiness | ★★☆☆☆ | ★★★★★ | Real PDK, multi-Vt, memory compiler |

---

## Suggested Execution Priority

```
Immediate wins (Phase 1):
  ├── Complete SDC constraints (IO delay, uncertainty, max_tran)
  ├── Add repair_timing -hold in PnR scripts
  └── Add set_timing_derate for basic OCV

Short-term (Phase 2-3):
  ├── Multi-corner Liberty + multi-corner STA
  ├── Post-route timing optimization
  ├── IR drop analysis (OpenROAD built-in)
  ├── KLayout DRC with real rule deck
  └── LVS integration (KLayout or netgen)

Medium-term (Phase 4-5):
  ├── Scan chain insertion (Fault or custom)
  ├── Gate-level simulation with SDF
  ├── Formal equivalence checking
  └── Activity-based power analysis (SAIF)

Long-term (Phase 6-7):
  ├── SKY130 / IHP SG13G2 PDK integration
  ├── OpenRAM memory compiler
  ├── CI/CD pipeline
  └── ECO flow
```

---

## References

- [OpenROAD Flow Scripts (ORFS)](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts) — mature open-source RTL-to-GDS reference
- [SkyWater SKY130 PDK](https://github.com/google/skywater-pdk) — open foundry PDK (130nm, tape-out capable)
- [IHP SG13G2 PDK](https://github.com/IHP-GmbH/IHP-Open-PDK) — open SiGe BiCMOS PDK (130nm)
- [OpenRAM](https://github.com/VLSIDA/OpenRAM) — open-source SRAM compiler
- [Fault](https://github.com/AUCOHL/Fault) — open-source DFT / ATPG for Yosys
- [OpenLane](https://github.com/efabless/openlane2) — automated RTL-to-GDSII for SKY130/GF180
