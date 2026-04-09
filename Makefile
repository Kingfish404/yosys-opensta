PROJ_PATH = $(shell pwd)
NPROC = $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# Ensure pipe failures propagate (e.g. cmd | tee returns cmd's exit code)
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

# =====================================================================
#  Platform
# =====================================================================
# Supported: nangate45 (default), asap7
PLATFORM ?= nangate45## Target platform: nangate45, asap7
PLATFORM_DIR = $(PROJ_PATH)/platforms/$(PLATFORM)
THIRD_PARTY_DIR = $(PROJ_PATH)/third_party
LIB_DIR = $(THIRD_PARTY_DIR)/lib/$(PLATFORM)

include $(PLATFORM_DIR)/platform.mk

# =====================================================================
#  Design Parameters
# =====================================================================
DESIGN ?= op## Top-level design module name
RTL_FILES ?= $(shell find $(PROJ_PATH)/example -name "*.v")## RTL source files
CLK_PORT_NAME ?= clock## Clock port name in the design
CLK_FREQ_MHZ ?= 50## Target clock frequency (MHz)
VERILOG_INCLUDE_DIRS ?= $(PROJ_PATH)/example## Verilog include search paths
ABC_SCRIPT ?=## ABC optimization script override (empty=default)
SYNTH_HIERARCHICAL ?= 0## Hierarchical synthesis (0=flat, 1=preserve hierarchy)

# =====================================================================
#  PnR Parameters
# =====================================================================
CORE_UTILIZATION ?= 40## Core area utilization (%)
CORE_ASPECT_RATIO ?= 1.0## Core aspect ratio (W/H)
PLACE_DENSITY ?= 0.60## Placement density (0.0-1.0)
DR_THREADS ?= 0## Detailed routing threads (0=auto)
PIN_CONSTRAINT_FILE ?=## Pin constraint TCL file (optional)
PNR_RESUME_FROM ?=## Resume PnR from stage (floorplan|place|cts|route|finish)

# =====================================================================
#  Derived Paths (do not edit)
# =====================================================================
RESULT_DIR = $(PROJ_PATH)/result/$(PLATFORM)-$(DESIGN)-$(CLK_FREQ_MHZ)MHz
PNR_RESULT_DIR = $(PROJ_PATH)/result/$(PLATFORM)-$(DESIGN)-$(CLK_FREQ_MHZ)MHz-pnr
SCRIPT_DIR = $(PROJ_PATH)/scripts
NETLIST_SYN_V = $(DESIGN).netlist.syn.v
DOT_FORMAT ?= svg## Architecture diagram format: svg, pdf, png

NANGATE45_URL = https://github.com/Kingfish404/yosys-opensta/releases/download/nangate45/nangate45.tar.bz2

# Tool paths (override if installed elsewhere)
OPENSTA_BIN ?= $(PROJ_PATH)/third_party/OpenSTA/build/sta
OPENROAD_BIN ?= $(shell command -v openroad 2>/dev/null || echo $(PROJ_PATH)/third_party/OpenROAD/build/bin/openroad)

# Common environment variables passed to local tools
COMMON_ENV = \
  PROJ_PATH=$(PROJ_PATH) \
  DESIGN=$(DESIGN) \
  CLK_PORT_NAME=$(CLK_PORT_NAME) \
  CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
  RESULT_DIR=result/$(PLATFORM)-$(DESIGN)-$(CLK_FREQ_MHZ)MHz/ \
  NETLIST_SYN_V=$(NETLIST_SYN_V) \
  PLATFORM=$(PLATFORM)

# Common Docker -e flags
DOCKER_ENV = \
  -e DESIGN=$(DESIGN) \
  -e CLK_PORT_NAME=$(CLK_PORT_NAME) \
  -e CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
  -e RESULT_DIR=result/$(PLATFORM)-$(DESIGN)-$(CLK_FREQ_MHZ)MHz/ \
  -e NETLIST_SYN_V=$(NETLIST_SYN_V) \
  -e PLATFORM=$(PLATFORM)

# PnR-specific environment (extends COMMON_ENV / DOCKER_ENV)
PNR_ENV = \
  PNR_RESULT_DIR=result/$(PLATFORM)-$(DESIGN)-$(CLK_FREQ_MHZ)MHz-pnr \
  CORE_UTILIZATION=$(CORE_UTILIZATION) \
  CORE_ASPECT_RATIO=$(CORE_ASPECT_RATIO) \
  PLACE_DENSITY=$(PLACE_DENSITY) \
  MIN_ROUTING_LAYER=$(MIN_ROUTING_LAYER) \
  MAX_ROUTING_LAYER=$(MAX_ROUTING_LAYER) \
  PIN_CONSTRAINT_FILE=$(PIN_CONSTRAINT_FILE) \
  PNR_RESUME_FROM=$(PNR_RESUME_FROM)

PNR_DOCKER_ENV = \
  -e PNR_RESULT_DIR=result/$(PLATFORM)-$(DESIGN)-$(CLK_FREQ_MHZ)MHz-pnr \
  -e CORE_UTILIZATION=$(CORE_UTILIZATION) \
  -e CORE_ASPECT_RATIO=$(CORE_ASPECT_RATIO) \
  -e PLACE_DENSITY=$(PLACE_DENSITY) \
  -e MIN_ROUTING_LAYER=$(MIN_ROUTING_LAYER) \
  -e MAX_ROUTING_LAYER=$(MAX_ROUTING_LAYER) \
  -e PIN_CONSTRAINT_FILE=$(PIN_CONSTRAINT_FILE) \
  -e PNR_RESUME_FROM=$(PNR_RESUME_FROM)

# =====================================================================
#  Default Target — Help
# =====================================================================
.DEFAULT_GOAL := help

help: ## Show this help message
	@echo "Usage: make <target> [VAR=value ...]"
	@awk '\
		BEGIN { state=0; pending=""; first_target=1 } \
		/^# =+$$/ { \
			if (state==0) state=1; \
			else if (state==2) { pending=section; state=0 } \
			else state=0; next } \
		state==1 && /^# .+/ { section=substr($$0,3); state=2; next } \
		{ if (state==1) state=0 } \
		/^[a-zA-Z0-9_-]+:.*## / { \
			if (pending!="") { printf "\n%s:\n", pending; pending="" } \
			else if (first_target) printf "\nTargets:\n"; \
			first_target=0; \
			target=$$0; sub(/:.*/, "", target); \
			desc=$$0; sub(/.*## /, "", desc); \
			printf "  %-20s %s\n", target, desc }' $(MAKEFILE_LIST)
	@echo ""
	@echo "Variables (override with VAR=value):"
	@grep -hE '^[A-Z_]+\s*\?=' $(MAKEFILE_LIST) | \
		awk '{ \
			if (match($$0, /## /)) { \
				name=$$0; sub(/\s*\?=.*/, "", name); \
				desc=substr($$0, RSTART+3); \
				printf "  %-20s %s\n", name, desc } \
			else { \
				split($$0, a, "\\?="); \
				gsub(/^[ \t]+|[ \t]+$$/, "", a[1]); gsub(/^[ \t]+|[ \t]+$$/, "", a[2]); \
				printf "  %-20s %s\n", a[1], a[2] } }'
	@echo ""

# =====================================================================
#  Setup
# =====================================================================
setup: setup-nangate45 setup-asap7 setup-opensta setup-openroad ## Full local build (CUDD + OpenSTA + yosys-slang + OpenROAD)

setup-nangate45: ## Download NanGate45 PDK data
	mkdir -p third_party/lib
	wget -O - $(NANGATE45_URL) | tar xfj - -C third_party/lib

setup-asap7: ## Download ASAP7 PDK data
	@echo ">>> Downloading ASAP7 platform files from OpenROAD-flow-scripts ..."
	@rm -rf /tmp/orfs-asap7-download
	git clone --depth 1 --filter=blob:none --sparse \
		https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git \
		/tmp/orfs-asap7-download
	cd /tmp/orfs-asap7-download && git sparse-checkout set flow/platforms/asap7
	@mkdir -p third_party/lib/asap7
	cp -r /tmp/orfs-asap7-download/flow/platforms/asap7/lef third_party/lib/asap7/
	cp -r /tmp/orfs-asap7-download/flow/platforms/asap7/lib third_party/lib/asap7/
	cp -r /tmp/orfs-asap7-download/flow/platforms/asap7/gds third_party/lib/asap7/
	cp -r /tmp/orfs-asap7-download/flow/platforms/asap7/verilog third_party/lib/asap7/
	cp -r /tmp/orfs-asap7-download/flow/platforms/asap7/yoSys third_party/lib/asap7/
	cp -r /tmp/orfs-asap7-download/flow/platforms/asap7/KLayout third_party/lib/asap7/ 2>/dev/null || true
	cp /tmp/orfs-asap7-download/flow/platforms/asap7/rcx_patterns.rules third_party/lib/asap7/ 2>/dev/null || true
	@rm -rf /tmp/orfs-asap7-download
	# Decompress .lib.gz files
	cd third_party/lib/asap7/lib/NLDM && for f in *.lib.gz; do gunzip -fk "$$f" 2>/dev/null; done || true
	cd third_party/lib/asap7/lib/CCS  && for f in *.lib.gz; do gunzip -fk "$$f" 2>/dev/null; done || true
	# Create merged liberty for RVT TT corner
	cat third_party/lib/asap7/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib \
	    third_party/lib/asap7/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib \
	    third_party/lib/asap7/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib \
	    third_party/lib/asap7/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib \
	    third_party/lib/asap7/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib \
	    > third_party/lib/asap7/lib/merged.lib
	@echo ">>> ASAP7 platform files ready in third_party/lib/asap7/"

setup-opensta: ## Build OpenSTA locally (with CUDD)
	# Download and build CUDD
	mkdir -p third_party
	wget -O third_party/cudd-3.0.0.tar.gz https://raw.githubusercontent.com/davidkebo/cudd/main/cudd_versions/cudd-3.0.0.tar.gz
	tar -xvf third_party/cudd-3.0.0.tar.gz -C third_party
	rm third_party/cudd-3.0.0.tar.gz
	cd third_party/cudd-3.0.0 && mkdir -p ../cudd && ./configure && make -j$(NPROC)
	# Clone and build OpenSTA
	git clone https://github.com/parallaxsw/OpenSTA.git third_party/OpenSTA || true
	cd third_party/OpenSTA && cmake -DCUDD_DIR=../cudd-3.0.0 -B build . && cmake --build build -j$(NPROC)
	# Build and install yosys-slang
	git clone --recursive https://github.com/povik/yosys-slang || true
	cd yosys-slang && make -j$(NPROC) && make install
	@echo ">>> Setup complete. Run 'make flow' to test the full flow."

setup-openroad: ## Build OpenROAD from source
	git clone --recursive https://github.com/The-OpenROAD-Project/OpenROAD.git third_party/OpenROAD || true
ifeq ($(shell uname -s),Darwin)
	# macOS: install dependencies via Homebrew
	brew install bison boost cmake eigen flex fmt groff libomp or-tools \
		pkg-config python spdlog tcl-tk zlib swig yaml-cpp googletest || true
	# lemon-graph: build from source (Homebrew tap is broken with newer cmake)
	@if ! pkg-config --exists lemon 2>/dev/null && \
	   ! [ -f /opt/homebrew/include/lemon/core.h ] ; then \
		echo ">>> Building lemon-graph from source ..." ; \
		cd /tmp && rm -rf lemon-1.3.1 && \
		wget -q https://lemon.cs.elte.hu/pub/sources/lemon-1.3.1.tar.gz && \
		tar xzf lemon-1.3.1.tar.gz && cd lemon-1.3.1 && \
		sed -i '' 's/CMAKE_MINIMUM_REQUIRED(VERSION 2.8)/cmake_minimum_required(VERSION 3.14)/' CMakeLists.txt && \
		sed -i '' 's/CMAKE_POLICY(SET CMP0048 OLD)//' CMakeLists.txt && \
		sed -i '' 's/^SET(PROJECT_NAME "LEMON")/project(LEMON VERSION 1.3.1 LANGUAGES C CXX)/' CMakeLists.txt && \
		cmake -DCMAKE_INSTALL_PREFIX=/opt/homebrew -B build . && \
		cmake --build build -j$(NPROC) && \
		sudo cmake --install build && \
		rm -rf /tmp/lemon-1.3.1 /tmp/lemon-1.3.1.tar.gz ; \
	else echo ">>> lemon-graph already installed, skipping." ; fi
	cd third_party/OpenROAD && ./etc/Build.sh
else
	# Linux: use the official dependency installer + build script
	cd third_party/OpenROAD \
		&& sudo ./etc/DependencyInstaller.sh -base \
		&& ./etc/DependencyInstaller.sh -common -local \
		&& sed -i 's/ABSL_ROOT/absl_ROOT/g' etc/openroad_deps_prefixes.txt \
		&& ./etc/Build.sh -cmake='-DCUDD_DIR=$(HOME)/.local'
endif

setup-docker: ## Pull Docker images (OpenSTA + OpenROAD)
	# Pull pre-built OpenSTA Docker image
	git clone https://github.com/parallaxsw/OpenSTA.git third_party/OpenSTA || true
	cd third_party/OpenSTA && docker build --file Dockerfile.ubuntu_22.04 --tag opensta .
	# Pull pre-built OpenROAD Docker image
	docker pull openroad/openroad:latest
	docker tag openroad/openroad:latest openroad

# =====================================================================
#  Synthesis
# =====================================================================
syn: $(RESULT_DIR)/$(NETLIST_SYN_V) ## Run Yosys synthesis

$(RESULT_DIR)/$(NETLIST_SYN_V): $(RTL_FILES) $(SCRIPT_DIR)/yosys.tcl
	mkdir -p $(@D)
	export PLATFORM=$(PLATFORM) \
	  ABC_SCRIPT="$(ABC_SCRIPT)" \
	  SYNTH_HIERARCHICAL=$(SYNTH_HIERARCHICAL) && \
	echo tcl $(SCRIPT_DIR)/yosys.tcl \
		$(DESIGN) \
		\"$(RTL_FILES)\" \
		\"$(VERILOG_INCLUDE_DIRS)\" \
		$@ | yosys -m slang -s - 2>&1 | tee $(@D)/yosys.log

# =====================================================================
#  Static Timing Analysis
# =====================================================================
sta: $(RESULT_DIR)/$(NETLIST_SYN_V) ## Run OpenSTA timing analysis
	$(COMMON_ENV) \
	$(OPENSTA_BIN) -exit ./scripts/opensta.tcl | tee $(RESULT_DIR)/sta.log

sta-detail: $(RESULT_DIR)/$(NETLIST_SYN_V) ## Detailed timing report (path-level)
	$(COMMON_ENV) \
	$(OPENSTA_BIN) -exit ./scripts/opensta_detail.tcl | tee $(RESULT_DIR)/sta_detail.log

sta-docker: $(RESULT_DIR)/$(NETLIST_SYN_V) ## Run OpenSTA via Docker
	@docker run -i --rm $(DOCKER_ENV) \
		-v .:/data opensta -exit data/scripts/opensta.tcl | tee $(RESULT_DIR)/sta.log

sta-detail-docker: $(RESULT_DIR)/$(NETLIST_SYN_V) ## Detailed timing report via Docker
	@docker run -i --rm $(DOCKER_ENV) \
		-v .:/data opensta -exit data/scripts/opensta_detail.tcl | tee $(RESULT_DIR)/sta_detail.log

show: $(RESULT_DIR)/$(NETLIST_SYN_V) ## PPA summary report (formatted)
	@python3 $(SCRIPT_DIR)/ppa_summary.py $(RESULT_DIR) --platform $(PLATFORM) --design $(DESIGN)

summary: $(RESULT_DIR)/$(NETLIST_SYN_V) ## PPA report + save to result dir
	@python3 $(SCRIPT_DIR)/ppa_summary.py $(RESULT_DIR) --platform $(PLATFORM) --design $(DESIGN) --save

summary-json: $(RESULT_DIR)/$(NETLIST_SYN_V) ## PPA report as JSON + save
	@python3 $(SCRIPT_DIR)/ppa_summary.py $(RESULT_DIR) --platform $(PLATFORM) --design $(DESIGN) --json --save

show-raw: $(RESULT_DIR)/$(NETLIST_SYN_V) ## Print raw STA log + area
	@cat $(RESULT_DIR)/sta.log
	@cat $(RESULT_DIR)/synth_stat.txt | grep 'Chip area'

# =====================================================================
#  Place & Route
# =====================================================================
pnr: $(RESULT_DIR)/$(NETLIST_SYN_V) ## Run OpenROAD place & route
	@mkdir -p $(PNR_RESULT_DIR)
	@test -x "$(OPENROAD_BIN)" || { echo "Error: openroad not found at $(OPENROAD_BIN). Run 'make setup-openroad' or set OPENROAD_BIN."; exit 1; }
	$(COMMON_ENV) $(PNR_ENV) \
	$(OPENROAD_BIN) -exit ./scripts/openroad_pnr.tcl \
	| tee $(PNR_RESULT_DIR)/pnr.log

pnr-fast: $(RESULT_DIR)/$(NETLIST_SYN_V) ## Fast PnR (fewer iterations, multi-threaded)
	@mkdir -p $(PNR_RESULT_DIR)
	@test -x "$(OPENROAD_BIN)" || { echo "Error: openroad not found at $(OPENROAD_BIN). Run 'make setup-openroad' or set OPENROAD_BIN."; exit 1; }
	$(COMMON_ENV) $(PNR_ENV) DR_THREADS=$(DR_THREADS) \
	$(OPENROAD_BIN) -exit ./scripts/openroad_pnr_fast.tcl \
	| tee $(PNR_RESULT_DIR)/pnr.log

pnr-docker: $(RESULT_DIR)/$(NETLIST_SYN_V) ## Run PnR via Docker
	@mkdir -p $(PNR_RESULT_DIR)
	@docker run -i --rm $(DOCKER_ENV) $(PNR_DOCKER_ENV) \
		-v .:/data openroad -exit /data/scripts/openroad_pnr.tcl \
		| tee $(PNR_RESULT_DIR)/pnr.log

pnr-fast-docker: $(RESULT_DIR)/$(NETLIST_SYN_V) ## Fast PnR via Docker
	@mkdir -p $(PNR_RESULT_DIR)
	@docker run -i --rm $(DOCKER_ENV) $(PNR_DOCKER_ENV) \
		-e DR_THREADS=$(DR_THREADS) \
		-v .:/data openroad -exit /data/scripts/openroad_pnr_fast.tcl \
		| tee $(PNR_RESULT_DIR)/pnr.log

# Per-stage PnR targets (resume from a specific stage)
pnr-from-place: $(RESULT_DIR)/$(NETLIST_SYN_V) ## Resume PnR from placement
	@mkdir -p $(PNR_RESULT_DIR)
	@test -x "$(OPENROAD_BIN)" || { echo "Error: openroad not found at $(OPENROAD_BIN). Run 'make setup-openroad' or set OPENROAD_BIN."; exit 1; }
	$(COMMON_ENV) $(PNR_ENV) PNR_RESUME_FROM=place \
	$(OPENROAD_BIN) -exit ./scripts/openroad_pnr.tcl \
	| tee $(PNR_RESULT_DIR)/pnr.log

pnr-from-cts: $(RESULT_DIR)/$(NETLIST_SYN_V) ## Resume PnR from CTS
	@mkdir -p $(PNR_RESULT_DIR)
	@test -x "$(OPENROAD_BIN)" || { echo "Error: openroad not found at $(OPENROAD_BIN). Run 'make setup-openroad' or set OPENROAD_BIN."; exit 1; }
	$(COMMON_ENV) $(PNR_ENV) PNR_RESUME_FROM=cts \
	$(OPENROAD_BIN) -exit ./scripts/openroad_pnr.tcl \
	| tee $(PNR_RESULT_DIR)/pnr.log

pnr-from-route: $(RESULT_DIR)/$(NETLIST_SYN_V) ## Resume PnR from routing
	@mkdir -p $(PNR_RESULT_DIR)
	@test -x "$(OPENROAD_BIN)" || { echo "Error: openroad not found at $(OPENROAD_BIN). Run 'make setup-openroad' or set OPENROAD_BIN."; exit 1; }
	$(COMMON_ENV) $(PNR_ENV) PNR_RESUME_FROM=route \
	$(OPENROAD_BIN) -exit ./scripts/openroad_pnr.tcl \
	| tee $(PNR_RESULT_DIR)/pnr.log

pnr-from-finish: $(RESULT_DIR)/$(NETLIST_SYN_V) ## Resume PnR from finish (reports only)
	@mkdir -p $(PNR_RESULT_DIR)
	@test -x "$(OPENROAD_BIN)" || { echo "Error: openroad not found at $(OPENROAD_BIN). Run 'make setup-openroad' or set OPENROAD_BIN."; exit 1; }
	$(COMMON_ENV) $(PNR_ENV) PNR_RESUME_FROM=finish \
	$(OPENROAD_BIN) -exit ./scripts/openroad_pnr.tcl \
	| tee $(PNR_RESULT_DIR)/pnr.log

# =====================================================================
#  GDS Generation
# =====================================================================
gds: $(PNR_RESULT_DIR)/$(DESIGN)_final.def ## Generate GDS via KLayout
	@echo "=== Generating GDS via KLayout ==="
	QT_QPA_PLATFORM=offscreen klayout -z -r $(SCRIPT_DIR)/klayout_gds_merge.py \
		-rd def_file=$(PNR_RESULT_DIR)/$(DESIGN)_final.def \
		-rd cell_gds=$(PLATFORM_CELL_GDS) \
		-rd tech_lef=$(PLATFORM_TECH_LEF) \
		-rd cell_lef=$(PLATFORM_SC_LEF) \
		-rd tech_file=$(PLATFORM_KLAYOUT_TECH) \
		-rd out_gds=$(PNR_RESULT_DIR)/$(DESIGN)_final.gds \
		-rd design=$(DESIGN)
	@echo "=== GDS written: $(PNR_RESULT_DIR)/$(DESIGN)_final.gds ==="

# =====================================================================
#  Composite Flows
# =====================================================================
flow: syn sta pnr ## Complete flow: syn -> sta -> pnr
	@echo "=== Flow complete: syn → sta → pnr ==="
	@echo "=== Results: $(RESULT_DIR)/  $(PNR_RESULT_DIR)/ ==="

flow-gds: syn sta pnr gds ## RTL-to-GDS: syn -> sta -> pnr -> gds
	@echo "=== RTL-to-GDS complete ==="
	@echo "=== GDS: $(PNR_RESULT_DIR)/$(DESIGN)_final.gds ==="

# =====================================================================
#  Visualization
# =====================================================================
viz: $(PNR_RESULT_DIR)/$(DESIGN)_final.def ## Layout images via Python/matplotlib
	@echo "=== Generating layout images via Python ==="
	python3 $(SCRIPT_DIR)/viz_layout.py $(PNR_RESULT_DIR) \
		--design $(DESIGN) --format svg
	@echo "=== Layout images in $(PNR_RESULT_DIR)/images/ ==="

viz-openroad: $(PNR_RESULT_DIR)/$(DESIGN)_final.def ## Layout images via OpenROAD (headless)
	@echo "=== Generating layout images via OpenROAD ==="
	$(COMMON_ENV) \
	PNR_RESULT_DIR=result/$(PLATFORM)-$(DESIGN)-$(CLK_FREQ_MHZ)MHz-pnr \
	xvfb-run -a $(OPENROAD_BIN) -gui -exit \
		./scripts/openroad_viz.tcl \
		| tee $(PNR_RESULT_DIR)/viz_layout.log
	@echo "=== Layout images in $(PNR_RESULT_DIR)/images/ ==="

viz-openroad-docker: $(PNR_RESULT_DIR)/$(DESIGN)_final.def ## Layout images via OpenROAD (Docker)
	@echo "=== Generating layout images via OpenROAD (Docker) ==="
	@docker run -i --rm \
		-e DESIGN=$(DESIGN) \
		-e PNR_RESULT_DIR=result/$(PLATFORM)-$(DESIGN)-$(CLK_FREQ_MHZ)MHz-pnr \
		-e PLATFORM=$(PLATFORM) \
		-v .:/data openroad \
		xvfb-run -a openroad -gui -exit /data/scripts/openroad_viz.tcl \
		| tee $(PNR_RESULT_DIR)/viz_layout.log
	@echo "=== Layout images in $(PNR_RESULT_DIR)/images/ ==="

viz-klayout: $(PNR_RESULT_DIR)/$(DESIGN)_final.def ## Layout images via KLayout (headless)
	@echo "=== Generating layout images via KLayout ==="
	QT_QPA_PLATFORM=offscreen klayout -z -r $(SCRIPT_DIR)/viz_layout_klayout.py \
		-rd def_file=$(PNR_RESULT_DIR)/$(DESIGN)_final.def \
		-rd tech_lef=$(PLATFORM_TECH_LEF) \
		-rd cell_lef=$(PLATFORM_SC_LEF) \
		-rd tech_file=$(PLATFORM_KLAYOUT_TECH) \
		-rd lyp_file=$(PLATFORM_KLAYOUT_LYP) \
		-rd out_dir=$(PNR_RESULT_DIR)/images \
		-rd design=$(DESIGN)
	@echo "=== Layout images in $(PNR_RESULT_DIR)/images/ ==="

viz-timing: $(RESULT_DIR)/$(NETLIST_SYN_V).timing_model ## Timing model plots (after STA)
	@echo "=== Visualizing timing model ==="
	python3 $(SCRIPT_DIR)/viz-timing-model.py \
		$(RESULT_DIR)/$(NETLIST_SYN_V).timing_model \
		-o $(RESULT_DIR)
	@echo "=== Timing plots in $(RESULT_DIR)/ ==="

viz-arch-dot: $(RESULT_DIR)/$(NETLIST_SYN_V) ## Architecture diagram (dot/svg)
	@echo "=== Generating architecture diagram ==="
	python3 $(SCRIPT_DIR)/gen-arch.py $(RESULT_DIR)/$(DESIGN)_hier.json \
		-t $(DESIGN) -o $(RESULT_DIR)/$(DESIGN)_arch.dot \
		-l $(PLATFORM_MERGED_LIB) \
		-s $(RESULT_DIR)/$(DESIGN)_syn.json
	python3 $(SCRIPT_DIR)/gen-dot.py -f $(DOT_FORMAT) $(RESULT_DIR)/$(DESIGN)_arch.dot
	@echo "=== Diagrams generated in $(RESULT_DIR)/ ==="

viz-png: $(PNR_RESULT_DIR)/$(DESIGN)_final.odb ## Export ODB layout as PNG
	@echo "=== Exporting layout PNG via OpenROAD ==="
	ODB=$(PNR_RESULT_DIR)/$(DESIGN)_final.odb \
	xvfb-run -a $(OPENROAD_BIN) -gui -exit \
		$(SCRIPT_DIR)/export_odb_webp.tcl
	@echo "=== Saved: $(PNR_RESULT_DIR)/$(DESIGN)_final.png ==="

viz-label: $(PNR_RESULT_DIR)/$(DESIGN)_final.png ## Labeled module overlay on layout PNG
	@echo "=== Generating labeled module layout ==="
	python3 $(SCRIPT_DIR)/viz_label_modules.py \
		--syn-json  $(RESULT_DIR)/$(DESIGN)_syn.json \
		--hier-json $(RESULT_DIR)/$(DESIGN)_hier.json \
		--netlist-v $(RESULT_DIR)/$(DESIGN).netlist.syn.v \
		--def-file  $(PNR_RESULT_DIR)/$(DESIGN)_final.def \
		--base-png  $(PNR_RESULT_DIR)/$(DESIGN)_final.png \
		-o          $(PNR_RESULT_DIR)/$(DESIGN)_final.label.png
	@echo "=== Saved: $(PNR_RESULT_DIR)/$(DESIGN)_final.label.png ==="

# =====================================================================
#  Interactive GUI
# =====================================================================
gui: $(PNR_RESULT_DIR)/$(DESIGN)_final.odb ## Open layout in OpenROAD GUI
	@echo "=== Opening layout in OpenROAD GUI ==="
	cd $(PROJ_PATH) && $(OPENROAD_BIN) -gui <<< "\
		read_lef $(PLATFORM_TECH_LEF); \
		read_lef $(PLATFORM_SC_LEF); \
		read_db $(PNR_RESULT_DIR)/$(DESIGN)_final.odb"

gui-klayout: $(PNR_RESULT_DIR)/$(DESIGN)_final.def ## Open layout in KLayout GUI
	@echo "=== Opening layout in KLayout ==="
	klayout -e \
		-t $(PLATFORM_KLAYOUT_TECH) \
		$(if $(PLATFORM_KLAYOUT_LYP),-l $(PLATFORM_KLAYOUT_LYP)) \
		$(PNR_RESULT_DIR)/$(DESIGN)_final.def

# =====================================================================
#  Tests
# =====================================================================
test: ## Run all smoke tests (syn + sta + pnr + viz)
	@$(MAKE) -C tests test PLATFORM=$(PLATFORM)

test-syn: ## Run synthesis tests only
	@$(MAKE) -C tests test-syn PLATFORM=$(PLATFORM)

test-sta: ## Run STA tests only
	@$(MAKE) -C tests test-sta PLATFORM=$(PLATFORM)

test-pnr: ## Run PnR tests only
	@$(MAKE) -C tests test-pnr PLATFORM=$(PLATFORM)

test-viz: ## Run visualization tests only
	@$(MAKE) -C tests test-viz PLATFORM=$(PLATFORM)

test-flow: ## Run full flow end-to-end test
	@$(MAKE) -C tests test-flow PLATFORM=$(PLATFORM)

# =====================================================================
#  Clean
# =====================================================================
clean: ## Remove all results
	-rm -rf result/

clean-pnr: ## Remove PnR results only
	-rm -rf $(PNR_RESULT_DIR)/

# =====================================================================
#  .PHONY
# =====================================================================
.PHONY: help \
        setup setup-nangate45 setup-asap7 setup-opensta setup-openroad setup-docker \
        syn sta sta-detail sta-docker sta-detail-docker show show-raw summary summary-json \
        pnr pnr-fast pnr-docker pnr-fast-docker \
        pnr-from-place pnr-from-cts pnr-from-route pnr-from-finish \
        gds \
        flow flow-gds \
        viz viz-openroad viz-openroad-docker viz-klayout viz-timing viz-arch-dot viz-png viz-label \
        gui gui-klayout \
        test test-syn test-sta test-pnr test-viz test-flow \
        clean clean-pnr
