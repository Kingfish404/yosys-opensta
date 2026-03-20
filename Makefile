PROJ_PATH = $(shell pwd)
NPROC = $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# =====================================================================
#  Platform
# =====================================================================
# Supported: nangate45 (default), asap7
PLATFORM ?= nangate45
PLATFORM_DIR = $(PROJ_PATH)/platforms/$(PLATFORM)
LIB_DIR = $(PROJ_PATH)/lib/$(PLATFORM)

include $(PLATFORM_DIR)/platform.mk

# =====================================================================
#  Design Parameters
# =====================================================================
DESIGN ?= gcd
RTL_FILES ?= $(shell find $(PROJ_PATH)/example -name "*.v")
CLK_PORT_NAME ?= clock
CLK_FREQ_MHZ ?= 50
VERILOG_INCLUDE_DIRS ?= $(PROJ_PATH)/example

# =====================================================================
#  PnR Parameters
# =====================================================================
CORE_UTILIZATION ?= 40
CORE_ASPECT_RATIO ?= 1.0
PLACE_DENSITY ?= 0.60
DR_THREADS ?= 0

# =====================================================================
#  Derived Paths (do not edit)
# =====================================================================
RESULT_DIR = $(PROJ_PATH)/result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz
PNR_RESULT_DIR = $(PROJ_PATH)/result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz-pnr
SCRIPT_DIR = $(PROJ_PATH)/scripts
NETLIST_SYN_V = $(DESIGN).netlist.syn.v
DOT_FORMAT ?= svg

NANGATE45_URL = https://github.com/Kingfish404/yosys-opensta/releases/download/nangate45/nangate45.tar.bz2

# Common environment variables passed to local tools
COMMON_ENV = \
  PROJ_PATH=$(PROJ_PATH) \
  DESIGN=$(DESIGN) \
  CLK_PORT_NAME=$(CLK_PORT_NAME) \
  CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
  RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/ \
  NETLIST_SYN_V=$(NETLIST_SYN_V) \
  PLATFORM=$(PLATFORM)

# Common Docker -e flags
DOCKER_ENV = \
  -e DESIGN=$(DESIGN) \
  -e CLK_PORT_NAME=$(CLK_PORT_NAME) \
  -e CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
  -e RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/ \
  -e NETLIST_SYN_V=$(NETLIST_SYN_V) \
  -e PLATFORM=$(PLATFORM)

# PnR-specific environment (extends COMMON_ENV / DOCKER_ENV)
PNR_ENV = \
  PNR_RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz-pnr \
  CORE_UTILIZATION=$(CORE_UTILIZATION) \
  CORE_ASPECT_RATIO=$(CORE_ASPECT_RATIO) \
  PLACE_DENSITY=$(PLACE_DENSITY) \
  MIN_ROUTING_LAYER=$(MIN_ROUTING_LAYER) \
  MAX_ROUTING_LAYER=$(MAX_ROUTING_LAYER)

PNR_DOCKER_ENV = \
  -e PNR_RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz-pnr \
  -e CORE_UTILIZATION=$(CORE_UTILIZATION) \
  -e CORE_ASPECT_RATIO=$(CORE_ASPECT_RATIO) \
  -e PLACE_DENSITY=$(PLACE_DENSITY) \
  -e MIN_ROUTING_LAYER=$(MIN_ROUTING_LAYER) \
  -e MAX_ROUTING_LAYER=$(MAX_ROUTING_LAYER)

# =====================================================================
#  Default Target — Help
# =====================================================================
.DEFAULT_GOAL := help

help:
	@echo ""
	@echo "yosys-opensta — Open-Source RTL-to-Layout Flow"
	@echo "==============================================="
	@echo ""
	@echo "  Setup:"
	@echo "    make setup              Full local build (CUDD + OpenSTA + yosys-slang + OpenROAD + NanGate45)"
	@echo "    make setup-nangate45    Download NanGate45 PDK data"
	@echo "    make setup-asap7        Download ASAP7 PDK data"
	@echo "    make setup-opensta      Build OpenSTA locally (with CUDD)"
	@echo "    make setup-openroad     Build OpenROAD from source"
	@echo "    make setup-docker       Pull Docker images (OpenSTA + OpenROAD)"
	@echo ""
	@echo "  Synthesis & Timing:"
	@echo "    make syn                Run Yosys synthesis"
	@echo "    make sta                Run OpenSTA timing analysis"
	@echo "    make sta-detail         Detailed timing report (path-level)"
	@echo "    make show               Print synthesis + STA summary"
	@echo ""
	@echo "  Place & Route:"
	@echo "    make pnr                Run OpenROAD place & route"
	@echo "    make pnr-fast           Fast PnR (fewer iterations, multi-threaded)"
	@echo "    make gds                Generate GDS via KLayout"
	@echo ""
	@echo "  Composite Flows:"
	@echo "    make flow               syn → sta → pnr"
	@echo "    make flow-gds           syn → sta → pnr → gds"
	@echo ""
	@echo "  Visualization (after PnR):"
	@echo "    make viz                Layout images via Python/matplotlib"
	@echo "    make viz-openroad       Layout images via OpenROAD (headless)"
	@echo "    make viz-klayout        Layout images via KLayout (headless)"
	@echo "    make viz-timing         Timing model plots (after STA)"
	@echo "    make viz-arch-dot       Architecture diagram (dot/svg)"
	@echo ""
	@echo "  Interactive GUI:"
	@echo "    make gui                Open layout in OpenROAD GUI"
	@echo "    make gui-klayout        Open layout in KLayout GUI"
	@echo ""
	@echo "  Docker Variants (append '-docker' to any flow target):"
	@echo "    make sta-docker / pnr-docker / pnr-fast-docker / viz-openroad-docker"
	@echo ""
	@echo "  Clean:"
	@echo "    make clean              Remove all results"
	@echo "    make clean-pnr          Remove PnR results only"
	@echo ""
	@echo "  Key Variables:"
	@echo "    PLATFORM=$(PLATFORM)  DESIGN=$(DESIGN)  CLK_FREQ_MHZ=$(CLK_FREQ_MHZ)"
	@echo "    CORE_UTILIZATION=$(CORE_UTILIZATION)  PLACE_DENSITY=$(PLACE_DENSITY)"
	@echo ""

# =====================================================================
#  Setup
# =====================================================================
setup: setup-nangate45 setup-opensta setup-openroad
	# Build and install yosys-slang
	git clone --recursive https://github.com/povik/yosys-slang || true
	cd yosys-slang && make -j$(NPROC) && make install
	@echo ">>> Setup complete. Run 'make flow' to test the full flow."

setup-nangate45:
	mkdir -p lib
	wget -O - $(NANGATE45_URL) | tar xfj - -C lib

setup-asap7:
	@echo ">>> Downloading ASAP7 platform files from OpenROAD-flow-scripts ..."
	@rm -rf /tmp/orfs-asap7-download
	git clone --depth 1 --filter=blob:none --sparse \
		https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git \
		/tmp/orfs-asap7-download
	cd /tmp/orfs-asap7-download && git sparse-checkout set flow/platforms/asap7
	@mkdir -p lib/asap7
	cp -r /tmp/orfs-asap7-download/flow/platforms/asap7/lef lib/asap7/
	cp -r /tmp/orfs-asap7-download/flow/platforms/asap7/lib lib/asap7/
	cp -r /tmp/orfs-asap7-download/flow/platforms/asap7/gds lib/asap7/
	cp -r /tmp/orfs-asap7-download/flow/platforms/asap7/verilog lib/asap7/
	cp -r /tmp/orfs-asap7-download/flow/platforms/asap7/yoSys lib/asap7/
	cp -r /tmp/orfs-asap7-download/flow/platforms/asap7/KLayout lib/asap7/ 2>/dev/null || true
	cp /tmp/orfs-asap7-download/flow/platforms/asap7/rcx_patterns.rules lib/asap7/ 2>/dev/null || true
	@rm -rf /tmp/orfs-asap7-download
	# Decompress .lib.gz files
	cd lib/asap7/lib/NLDM && for f in *.lib.gz; do gunzip -fk "$$f" 2>/dev/null; done || true
	cd lib/asap7/lib/CCS  && for f in *.lib.gz; do gunzip -fk "$$f" 2>/dev/null; done || true
	# Create merged liberty for RVT TT corner
	cat lib/asap7/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib \
	    lib/asap7/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib \
	    lib/asap7/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib \
	    lib/asap7/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib \
	    lib/asap7/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib \
	    > lib/asap7/lib/merged.lib
	@echo ">>> ASAP7 platform files ready in lib/asap7/"

setup-opensta:
	# Download and build CUDD
	wget https://raw.githubusercontent.com/davidkebo/cudd/main/cudd_versions/cudd-3.0.0.tar.gz
	tar -xvf cudd-3.0.0.tar.gz
	rm cudd-3.0.0.tar.gz
	cd cudd-3.0.0 && mkdir -p ../cudd && ./configure && make -j$(NPROC)
	# Clone and build OpenSTA
	git clone https://github.com/parallaxsw/OpenSTA.git || true
	cd OpenSTA && cmake -DCUDD_DIR=../cudd-3.0.0 -B build . && cmake --build build -j$(NPROC)

setup-openroad:
	git clone --recursive https://github.com/The-OpenROAD-Project/OpenROAD.git || true
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
	cd OpenROAD && ./etc/Build.sh
else
	# Linux: use the official dependency installer + build script
	cd OpenROAD \
		&& sudo ./etc/DependencyInstaller.sh -base \
		&& ./etc/DependencyInstaller.sh -common -local \
		&& ./etc/Build.sh
endif

setup-docker:
	# Pull pre-built OpenSTA Docker image
	git clone https://github.com/parallaxsw/OpenSTA.git || true
	cd OpenSTA && docker build --file Dockerfile.ubuntu_22.04 --tag opensta .
	# Pull pre-built OpenROAD Docker image
	docker pull openroad/openroad:latest
	docker tag openroad/openroad:latest openroad

# =====================================================================
#  Synthesis
# =====================================================================
syn: $(RESULT_DIR)/$(NETLIST_SYN_V)

$(RESULT_DIR)/$(NETLIST_SYN_V): $(RTL_FILES) $(SCRIPT_DIR)/yosys.tcl
	mkdir -p $(@D)
	export PLATFORM=$(PLATFORM) && \
	echo tcl $(SCRIPT_DIR)/yosys.tcl \
		$(DESIGN) \
		\"$(RTL_FILES)\" \
		\"$(VERILOG_INCLUDE_DIRS)\" \
		$@ | yosys -m slang -l $(@D)/yosys.log -s - | tee $(@D)/yosys.log

# =====================================================================
#  Static Timing Analysis
# =====================================================================
sta: $(RESULT_DIR)/$(NETLIST_SYN_V)
	$(COMMON_ENV) \
	./OpenSTA/build/sta ./scripts/opensta.tcl | tee $(RESULT_DIR)/sta.log

sta-detail: $(RESULT_DIR)/$(NETLIST_SYN_V)
	$(COMMON_ENV) \
	./OpenSTA/build/sta ./scripts/opensta_detail.tcl | tee $(RESULT_DIR)/sta_detail.log

sta-docker: $(RESULT_DIR)/$(NETLIST_SYN_V)
	@docker run -i --rm $(DOCKER_ENV) \
		-v .:/data opensta data/scripts/opensta.tcl | tee $(RESULT_DIR)/sta.log

sta-detail-docker: $(RESULT_DIR)/$(NETLIST_SYN_V)
	@docker run -i --rm $(DOCKER_ENV) \
		-v .:/data opensta data/scripts/opensta_detail.tcl | tee $(RESULT_DIR)/sta_detail.log

show: $(RESULT_DIR)/$(NETLIST_SYN_V)
	@cat $(RESULT_DIR)/sta.log
	@cat $(RESULT_DIR)/synth_stat.txt | grep 'Chip area'

# =====================================================================
#  Place & Route
# =====================================================================
pnr: $(RESULT_DIR)/$(NETLIST_SYN_V)
	@mkdir -p $(PNR_RESULT_DIR)
	$(COMMON_ENV) $(PNR_ENV) \
	./OpenROAD/build/bin/openroad ./scripts/openroad_pnr.tcl \
	| tee $(PNR_RESULT_DIR)/pnr.log

pnr-fast: $(RESULT_DIR)/$(NETLIST_SYN_V)
	@mkdir -p $(PNR_RESULT_DIR)
	$(COMMON_ENV) $(PNR_ENV) DR_THREADS=$(DR_THREADS) \
	./OpenROAD/build/bin/openroad ./scripts/openroad_pnr_fast.tcl \
	| tee $(PNR_RESULT_DIR)/pnr.log

pnr-docker: $(RESULT_DIR)/$(NETLIST_SYN_V)
	@mkdir -p $(PNR_RESULT_DIR)
	@docker run -i --rm $(DOCKER_ENV) $(PNR_DOCKER_ENV) \
		-v .:/data openroad /data/scripts/openroad_pnr.tcl \
		| tee $(PNR_RESULT_DIR)/pnr.log

pnr-fast-docker: $(RESULT_DIR)/$(NETLIST_SYN_V)
	@mkdir -p $(PNR_RESULT_DIR)
	@docker run -i --rm $(DOCKER_ENV) $(PNR_DOCKER_ENV) \
		-e DR_THREADS=$(DR_THREADS) \
		-v .:/data openroad /data/scripts/openroad_pnr_fast.tcl \
		| tee $(PNR_RESULT_DIR)/pnr.log

# =====================================================================
#  GDS Generation
# =====================================================================
gds: $(PNR_RESULT_DIR)/$(DESIGN)_final.def
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
flow: syn sta pnr
	@echo "=== Flow complete: syn → sta → pnr ==="
	@echo "=== Results: $(RESULT_DIR)/  $(PNR_RESULT_DIR)/ ==="

flow-gds: syn sta pnr gds
	@echo "=== RTL-to-GDS complete ==="
	@echo "=== GDS: $(PNR_RESULT_DIR)/$(DESIGN)_final.gds ==="

# =====================================================================
#  Visualization
# =====================================================================
viz: $(PNR_RESULT_DIR)/$(DESIGN)_final.def
	@echo "=== Generating layout images via Python ==="
	python3 $(SCRIPT_DIR)/viz_layout.py $(PNR_RESULT_DIR) \
		--design $(DESIGN) --format svg
	@echo "=== Layout images in $(PNR_RESULT_DIR)/images/ ==="

viz-openroad: $(PNR_RESULT_DIR)/$(DESIGN)_final.def
	@echo "=== Generating layout images via OpenROAD ==="
	$(COMMON_ENV) \
	PNR_RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz-pnr \
	xvfb-run -a ./OpenROAD/build/bin/openroad -gui -exit \
		./scripts/openroad_viz.tcl \
		| tee $(PNR_RESULT_DIR)/viz_layout.log
	@echo "=== Layout images in $(PNR_RESULT_DIR)/images/ ==="

viz-openroad-docker: $(PNR_RESULT_DIR)/$(DESIGN)_final.def
	@echo "=== Generating layout images via OpenROAD (Docker) ==="
	@docker run -i --rm \
		-e DESIGN=$(DESIGN) \
		-e PNR_RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz-pnr \
		-e PLATFORM=$(PLATFORM) \
		-v .:/data openroad \
		xvfb-run -a openroad -gui -exit /data/scripts/openroad_viz.tcl \
		| tee $(PNR_RESULT_DIR)/viz_layout.log
	@echo "=== Layout images in $(PNR_RESULT_DIR)/images/ ==="

viz-klayout: $(PNR_RESULT_DIR)/$(DESIGN)_final.def
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

viz-timing: $(RESULT_DIR)/$(NETLIST_SYN_V).timing_model
	@echo "=== Visualizing timing model ==="
	python3 $(SCRIPT_DIR)/viz-timing-model.py \
		$(RESULT_DIR)/$(NETLIST_SYN_V).timing_model \
		-o $(RESULT_DIR)
	@echo "=== Timing plots in $(RESULT_DIR)/ ==="

viz-arch-dot: $(RESULT_DIR)/$(NETLIST_SYN_V)
	@echo "=== Generating architecture diagram ==="
	python3 $(SCRIPT_DIR)/gen-arch.py $(RESULT_DIR)/$(DESIGN)_hier.json \
		-t $(DESIGN) -o $(RESULT_DIR)/$(DESIGN)_arch.dot \
		-l $(PLATFORM_MERGED_LIB) \
		-s $(RESULT_DIR)/$(DESIGN)_syn.json
	python3 $(SCRIPT_DIR)/gen-dot.py -f $(DOT_FORMAT) $(RESULT_DIR)/$(DESIGN)_arch.dot
	@echo "=== Diagrams generated in $(RESULT_DIR)/ ==="

# =====================================================================
#  Interactive GUI
# =====================================================================
gui: $(PNR_RESULT_DIR)/$(DESIGN)_final.odb
	@echo "=== Opening layout in OpenROAD GUI ==="
	cd $(PROJ_PATH) && ./OpenROAD/build/bin/openroad -gui <<< "\
		read_lef $(PLATFORM_TECH_LEF); \
		read_lef $(PLATFORM_SC_LEF); \
		read_db $(PNR_RESULT_DIR)/$(DESIGN)_final.odb"

gui-klayout: $(PNR_RESULT_DIR)/$(DESIGN)_final.def
	@echo "=== Opening layout in KLayout ==="
	klayout -e \
		-t $(PLATFORM_KLAYOUT_TECH) \
		$(if $(PLATFORM_KLAYOUT_LYP),-l $(PLATFORM_KLAYOUT_LYP)) \
		$(PNR_RESULT_DIR)/$(DESIGN)_final.def

# =====================================================================
#  Clean
# =====================================================================
clean:
	-rm -rf result/

clean-pnr:
	-rm -rf $(PNR_RESULT_DIR)/

# =====================================================================
#  .PHONY
# =====================================================================
.PHONY: help \
        setup setup-nangate45 setup-asap7 setup-opensta setup-openroad setup-docker \
        syn sta sta-detail sta-docker sta-detail-docker show \
        pnr pnr-fast pnr-docker pnr-fast-docker gds \
        flow flow-gds \
        viz viz-openroad viz-openroad-docker viz-klayout viz-timing viz-arch-dot \
        gui gui-klayout \
        clean clean-pnr
