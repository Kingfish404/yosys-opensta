# NanGate45 Yosys Synthesis Configuration
# Requires: FOUNDRY_PATH is set before sourcing this file

set MERGED_LIB_FILE         "$FOUNDRY_PATH/lib/merged.lib"
set LIB_FILES               [list $MERGED_LIB_FILE]
set BLACKBOX_V_FILE         "$FOUNDRY_PATH/verilog/blackbox.v"
set CLKGATE_MAP_FILE        "$FOUNDRY_PATH/verilog/cells_clkgate.v"
set LATCH_MAP_FILE          "$FOUNDRY_PATH/verilog/cells_latch.v"
set BLACKBOX_MAP_TCL        "$FOUNDRY_PATH/blackbox_map.tcl"

set TIEHI_CELL_AND_PORT     "LOGIC1_X1 Z"
set TIELO_CELL_AND_PORT     "LOGIC0_X1 Z"
set MIN_BUF_CELL_AND_PORTS  "BUF_X1 A Z"

# ABC optimization parameters
set ABC_DRIVER_CELL         "BUF_X1"
set ABC_LOAD_IN_FF          3.898

# Cells to avoid during synthesis (ease congestion)
set DONT_USE_CELLS          {TAPCELL_X1 FILLCELL_X1 AOI211_X1 OAI211_X1}
