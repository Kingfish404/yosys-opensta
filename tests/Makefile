# =====================================================================
#  Test Suite for yosys-opensta
#  Usage: make test          — run all tests (syn + sta + pnr + viz)
#         make test-syn      — synthesis smoke tests only
#         make test-sta      — STA smoke tests only
#         make test-pnr      — PnR smoke tests only
#         make test-viz      — visualization tests only
#         make test-flow     — full flow end-to-end (syn → sta → pnr)
#         make clean         — remove test results
#
#  Append PLATFORM=asap7 to test against the ASAP7 platform.
# =====================================================================

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

TESTS_DIR := $(shell pwd)
ROOT_DIR  := $(TESTS_DIR)/..

# Test design: minimal counter (fast synthesis / PnR)
COUNTER_DESIGN     := counter
COUNTER_RTL        := $(TESTS_DIR)/designs/counter.v
COUNTER_CLK        := clock
COUNTER_FREQ       := 50

# Test design: example ALU (op.v from example/)
OP_DESIGN          := op
OP_RTL             := $(ROOT_DIR)/example/op.v
OP_CLK             := clock
OP_FREQ            := 50

PLATFORM ?= nangate45

# Result directories (match the main Makefile convention)
COUNTER_RESULT     := $(ROOT_DIR)/result/$(PLATFORM)-$(COUNTER_DESIGN)-$(COUNTER_FREQ)MHz
COUNTER_PNR_RESULT := $(ROOT_DIR)/result/$(PLATFORM)-$(COUNTER_DESIGN)-$(COUNTER_FREQ)MHz-pnr
OP_RESULT          := $(ROOT_DIR)/result/$(PLATFORM)-$(OP_DESIGN)-$(OP_FREQ)MHz
OP_PNR_RESULT      := $(ROOT_DIR)/result/$(PLATFORM)-$(OP_DESIGN)-$(OP_FREQ)MHz-pnr

# Common make arguments per design (reduce repetition)
COUNTER_ARGS = DESIGN=$(COUNTER_DESIGN) \
	RTL_FILES="$(COUNTER_RTL)" \
	VERILOG_INCLUDE_DIRS="$(TESTS_DIR)/designs" \
	CLK_PORT_NAME=$(COUNTER_CLK) \
	CLK_FREQ_MHZ=$(COUNTER_FREQ) \
	PLATFORM=$(PLATFORM)

OP_ARGS = DESIGN=$(OP_DESIGN) \
	RTL_FILES="$(OP_RTL)" \
	VERILOG_INCLUDE_DIRS="$(ROOT_DIR)/example" \
	CLK_PORT_NAME=$(OP_CLK) \
	CLK_FREQ_MHZ=$(OP_FREQ) \
	PLATFORM=$(PLATFORM)

# Track pass/fail counts
PASS = \033[32mPASS\033[0m
FAIL = \033[31mFAIL\033[0m

# =====================================================================
#  Default: run all tests
# =====================================================================
.DEFAULT_GOAL := test

test: test-syn test-sta test-show test-pnr test-viz ## Run all tests
	@echo ""
	@echo -e "$(PASS) All tests passed."

# =====================================================================
#  Synthesis Tests
# =====================================================================
test-syn: test-syn-counter test-syn-op ## Synthesis smoke tests
	@echo -e "$(PASS) All synthesis tests passed."

test-syn-counter: ## Synthesize minimal counter
	@echo "=== TEST: syn counter ($(PLATFORM)) ==="
	@make -C $(ROOT_DIR) syn $(COUNTER_ARGS)
	@test -s $(COUNTER_RESULT)/$(COUNTER_DESIGN).netlist.syn.v \
		|| { echo -e "$(FAIL) Missing netlist"; exit 1; }
	@test -s $(COUNTER_RESULT)/synth_stat.txt \
		|| { echo -e "$(FAIL) Missing synth_stat.txt"; exit 1; }
	@echo -e "$(PASS) test-syn-counter"

test-syn-op: ## Synthesize example ALU (op.v)
	@echo "=== TEST: syn op ($(PLATFORM)) ==="
	@make -C $(ROOT_DIR) syn $(OP_ARGS)
	@test -s $(OP_RESULT)/$(OP_DESIGN).netlist.syn.v \
		|| { echo -e "$(FAIL) Missing netlist"; exit 1; }
	@test -s $(OP_RESULT)/synth_stat.txt \
		|| { echo -e "$(FAIL) Missing synth_stat.txt"; exit 1; }
	@test -s $(OP_RESULT)/synth_check.txt \
		|| { echo -e "$(FAIL) Missing synth_check.txt"; exit 1; }
	@echo -e "$(PASS) test-syn-op"

# =====================================================================
#  STA Tests (depend on synthesis)
# =====================================================================
test-sta: test-sta-counter test-sta-op ## STA smoke tests
	@echo -e "$(PASS) All STA tests passed."

test-sta-counter: test-syn-counter ## Run STA on counter
	@echo "=== TEST: sta counter ($(PLATFORM)) ==="
	@make -C $(ROOT_DIR) sta $(COUNTER_ARGS)
	@test -s $(COUNTER_RESULT)/$(COUNTER_DESIGN).netlist.syn.v.sdc \
		|| { echo -e "$(FAIL) Missing .sdc"; exit 1; }
	@test -s $(COUNTER_RESULT)/$(COUNTER_DESIGN).netlist.syn.v.sdf \
		|| { echo -e "$(FAIL) Missing .sdf"; exit 1; }
	@test -s $(COUNTER_RESULT)/sta.log \
		|| { echo -e "$(FAIL) Missing sta.log"; exit 1; }
	@echo -e "$(PASS) test-sta-counter"

test-sta-op: test-syn-op ## Run STA on op.v
	@echo "=== TEST: sta op ($(PLATFORM)) ==="
	@make -C $(ROOT_DIR) sta $(OP_ARGS)
	@test -s $(OP_RESULT)/$(OP_DESIGN).netlist.syn.v.sdc \
		|| { echo -e "$(FAIL) Missing .sdc"; exit 1; }
	@test -s $(OP_RESULT)/$(OP_DESIGN).netlist.syn.v.sdf \
		|| { echo -e "$(FAIL) Missing .sdf"; exit 1; }
	@test -s $(OP_RESULT)/$(OP_DESIGN).netlist.syn.v.timing_model \
		|| { echo -e "$(FAIL) Missing .timing_model"; exit 1; }
	@test -s $(OP_RESULT)/sta.log \
		|| { echo -e "$(FAIL) Missing sta.log"; exit 1; }
	@echo -e "$(PASS) test-sta-op"

# =====================================================================
#  Show / Summary Tests (depend on STA)
# =====================================================================
test-show: test-sta-op ## Test PPA summary report
	@echo "=== TEST: show op ($(PLATFORM)) ==="
	@make -C $(ROOT_DIR) show $(OP_ARGS)
	@echo -e "$(PASS) test-show"

# =====================================================================
#  PnR Tests (depend on STA)
# =====================================================================
test-pnr: test-pnr-counter ## PnR smoke tests
	@echo -e "$(PASS) All PnR tests passed."

test-pnr-counter: test-sta-counter ## Run PnR on counter
	@echo "=== TEST: pnr counter ($(PLATFORM)) ==="
	@make -C $(ROOT_DIR) pnr-fast $(COUNTER_ARGS)
	@test -s $(COUNTER_PNR_RESULT)/$(COUNTER_DESIGN)_final.def \
		|| { echo -e "$(FAIL) Missing _final.def"; exit 1; }
	@test -s $(COUNTER_PNR_RESULT)/$(COUNTER_DESIGN)_final.odb \
		|| { echo -e "$(FAIL) Missing _final.odb"; exit 1; }
	@test -s $(COUNTER_PNR_RESULT)/$(COUNTER_DESIGN)_final.v \
		|| { echo -e "$(FAIL) Missing _final.v"; exit 1; }
	@test -s $(COUNTER_PNR_RESULT)/timing_max_final.rpt \
		|| { echo -e "$(FAIL) Missing timing_max_final.rpt"; exit 1; }
	@test -s $(COUNTER_PNR_RESULT)/timing_min_final.rpt \
		|| { echo -e "$(FAIL) Missing timing_min_final.rpt"; exit 1; }
	@test -s $(COUNTER_PNR_RESULT)/area_final.rpt \
		|| { echo -e "$(FAIL) Missing area_final.rpt"; exit 1; }
	@test -s $(COUNTER_PNR_RESULT)/power_final.rpt \
		|| { echo -e "$(FAIL) Missing power_final.rpt"; exit 1; }
	@echo -e "$(PASS) test-pnr-counter"

# =====================================================================
#  Visualization Tests
# =====================================================================
test-viz: test-viz-arch test-viz-timing test-viz-layout ## Visualization smoke tests
	@echo -e "$(PASS) All visualization tests passed."

test-viz-arch: test-syn-op ## Architecture diagram (dot → svg)
	@echo "=== TEST: viz-arch-dot op ($(PLATFORM)) ==="
	@make -C $(ROOT_DIR) viz-arch-dot $(OP_ARGS)
	@test -s $(OP_RESULT)/$(OP_DESIGN)_arch.dot \
		|| { echo -e "$(FAIL) Missing _arch.dot"; exit 1; }
	@ls $(OP_RESULT)/$(OP_DESIGN)_arch*.svg >/dev/null 2>&1 \
		|| { echo -e "$(FAIL) Missing architecture SVG"; exit 1; }
	@echo -e "$(PASS) test-viz-arch"

test-viz-timing: test-sta-op ## Timing model plots
	@echo "=== TEST: viz-timing op ($(PLATFORM)) ==="
	@make -C $(ROOT_DIR) viz-timing $(OP_ARGS)
	@echo -e "$(PASS) test-viz-timing"

test-viz-layout: test-pnr-counter ## Layout images (Python/matplotlib)
	@echo "=== TEST: viz counter ($(PLATFORM)) ==="
	@make -C $(ROOT_DIR) viz $(COUNTER_ARGS)
	@test -d $(COUNTER_PNR_RESULT)/images \
		|| { echo -e "$(FAIL) Missing images/ directory"; exit 1; }
	@echo -e "$(PASS) test-viz-layout"

test-viz-png: test-pnr-counter ## Export layout PNG (requires xvfb + OpenROAD GUI)
	@echo "=== TEST: viz-png counter ($(PLATFORM)) ==="
	@make -C $(ROOT_DIR) viz-png $(COUNTER_ARGS)
	@test -s $(COUNTER_PNR_RESULT)/$(COUNTER_DESIGN)_final.png \
		|| { echo -e "$(FAIL) Missing _final.png"; exit 1; }
	@echo -e "$(PASS) test-viz-png"

test-viz-label: test-viz-png ## Labeled module overlay (requires viz-png)
	@echo "=== TEST: viz-label counter ($(PLATFORM)) ==="
	@make -C $(ROOT_DIR) viz-label $(COUNTER_ARGS)
	@test -s $(COUNTER_PNR_RESULT)/$(COUNTER_DESIGN)_final.label.png \
		|| { echo -e "$(FAIL) Missing _final.label.png"; exit 1; }
	@echo -e "$(PASS) test-viz-label"

# =====================================================================
#  Full Flow Test (end-to-end: syn → sta → pnr)
# =====================================================================
test-flow: ## Full flow end-to-end on counter
	@echo "=== TEST: flow counter ($(PLATFORM)) ==="
	@make -C $(ROOT_DIR) flow $(COUNTER_ARGS)
	@test -s $(COUNTER_RESULT)/$(COUNTER_DESIGN).netlist.syn.v \
		|| { echo -e "$(FAIL) Missing netlist"; exit 1; }
	@test -s $(COUNTER_RESULT)/sta.log \
		|| { echo -e "$(FAIL) Missing sta.log"; exit 1; }
	@test -s $(COUNTER_PNR_RESULT)/$(COUNTER_DESIGN)_final.def \
		|| { echo -e "$(FAIL) Missing _final.def"; exit 1; }
	@echo -e "$(PASS) test-flow"

# =====================================================================
#  Clean
# =====================================================================
clean: ## Remove test result directories
	-rm -rf $(COUNTER_RESULT) $(COUNTER_PNR_RESULT)
	-rm -rf $(OP_RESULT) $(OP_PNR_RESULT)

clean-all: ## Remove test results for all platforms
	-rm -rf $(ROOT_DIR)/result/*-$(COUNTER_DESIGN)-*
	-rm -rf $(ROOT_DIR)/result/*-$(OP_DESIGN)-*
	@echo "Test results cleaned."

.PHONY: test test-syn test-sta test-show test-pnr test-viz test-flow \
        test-syn-counter test-syn-op \
        test-sta-counter test-sta-op \
        test-pnr-counter \
        test-viz-arch test-viz-timing test-viz-layout test-viz-png test-viz-label \
        clean clean-all
