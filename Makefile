PROJ_PATH = $(shell pwd)

NANGATE45_URL="https://github.com/Kingfish404/yosys-opensta/releases/download/nangate45/nangate45.tar.bz2"

DESIGN ?= gcd
RTL_FILES ?= $(shell find $(PROJ_PATH)/example -name "*.v")
CLK_PORT_NAME ?= clock
CLK_FREQ_MHZ ?= 500
VERILOG_INCLUDE_DIRS ?= $(PROJ_PATH)/example

RESULT_DIR = $(PROJ_PATH)/result/$(DESIGN)-$(CLK_FREQ_MHZ)MHz
SCRIPT_DIR = $(PROJ_PATH)/scripts
NETLIST_SYN_V = $(DESIGN).netlist.syn.v

init:
	wget -O - $(NANGATE45_URL) | tar xfj -

init_opensta:
	git clone https://github.com/parallaxsw/OpenSTA.git
	cd OpenSTA && docker build --file Dockerfile.ubuntu_22.04 --tag opensta .

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

show: $(RESULT_DIR)/$(NETLIST_SYN_V)
	@cat $(RESULT_DIR)/sta.log
	@cat $(RESULT_DIR)/synth_stat.txt | grep 'Chip area'

clean:
	-rm -rf result/

.PHONY: init syn sta clean
