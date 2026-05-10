# SKY130 HD Platform Configuration for OpenROAD / OpenSTA scripts
# Requires: PLATFORM_DIR and LIB_DIR are set before sourcing this file
#   PLATFORM_DIR = platforms/sky130hd (build configs)
#   LIB_DIR      = third_party/lib/sky130hd       (downloaded PDK data)
#
# This config targets sky130_fd_sc_hd, the same standard cell library
# used by TinyTapeout / OpenLane, so synthesized + placed-and-routed
# designs are tape-out compatible with the TT shuttle flow.

# Technology files
set TECH_LEF     $LIB_DIR/lef/sky130_fd_sc_hd.tlef
set SC_LEF       $LIB_DIR/lef/sky130_fd_sc_hd_merged.lef

# Time unit: liberty uses ns -> MHz_to_period factor = 1e3
set TIME_SCALE 1000.0
set TIME_UNIT "ns"
set LIB_FILES [list \
    $LIB_DIR/lib/sky130_fd_sc_hd__tt_025C_1v80.lib \
]
set LIB_FILE     [lindex $LIB_FILES 0]

# RC extraction configuration (sourced by PnR scripts)
set SET_RC_TCL   $PLATFORM_DIR/setRC.tcl

# Placement site (from sky130_fd_sc_hd.tlef)
set PLACE_SITE   unithd

# Cell configuration
set FILL_CELLS     "sky130_fd_sc_hd__fill_1 sky130_fd_sc_hd__fill_2 sky130_fd_sc_hd__fill_4 sky130_fd_sc_hd__fill_8"
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
]
set CTS_BUF_CELL   sky130_fd_sc_hd__clkbuf_4
set CTS_BUF_LIST   {sky130_fd_sc_hd__clkbuf_1 sky130_fd_sc_hd__clkbuf_2 sky130_fd_sc_hd__clkbuf_4 sky130_fd_sc_hd__clkbuf_8 sky130_fd_sc_hd__clkbuf_16}

# Tie cell configuration (for repair_tie_fanout)
set TIEHI_CELL_AND_PORT {sky130_fd_sc_hd__conb_1 HI}
set TIELO_CELL_AND_PORT {sky130_fd_sc_hd__conb_1 LO}

# Antenna repair diode configuration (for repair_antennas)
set ANTENNA_DIODE_CELL sky130_fd_sc_hd__diode_2
set ANTENNA_DIODE_CELL_AND_PORT {sky130_fd_sc_hd__diode_2 DIODE}

# Pin placement layers (TinyTapeout-style: H=met3, V=met2)
set PIN_HOR_LAYER  met3
set PIN_VER_LAYER  met2

# Default routing layers (can be overridden by env vars before sourcing)
if {![info exists MIN_ROUTING_LAYER] || $MIN_ROUTING_LAYER eq ""} {
  set MIN_ROUTING_LAYER met1
}
if {![info exists MAX_ROUTING_LAYER] || $MAX_ROUTING_LAYER eq ""} {
  set MAX_ROUTING_LAYER met5
}

# Layer names for GUI visualization
set VIZ_METAL_LAYERS {li1 met1 met2 met3 met4 met5}
set VIZ_VIA_LAYERS   {mcon via via2 via3 via4}

# --- Platform Procedures ---

# Track definitions (matches OpenROAD-flow-scripts sky130hd/make_tracks.tcl)
proc platform_make_tracks {} {
  make_tracks li1  -x_offset 0.23 -x_pitch 0.46 -y_offset 0.17 -y_pitch 0.34
  make_tracks met1 -x_offset 0.17 -x_pitch 0.34 -y_offset 0.17 -y_pitch 0.34
  make_tracks met2 -x_offset 0.23 -x_pitch 0.46 -y_offset 0.23 -y_pitch 0.46
  make_tracks met3 -x_offset 0.34 -x_pitch 0.68 -y_offset 0.34 -y_pitch 0.68
  make_tracks met4 -x_offset 0.46 -x_pitch 0.92 -y_offset 0.46 -y_pitch 0.92
  make_tracks met5 -x_offset 1.70 -x_pitch 3.40 -y_offset 1.70 -y_pitch 3.40
}

# Tapcell insertion (from OpenROAD-flow-scripts sky130hd/tapcell.tcl)
proc platform_tapcell {} {
  tapcell \
    -distance 14 \
    -tapcell_master "sky130_fd_sc_hd__tapvpwrvgnd_1"
}

# Power Distribution Network
# Mirrors OpenROAD-flow-scripts sky130hd/pdn.tcl (sky130_fd_sc_hd grid).
# check_size: if 1, skip upper-metal straps when core is too small.
proc platform_pdn {{check_size 1}} {
  add_global_connection -net VDD -inst_pattern .* -pin_pattern {^VDD$} -power
  add_global_connection -net VDD -inst_pattern .* -pin_pattern {^VDDPE$}
  add_global_connection -net VDD -inst_pattern .* -pin_pattern {^VDDCE$}
  add_global_connection -net VDD -inst_pattern .* -pin_pattern {VPWR}
  add_global_connection -net VDD -inst_pattern .* -pin_pattern {VPB}
  add_global_connection -net VSS -inst_pattern .* -pin_pattern {^VSS$} -ground
  add_global_connection -net VSS -inst_pattern .* -pin_pattern {^VSSE$}
  add_global_connection -net VSS -inst_pattern .* -pin_pattern {VGND}
  add_global_connection -net VSS -inst_pattern .* -pin_pattern {VNB}

  global_connect
  set_voltage_domain -power VDD -ground VSS

  define_pdn_grid -name "Core" -pins {met5}
  add_pdn_stripe -followpins -layer met1 -width 0.48

  if {$check_size} {
    set core_area [ord::get_db_core]
    set core_width [expr {([$core_area xMax] - [$core_area xMin]) / 1000.0}]
    set core_height [expr {([$core_area yMax] - [$core_area yMin]) / 1000.0}]
    puts "PDN: core dimensions = ${core_width} x ${core_height} um"

    if {$core_width > 30.0 && $core_height > 30.0} {
      add_pdn_stripe -layer met4 -width 1.600 -pitch 27.140 -offset 13.570
      add_pdn_stripe -layer met5 -width 1.600 -pitch 27.200 -offset 13.600
      add_pdn_connect -layers {met1 met4}
      add_pdn_connect -layers {met4 met5}
    } else {
      puts "PDN: core too small for met4/met5 straps, using followpins only"
    }
  } else {
    add_pdn_stripe -layer met4 -width 1.600 -pitch 27.140 -offset 13.570
    add_pdn_stripe -layer met5 -width 1.600 -pitch 27.200 -offset 13.600
    add_pdn_connect -layers {met1 met4}
    add_pdn_connect -layers {met4 met5}
  }

  # Macro grids (for designs with hard macros)
  define_pdn_grid -name "CORE_macro_grid_1" -macro \
    -orient {R0 R180 MX MY} -halo {2.0 2.0 2.0 2.0} -default
  add_pdn_connect -grid "CORE_macro_grid_1" -layers {met4 met5}
  define_pdn_grid -name "CORE_macro_grid_2" -macro \
    -orient {R90 R270 MXR90 MYR90} -halo {2.0 2.0 2.0 2.0} -default
  add_pdn_connect -grid "CORE_macro_grid_2" -layers {met4 met5}

  pdngen
}

# Routing layer configuration
proc platform_routing_setup {} {
  global MIN_ROUTING_LAYER MAX_ROUTING_LAYER
  set_routing_layers \
    -signal ${MIN_ROUTING_LAYER}-${MAX_ROUTING_LAYER} \
    -clock met3-${MAX_ROUTING_LAYER}

  set_global_routing_layer_adjustment ${MIN_ROUTING_LAYER}-${MAX_ROUTING_LAYER} 0.20

  set_macro_extension 2
}
