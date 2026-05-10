# SKY130 HD Yosys Synthesis Configuration
# Requires: FOUNDRY_PATH is set before sourcing this file
#
# Uses sky130_fd_sc_hd standard cells (TT corner: typical, 25C, 1.80V).
# This matches the TinyTapeout / OpenLane sky130 flow, so the resulting
# netlist is suitable for tape-out via TinyTapeout.

set MERGED_LIB_FILE         "$FOUNDRY_PATH/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
set LIB_FILES               [list $MERGED_LIB_FILE]
set BLACKBOX_V_FILE         ""
set CLKGATE_MAP_FILE        "$FOUNDRY_PATH/cells_clkgate_hd.v"
set LATCH_MAP_FILE          "$FOUNDRY_PATH/cells_latch_hd.v"
set BLACKBOX_MAP_TCL        ""

set TIEHI_CELL_AND_PORT     "sky130_fd_sc_hd__conb_1 HI"
set TIELO_CELL_AND_PORT     "sky130_fd_sc_hd__conb_1 LO"
set MIN_BUF_CELL_AND_PORTS  "sky130_fd_sc_hd__buf_4 A X"

# ABC optimization parameters (matches OpenROAD-flow-scripts sky130hd defaults)
set ABC_DRIVER_CELL         "sky130_fd_sc_hd__buf_1"
set ABC_LOAD_IN_FF          5

# Cells to avoid during synthesis (low-power flow & probe cells unsuitable
# for the standard digital flow). Mirrors OpenROAD-flow-scripts sky130hd.
set DONT_USE_CELLS [list \
    sky130_fd_sc_hd__probe_p_8 \
    sky130_fd_sc_hd__probec_p_8 \
    sky130_fd_sc_hd__lpflow_bleeder_1 \
    sky130_fd_sc_hd__lpflow_clkbufkapwr_1 \
    sky130_fd_sc_hd__lpflow_clkbufkapwr_16 \
    sky130_fd_sc_hd__lpflow_clkbufkapwr_2 \
    sky130_fd_sc_hd__lpflow_clkbufkapwr_4 \
    sky130_fd_sc_hd__lpflow_clkbufkapwr_8 \
    sky130_fd_sc_hd__lpflow_clkinvkapwr_1 \
    sky130_fd_sc_hd__lpflow_clkinvkapwr_16 \
    sky130_fd_sc_hd__lpflow_clkinvkapwr_2 \
    sky130_fd_sc_hd__lpflow_clkinvkapwr_4 \
    sky130_fd_sc_hd__lpflow_clkinvkapwr_8 \
    sky130_fd_sc_hd__lpflow_decapkapwr_12 \
    sky130_fd_sc_hd__lpflow_decapkapwr_3 \
    sky130_fd_sc_hd__lpflow_decapkapwr_4 \
    sky130_fd_sc_hd__lpflow_decapkapwr_6 \
    sky130_fd_sc_hd__lpflow_decapkapwr_8 \
    sky130_fd_sc_hd__lpflow_inputiso0n_1 \
    sky130_fd_sc_hd__lpflow_inputiso0p_1 \
    sky130_fd_sc_hd__lpflow_inputiso1n_1 \
    sky130_fd_sc_hd__lpflow_inputiso1p_1 \
    sky130_fd_sc_hd__lpflow_inputisolatch_1 \
    sky130_fd_sc_hd__lpflow_isobufsrc_1 \
    sky130_fd_sc_hd__lpflow_isobufsrc_16 \
    sky130_fd_sc_hd__lpflow_isobufsrc_2 \
    sky130_fd_sc_hd__lpflow_isobufsrc_4 \
    sky130_fd_sc_hd__lpflow_isobufsrc_8 \
    sky130_fd_sc_hd__lpflow_isobufsrckapwr_16 \
    sky130_fd_sc_hd__lpflow_lsbuf_lh_hl_isowell_tap_1 \
    sky130_fd_sc_hd__lpflow_lsbuf_lh_hl_isowell_tap_2 \
    sky130_fd_sc_hd__lpflow_lsbuf_lh_hl_isowell_tap_4 \
    sky130_fd_sc_hd__lpflow_lsbuf_lh_isowell_4 \
    sky130_fd_sc_hd__lpflow_lsbuf_lh_isowell_tap_1 \
    sky130_fd_sc_hd__lpflow_lsbuf_lh_isowell_tap_2 \
    sky130_fd_sc_hd__lpflow_lsbuf_lh_isowell_tap_4 \
]
