PROJ_PATH = $(shell pwd)

NANGATE45_URL="https://github.com/Kingfish404/yosys-opensta/releases/download/nangate45/nangate45.tar.bz2"

DESIGN ?= gcd
RTL_FILES ?= $(shell find $(PROJ_PATH)/example -name "*.v")
CLK_PORT_NAME ?= clock
CLK_FREQ_MHZ ?= 50
VERILOG_INCLUDE_DIRS ?= $(PROJ_PATH)/example

RESULT_DIR = $(PROJ_PATH)/result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz
PNR_RESULT_DIR = $(PROJ_PATH)/result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz-pnr
SCRIPT_DIR = $(PROJ_PATH)/scripts
NETLIST_SYN_V = $(DESIGN).netlist.syn.v
DOT_FORMAT ?= svg

# OpenROAD PnR parameters
CORE_UTILIZATION ?= 40
CORE_ASPECT_RATIO ?= 1.0
PLACE_DENSITY ?= 0.60
MIN_ROUTING_LAYER ?= metal2
MAX_ROUTING_LAYER ?= metal7

init:
	wget -O - $(NANGATE45_URL) | tar xfj -

init_opensta:
	git clone https://github.com/parallaxsw/OpenSTA.git
	cd OpenSTA && docker build --file Dockerfile.ubuntu_22.04 --tag opensta .

init_openroad:
	git clone --recursive https://github.com/The-OpenROAD-Project/OpenROAD.git || true
ifeq ($(shell uname -s),Darwin)
	# macOS: install dependencies via Homebrew
	brew install bison boost cmake eigen flex fmt groff libomp or-tools \
		pkg-config python spdlog tcl-tk zlib swig yaml-cpp googletest || true
	# lemon-graph: build from source (the Homebrew tap is broken with newer cmake)
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
		cmake --build build -j$$(sysctl -n hw.ncpu) && \
		sudo cmake --install build && \
		rm -rf /tmp/lemon-1.3.1 /tmp/lemon-1.3.1.tar.gz ; \
	else echo ">>> lemon-graph already installed, skipping." ; fi
	# Build OpenROAD
	cd OpenROAD && ./etc/Build.sh
else
	# Linux: use the official dependency installer + build script
	cd OpenROAD \
		&& sudo ./etc/DependencyInstaller.sh -base \
		&& ./etc/DependencyInstaller.sh -common -local \
		&& ./etc/Build.sh
endif

# Build OpenROAD Docker image (alternative to local build)
init_openroad_docker:
	@echo "Pulling pre-built OpenROAD Docker image ..."
	docker pull openroad/openroad:latest
	docker tag openroad/openroad:latest openroad

init_local:
	# Download and build CUDD
	wget https://raw.githubusercontent.com/davidkebo/cudd/main/cudd_versions/cudd-3.0.0.tar.gz
	tar -xvf cudd-3.0.0.tar.gz
	rm cudd-3.0.0.tar.gz
	cd cudd-3.0.0 && mkdir -p ../cudd && ./configure && make -j$$(nproc)
	# Get NANGATE45 and clone OpenSTA
	$(MAKE) init
	git clone https://github.com/parallaxsw/OpenSTA.git || true
	# Build OpenSTA with CUDD
	cd OpenSTA && cmake -DCUDD_DIR=../cudd-3.0.0 -B build . && cmake --build build -j$$(nproc)
	# Build and install yosys-slang
	git clone --recursive https://github.com/povik/yosys-slang || true
	cd yosys-slang && make -j$$(nproc) && make install
	# Build OpenROAD for PnR
	$(MAKE) init_openroad

full_local:
	$(MAKE) sta_local DESIGN=$(DESIGN)
	$(MAKE) pnr_local DESIGN=$(DESIGN)
	$(MAKE) viz_layout_local DESIGN=$(DESIGN)
	$(MAKE) viz_layout_klayout DESIGN=$(DESIGN)
	$(MAKE) viz_layout_py DESIGN=$(DESIGN)

syn: $(RESULT_DIR)/$(NETLIST_SYN_V)

$(RESULT_DIR)/$(NETLIST_SYN_V): $(RTL_FILES) $(SCRIPT_DIR)/yosys.tcl
	mkdir -p $(@D)
	echo tcl $(SCRIPT_DIR)/yosys.tcl \
		$(DESIGN) \
		\"$(RTL_FILES)\" \
		\"$(VERILOG_INCLUDE_DIRS)\" \
		$@ | yosys -m slang -l $(@D)/yosys.log -s - | tee $(@D)/yosys.log

sta: $(RESULT_DIR)/$(NETLIST_SYN_V)
	@docker run -i --rm \
		-e DESIGN=$(DESIGN) \
		-e CLK_PORT_NAME=$(CLK_PORT_NAME) \
		-e CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
		-e RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/ \
		-e NETLIST_SYN_V=$(NETLIST_SYN_V) \
		-v .:/data opensta data/scripts/opensta.tcl | tee $(RESULT_DIR)/sta.log

sta_local: $(RESULT_DIR)/$(NETLIST_SYN_V)
	PROJ_PATH=$(shell pwd) \
	DESIGN=$(DESIGN) \
	CLK_PORT_NAME=$(CLK_PORT_NAME) \
	CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
	RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/ \
	NETLIST_SYN_V=$(NETLIST_SYN_V) \
	./OpenSTA/build/sta ./scripts/opensta.tcl | tee $(RESULT_DIR)/sta.log

sta_detail: $(RESULT_DIR)/$(NETLIST_SYN_V)
	@docker run -i --rm \
		-e DESIGN=$(DESIGN) \
		-e CLK_PORT_NAME=$(CLK_PORT_NAME) \
		-e CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
		-e RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/ \
		-e NETLIST_SYN_V=$(NETLIST_SYN_V) \
		-v .:/data opensta data/scripts/opensta_detail.tcl | tee $(RESULT_DIR)/sta_detail.log

sta_detail_local: $(RESULT_DIR)/$(NETLIST_SYN_V)
	PROJ_PATH=$(shell pwd) \
	DESIGN=$(DESIGN) \
	CLK_PORT_NAME=$(CLK_PORT_NAME) \
	CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
	RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/ \
	NETLIST_SYN_V=$(NETLIST_SYN_V) \
	./OpenSTA/build/sta ./scripts/opensta_detail.tcl | tee $(RESULT_DIR)/sta_detail.log

show: $(RESULT_DIR)/$(NETLIST_SYN_V)
	@cat $(RESULT_DIR)/sta.log
	@cat $(RESULT_DIR)/synth_stat.txt | grep 'Chip area'

dot: $(RESULT_DIR)/$(NETLIST_SYN_V)
	@echo "=== Generating architecture diagram ==="
	python3 $(SCRIPT_DIR)/gen-arch.py $(RESULT_DIR)/$(DESIGN)_hier.json \
		-t $(DESIGN) -o $(RESULT_DIR)/$(DESIGN)_arch.dot \
		-l $(PROJ_PATH)/nangate45/lib/merged.lib \
		-s $(RESULT_DIR)/$(DESIGN)_syn.json
	python3 $(SCRIPT_DIR)/gen-dot.py -f $(DOT_FORMAT) $(RESULT_DIR)/$(DESIGN)_arch.dot
	@echo "=== Diagrams generated in $(RESULT_DIR)/ ==="

viz: $(RESULT_DIR)/$(NETLIST_SYN_V).timing_model
	@echo "=== Visualizing timing model ==="
	python3 $(SCRIPT_DIR)/viz-timing-model.py \
		$(RESULT_DIR)/$(NETLIST_SYN_V).timing_model \
		-o $(RESULT_DIR)
	@echo "=== Timing plots generated in $(RESULT_DIR)/ ==="

# ===== Physical Design (Place & Route) via OpenROAD =====

pnr: $(RESULT_DIR)/$(NETLIST_SYN_V)
	@mkdir -p $(PNR_RESULT_DIR)
	@docker run -i --rm \
		-e DESIGN=$(DESIGN) \
		-e CLK_PORT_NAME=$(CLK_PORT_NAME) \
		-e CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
		-e RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/ \
		-e PNR_RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz-pnr \
		-e NETLIST_SYN_V=$(NETLIST_SYN_V) \
		-e CORE_UTILIZATION=$(CORE_UTILIZATION) \
		-e CORE_ASPECT_RATIO=$(CORE_ASPECT_RATIO) \
		-e PLACE_DENSITY=$(PLACE_DENSITY) \
		-e MIN_ROUTING_LAYER=$(MIN_ROUTING_LAYER) \
		-e MAX_ROUTING_LAYER=$(MAX_ROUTING_LAYER) \
		-v .:/data openroad /data/scripts/openroad_pnr.tcl \
		| tee $(PNR_RESULT_DIR)/pnr.log

pnr_local: $(RESULT_DIR)/$(NETLIST_SYN_V)
	@mkdir -p $(PNR_RESULT_DIR)
	PROJ_PATH=$(shell pwd) \
	DESIGN=$(DESIGN) \
	CLK_PORT_NAME=$(CLK_PORT_NAME) \
	CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
	RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/ \
	PNR_RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz-pnr \
	NETLIST_SYN_V=$(NETLIST_SYN_V) \
	CORE_UTILIZATION=$(CORE_UTILIZATION) \
	CORE_ASPECT_RATIO=$(CORE_ASPECT_RATIO) \
	PLACE_DENSITY=$(PLACE_DENSITY) \
	MIN_ROUTING_LAYER=$(MIN_ROUTING_LAYER) \
	MAX_ROUTING_LAYER=$(MAX_ROUTING_LAYER) \
	./OpenROAD/build/bin/openroad ./scripts/openroad_pnr.tcl \
	| tee $(PNR_RESULT_DIR)/pnr.log

# Fast PnR variant — higher utilization, fewer iterations, multi-threaded routing
DR_THREADS ?= 0

pnr_fast: $(RESULT_DIR)/$(NETLIST_SYN_V)
	@mkdir -p $(PNR_RESULT_DIR)
	@docker run -i --rm \
		-e DESIGN=$(DESIGN) \
		-e CLK_PORT_NAME=$(CLK_PORT_NAME) \
		-e CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
		-e RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/ \
		-e PNR_RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz-pnr \
		-e NETLIST_SYN_V=$(NETLIST_SYN_V) \
		-e CORE_UTILIZATION=$(CORE_UTILIZATION) \
		-e CORE_ASPECT_RATIO=$(CORE_ASPECT_RATIO) \
		-e PLACE_DENSITY=$(PLACE_DENSITY) \
		-e MIN_ROUTING_LAYER=$(MIN_ROUTING_LAYER) \
		-e MAX_ROUTING_LAYER=$(MAX_ROUTING_LAYER) \
		-e DR_THREADS=$(DR_THREADS) \
		-v .:/data openroad /data/scripts/openroad_pnr_fast.tcl \
		| tee $(PNR_RESULT_DIR)/pnr.log

pnr_fast_local: $(RESULT_DIR)/$(NETLIST_SYN_V)
	@mkdir -p $(PNR_RESULT_DIR)
	PROJ_PATH=$(shell pwd) \
	DESIGN=$(DESIGN) \
	CLK_PORT_NAME=$(CLK_PORT_NAME) \
	CLK_FREQ_MHZ=$(CLK_FREQ_MHZ) \
	RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz/ \
	PNR_RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz-pnr \
	NETLIST_SYN_V=$(NETLIST_SYN_V) \
	CORE_UTILIZATION=$(CORE_UTILIZATION) \
	CORE_ASPECT_RATIO=$(CORE_ASPECT_RATIO) \
	PLACE_DENSITY=$(PLACE_DENSITY) \
	MIN_ROUTING_LAYER=$(MIN_ROUTING_LAYER) \
	MAX_ROUTING_LAYER=$(MAX_ROUTING_LAYER) \
	DR_THREADS=$(DR_THREADS) \
	./OpenROAD/build/bin/openroad ./scripts/openroad_pnr_fast.tcl \
	| tee $(PNR_RESULT_DIR)/pnr.log

# Run full flow: synthesis → STA → PnR (local)
flow_local: syn sta_local pnr_local
	@echo "=== Full flow complete: synthesis → STA → PnR ==="
	@echo "=== Synthesis/STA results in $(RESULT_DIR)/ ==="
	@echo "=== PnR results in $(PNR_RESULT_DIR)/ ==="

# Run full RTL-to-GDS flow (local)
flow_gds_local: syn sta_local pnr_local gds
	@echo "=== Full RTL-to-GDS flow complete ==="
	@echo "=== GDS: $(PNR_RESULT_DIR)/$(DESIGN)_final.gds ==="

# ===== GDS Generation (DEF + cell library merge via KLayout) =====

CELL_GDS = $(PROJ_PATH)/nangate45/gds/NangateOpenCellLibrary.gds
TECH_LEF = $(PROJ_PATH)/nangate45/lef/NangateOpenCellLibrary.tech.lef
SC_LEF   = $(PROJ_PATH)/nangate45/lef/NangateOpenCellLibrary.macro.mod.lef

gds: $(PNR_RESULT_DIR)/$(DESIGN)_final.def
	@echo "=== Generating GDS via KLayout (DEF + cell GDS merge) ==="
	QT_QPA_PLATFORM=offscreen klayout -z -r $(SCRIPT_DIR)/klayout_gds_merge.py \
		-rd def_file=$(PNR_RESULT_DIR)/$(DESIGN)_final.def \
		-rd cell_gds=$(CELL_GDS) \
		-rd tech_lef=$(TECH_LEF) \
		-rd cell_lef=$(SC_LEF) \
		-rd tech_file=$(PROJ_PATH)/nangate45/klayout.lyt \
		-rd out_gds=$(PNR_RESULT_DIR)/$(DESIGN)_final.gds \
		-rd design=$(DESIGN)
	@echo "=== GDS written: $(PNR_RESULT_DIR)/$(DESIGN)_final.gds ==="

# ===== Layout Visualization =====

# Generate layout images via Python + matplotlib (no GUI/X11/Docker needed)
viz_layout_py: $(PNR_RESULT_DIR)/$(DESIGN)_final.def
	@echo "=== Generating layout images via Python ==="
	python3 $(SCRIPT_DIR)/viz_layout.py $(PNR_RESULT_DIR) \
		--design $(DESIGN) --format svg
	@echo "=== Layout images in $(PNR_RESULT_DIR)/images/ ==="

# Generate layout images via OpenROAD GUI in Docker
viz_layout: $(PNR_RESULT_DIR)/$(DESIGN)_final.def
	@echo "=== Generating layout images via OpenROAD (Docker) ==="
	@docker run -i --rm \
		-e DESIGN=$(DESIGN) \
		-e PNR_RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz-pnr \
		-v .:/data openroad \
		xvfb-run -a openroad -gui -exit /data/scripts/openroad_viz.tcl \
		| tee $(PNR_RESULT_DIR)/viz_layout.log
	@echo "=== Layout images in $(PNR_RESULT_DIR)/images/ ==="

# Generate layout images via OpenROAD GUI locally (requires X11 or Xvfb)
viz_layout_local: $(PNR_RESULT_DIR)/$(DESIGN)_final.def
	@echo "=== Generating layout images via OpenROAD ==="
	PROJ_PATH=$(shell pwd) \
	DESIGN=$(DESIGN) \
	PNR_RESULT_DIR=result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz-pnr \
	xvfb-run -a ./OpenROAD/build/bin/openroad -gui -exit \
		./scripts/openroad_viz.tcl \
		| tee $(PNR_RESULT_DIR)/viz_layout.log
	@echo "=== Layout images in $(PNR_RESULT_DIR)/images/ ==="

# Generate layout images via KLayout (no X11 needed)
viz_layout_klayout: $(PNR_RESULT_DIR)/$(DESIGN)_final.def
	@echo "=== Generating layout images via KLayout ==="
	QT_QPA_PLATFORM=offscreen klayout -z -r $(SCRIPT_DIR)/viz_layout_klayout.py \
		-rd def_file=$(PNR_RESULT_DIR)/$(DESIGN)_final.def \
		-rd tech_lef=$(TECH_LEF) \
		-rd cell_lef=$(SC_LEF) \
		-rd tech_file=$(PROJ_PATH)/nangate45/klayout.lyt \
		-rd lyp_file=$(PROJ_PATH)/nangate45/klayout.lyp \
		-rd out_dir=$(PNR_RESULT_DIR)/images \
		-rd design=$(DESIGN)
	@echo "=== Layout images in $(PNR_RESULT_DIR)/images/ ==="

# Open final layout interactively in OpenROAD GUI
gui: $(PNR_RESULT_DIR)/$(DESIGN)_final.odb
	@echo "=== Opening layout in OpenROAD GUI ==="
	cd $(PROJ_PATH) && ./OpenROAD/build/bin/openroad -gui <<< "\
		read_lef nangate45/lef/NangateOpenCellLibrary.tech.lef; \
		read_lef nangate45/lef/NangateOpenCellLibrary.macro.mod.lef; \
		read_db $(PNR_RESULT_DIR)/$(DESIGN)_final.odb"

# Open final layout interactively in KLayout
gui_klayout: $(PNR_RESULT_DIR)/$(DESIGN)_final.def
	@echo "=== Opening layout in KLayout ==="
	klayout -e \
		-t $(PROJ_PATH)/nangate45/klayout.lyt \
		-l $(PROJ_PATH)/nangate45/klayout.lyp \
		$(PNR_RESULT_DIR)/$(DESIGN)_final.def

clean:
	-rm -rf result/

clean_pnr:
	-rm -rf $(PNR_RESULT_DIR)/

.PHONY: init init_openroad init_openroad_docker syn \
        sta sta_local sta_detail sta_detail_local show dot viz \
        pnr pnr_local flow_local \
        viz_layout viz_layout_py viz_layout_local viz_layout_klayout gui gui_klayout \
        clean clean_pnr
