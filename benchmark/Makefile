# =====================================================================
#  Benchmark Targets
#  Usage: make sta-hazard3 / make flow-picorv32 / etc.
#  Append PLATFORM=asap7 to use ASAP7 instead of NanGate45.
# =====================================================================

PLATFORM       ?= nangate45
CLK_FREQ_MHZ   ?= 50
ROOT_DIR       := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
RESULT_PREFIX  := $(ROOT_DIR)/result/$(PLATFORM)
CHECK_SCRIPT   := $(ROOT_DIR)/scripts/check_benchmark.py

# Per-design cell-count floor for the benchmark validator. Designed to catch
# degenerate runs (missing RTL, wrong top, unmapped memories) -- not to gate
# on PPA quality. Numbers are conservative w.r.t. nangate45/asap7 results.
HAZARD3_MIN_CELLS  ?= 4000
PICORV32_MIN_CELLS ?= 1500
# serv_rf_top = serv_top (bit-serial CPU core) + serv_rf_ram (integrated 32x32 RF).
# Without the RF wrapper the CPU's o_rf_*/i_rdata* ports stay open and STA
# results are meaningless, so always benchmark serv_rf_top.
SERV_MIN_CELLS     ?= 200

# --- Hazard3 (3-stage RV32IMACZb*) ---
sta-hazard3: third_party/Hazard3
	@make -C .. sta show \
		DESIGN=hazard3_core \
		CLK_PORT_NAME=clk \
		RTL_FILES="$(shell find $(abspath third_party/Hazard3/hdl) -name "*.v")" \
		VERILOG_INCLUDE_DIRS="$(abspath third_party/Hazard3/hdl)"

flow-hazard3: third_party/Hazard3
	@make -C .. flow \
		DESIGN=hazard3_core \
		CLK_PORT_NAME=clk \
		RTL_FILES="$(shell find $(abspath third_party/Hazard3/hdl) -name "*.v")" \
		VERILOG_INCLUDE_DIRS="$(abspath third_party/Hazard3/hdl)"

# --- PicoRV32 (RV32IMC) ---
sta-picorv32: third_party/picorv32
	@make -C .. sta show \
		DESIGN=picorv32 \
		CLK_PORT_NAME=clk \
		RTL_FILES="$(shell find $(abspath third_party/picorv32) -name "picorv32.v")" \
		VERILOG_INCLUDE_DIRS="$(abspath third_party/picorv32)"

flow-picorv32: third_party/picorv32
	@make -C .. flow \
		DESIGN=picorv32 \
		CLK_PORT_NAME=clk \
		RTL_FILES="$(shell find $(abspath third_party/picorv32) -name "picorv32.v")" \
		VERILOG_INCLUDE_DIRS="$(abspath third_party/picorv32)"

# --- SERV (bit-serial RISC-V) ---
# Use serv_rf_top (CPU core + integrated register file). serv_top alone leaves
# the RF interface ports unconnected, which produces a degenerate STA result.
sta-serv: third_party/serv
	@make -C .. sta show \
		DESIGN=serv_rf_top \
		CLK_PORT_NAME=clk \
		RTL_FILES="$(shell find $(abspath third_party/serv/rtl) -name "*.v")" \
		VERILOG_INCLUDE_DIRS="$(abspath third_party/serv/rtl)"

flow-serv: third_party/serv
	@make -C .. flow \
		DESIGN=serv_rf_top \
		CLK_PORT_NAME=clk \
		RTL_FILES="$(shell find $(abspath third_party/serv/rtl) -name "*.v")" \
		VERILOG_INCLUDE_DIRS="$(abspath third_party/serv/rtl)"

# --- Third-party source checkout ---
third_party/Hazard3:
	git clone https://github.com/Wren6991/Hazard3 $@

third_party/picorv32:
	git clone https://github.com/YosysHQ/picorv32 $@

third_party/serv:
	git clone https://github.com/olofk/serv $@

# =====================================================================
#  Validation: assert each benchmark produced a well-formed STA report
#  (real critical path, fmax, area, expected mapped-cell count, etc.).
#  Use these in CI to detect missing RTL files / unmapped memories /
#  silently-empty STA runs.
# =====================================================================
check-hazard3: ## Validate hazard3 STA result directory
	python3 $(CHECK_SCRIPT) $(RESULT_PREFIX)-hazard3_core-$(CLK_FREQ_MHZ)MHz \
		--design hazard3_core --clk-port clk --min-cells $(HAZARD3_MIN_CELLS)

check-picorv32: ## Validate picorv32 STA result directory
	python3 $(CHECK_SCRIPT) $(RESULT_PREFIX)-picorv32-$(CLK_FREQ_MHZ)MHz \
		--design picorv32 --clk-port clk --min-cells $(PICORV32_MIN_CELLS)

check-serv: ## Validate serv STA result directory
	python3 $(CHECK_SCRIPT) $(RESULT_PREFIX)-serv_rf_top-$(CLK_FREQ_MHZ)MHz \
		--design serv_rf_top --clk-port clk --min-cells $(SERV_MIN_CELLS)

check-all: check-hazard3 check-picorv32 check-serv ## Validate all benchmarks

# Convenience: run sta + check together for CI.
ci-hazard3:  sta-hazard3  check-hazard3  ## sta-hazard3  + check-hazard3
ci-picorv32: sta-picorv32 check-picorv32 ## sta-picorv32 + check-picorv32
ci-serv:     sta-serv     check-serv     ## sta-serv     + check-serv
ci-all:      ci-hazard3 ci-picorv32 ci-serv ## All sta-* + check-*

.PHONY: sta-hazard3 sta-picorv32 sta-serv \
        flow-hazard3 flow-picorv32 flow-serv \
        check-hazard3 check-picorv32 check-serv check-all \
        ci-hazard3 ci-picorv32 ci-serv ci-all
