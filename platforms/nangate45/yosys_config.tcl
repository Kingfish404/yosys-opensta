# NanGate45 Yosys Synthesis Configuration
# Requires: FOUNDARY_PATH is set before sourcing this file

set MERGED_LIB_FILE         "$FOUNDARY_PATH/lib/merged.lib"
set BLACKBOX_V_FILE         "$FOUNDARY_PATH/verilog/blackbox.v"
set CLKGATE_MAP_FILE        "$FOUNDARY_PATH/verilog/cells_clkgate.v"
set LATCH_MAP_FILE          "$FOUNDARY_PATH/verilog/cells_latch.v"
set BLACKBOX_MAP_TCL        "$FOUNDARY_PATH/blackbox_map.tcl"

set TIEHI_CELL_AND_PORT     "LOGIC1_X1 Z"
set TIELO_CELL_AND_PORT     "LOGIC0_X1 Z"
set MIN_BUF_CELL_AND_PORTS  "BUF_X1 A Z"
