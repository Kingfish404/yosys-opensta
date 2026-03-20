# =====================================================================
#  Benchmark Targets
#  Usage: make sta-hazard3 / make flow-picorv32 / etc.
#  Append PLATFORM=asap7 to use ASAP7 instead of NanGate45.
# =====================================================================

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
sta-serv: third_party/serv
	@make -C .. sta show \
		DESIGN=serv_top \
		CLK_PORT_NAME=clk \
		RTL_FILES="$(shell find $(abspath third_party/serv/rtl) -name "*.v")" \
		VERILOG_INCLUDE_DIRS="$(abspath third_party/serv)"

flow-serv: third_party/serv
	@make -C .. flow \
		DESIGN=serv_top \
		CLK_PORT_NAME=clk \
		RTL_FILES="$(shell find $(abspath third_party/serv/rtl) -name "*.v")" \
		VERILOG_INCLUDE_DIRS="$(abspath third_party/serv)"

# --- Third-party source checkout ---
third_party/Hazard3:
	git clone https://github.com/Wren6991/Hazard3 $@

third_party/picorv32:
	git clone https://github.com/YosysHQ/picorv32 $@

third_party/serv:
	git clone https://github.com/olofk/serv $@

.PHONY: sta-hazard3 sta-picorv32 sta-serv \
        flow-hazard3 flow-picorv32 flow-serv
