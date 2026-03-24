# ASAP7 Yosys Synthesis Configuration (RVT variant)
# Requires: FOUNDRY_PATH is set before sourcing this file

set LIB_FILES [list \
    "$FOUNDRY_PATH/lib/NLDM/asap7sc7p5t_AO_RVT_TT_nldm_211120.lib" \
    "$FOUNDRY_PATH/lib/NLDM/asap7sc7p5t_INVBUF_RVT_TT_nldm_220122.lib" \
    "$FOUNDRY_PATH/lib/NLDM/asap7sc7p5t_OA_RVT_TT_nldm_211120.lib" \
    "$FOUNDRY_PATH/lib/NLDM/asap7sc7p5t_SIMPLE_RVT_TT_nldm_211120.lib" \
    "$FOUNDRY_PATH/lib/NLDM/asap7sc7p5t_SEQ_RVT_TT_nldm_220123.lib" \
]
set MERGED_LIB_FILE         [lindex $LIB_FILES 0]
set BLACKBOX_V_FILE         ""
set CLKGATE_MAP_FILE        "$FOUNDRY_PATH/yoSys/cells_clkgate_R.v"
set LATCH_MAP_FILE          "$FOUNDRY_PATH/yoSys/cells_latch_R.v"
set BLACKBOX_MAP_TCL        ""

set TIEHI_CELL_AND_PORT     "TIEHIx1_ASAP7_75t_R H"
set TIELO_CELL_AND_PORT     "TIELOx1_ASAP7_75t_R L"
set MIN_BUF_CELL_AND_PORTS  "BUFx2_ASAP7_75t_R A Y"

# ABC optimization parameters
set ABC_DRIVER_CELL         "BUFx2_ASAP7_75t_R"
set ABC_LOAD_IN_FF          3.898

# Cells to avoid during synthesis (ease congestion)
set DONT_USE_CELLS          {*x1p*_ASAP7* *xp*_ASAP7* SDF* ICG*}
