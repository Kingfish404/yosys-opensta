sta_hazard3:
	@if [ ! -d third_party/Hazard3 ]; then \
		git clone https://github.com/Wren6991/Hazard3 third_party/Hazard3; \
	fi
	@make -C .. sta show \
		DESIGN=hazard3_core \
		CLK_PORT_NAME=clk \
		RTL_FILES="$(shell find $(abspath third_party/Hazard3/hdl) -name "*.v")" \
		VERILOG_INCLUDE_DIRS="$(abspath third_party/Hazard3/hdl)"

sta_picorv32:
	@if [ ! -d third_party/picorv32 ]; then \
		git clone https://github.com/YosysHQ/picorv32 third_party/picorv32; \
	fi
	@make -C .. sta show \
		DESIGN=picorv32 \
		CLK_PORT_NAME=clk \
		RTL_FILES="$(shell find $(abspath third_party/picorv32) -name "picorv32.v")" \
		VERILOG_INCLUDE_DIRS="$(abspath third_party/picorv32)"

sta_serv:
	@if [ ! -d third_party/serv ]; then \
		git clone https://github.com/olofk/serv third_party/serv; \
	fi
	@make -C .. sta show \
		DESIGN=serv_top \
		CLK_PORT_NAME=clk \
		RTL_FILES="$(shell find $(abspath third_party/serv/rtl) -name "*.v")" \
		VERILOG_INCLUDE_DIRS="$(abspath third_party/serv)"
