# ASAP7 Yosys Synthesis Configuration (RVT variant)
# Requires: FOUNDARY_PATH is set before sourcing this file

set MERGED_LIB_FILE         "$FOUNDARY_PATH/lib/merged.lib"
set BLACKBOX_V_FILE         ""
set CLKGATE_MAP_FILE        "$FOUNDARY_PATH/yoSys/cells_clkgate_R.v"
set LATCH_MAP_FILE          "$FOUNDARY_PATH/yoSys/cells_latch_R.v"
set BLACKBOX_MAP_TCL        ""

set TIEHI_CELL_AND_PORT     "TIEHIx1_ASAP7_75t_R H"
set TIELO_CELL_AND_PORT     "TIELOx1_ASAP7_75t_R L"
set MIN_BUF_CELL_AND_PORTS  "BUFx2_ASAP7_75t_R A Y"
