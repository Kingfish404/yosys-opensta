# NanGate45 Platform Configuration for OpenROAD / OpenSTA scripts
# Requires: PLATFORM_DIR and LIB_DIR are set before sourcing this file
#   PLATFORM_DIR = platforms/nangate45 (build configs)
#   LIB_DIR      = lib/nangate45       (downloaded PDK data)

# Technology files
set TECH_LEF     $LIB_DIR/lef/NangateOpenCellLibrary.tech.lef
set SC_LEF       $LIB_DIR/lef/NangateOpenCellLibrary.macro.mod.lef
set LIB_FILE     $LIB_DIR/lib/NangateOpenCellLibrary_typical.lib

# RC extraction configuration (sourced by PnR scripts)
set SET_RC_TCL   $LIB_DIR/setRC.tcl

# Placement site
set PLACE_SITE   FreePDK45_38x28_10R_NP_162NW_34O

# Cell configuration
set FILL_CELLS     "FILLCELL_X1 FILLCELL_X2 FILLCELL_X4 FILLCELL_X8 FILLCELL_X16 FILLCELL_X32"
set DONT_USE_CELLS {TAPCELL_X1 FILLCELL_X1 AOI211_X1 OAI211_X1}
set CTS_BUF_CELL   BUF_X4
set CTS_BUF_LIST   {BUF_X4 BUF_X8 BUF_X16}

# Pin placement layers
set PIN_HOR_LAYER  metal3
set PIN_VER_LAYER  metal2

# Default routing layers (can be overridden by env vars before sourcing)
if {![info exists MIN_ROUTING_LAYER] || $MIN_ROUTING_LAYER eq ""} {
  set MIN_ROUTING_LAYER metal2
}
if {![info exists MAX_ROUTING_LAYER] || $MAX_ROUTING_LAYER eq ""} {
  set MAX_ROUTING_LAYER metal7
}

# Layer names for GUI visualization
set VIZ_METAL_LAYERS {metal2 metal3 metal4 metal5 metal6 metal7}
set VIZ_VIA_LAYERS   {via1 via2 via3 via4 via5 via6}

# --- Platform Procedures ---

# Tapcell insertion
proc platform_tapcell {} {
  tapcell \
    -distance 120 \
    -tapcell_master "TAPCELL_X1" \
    -endcap_master "TAPCELL_X1"
}

# Power Distribution Network
# check_size: if 1, skip upper-metal straps when core is too small
proc platform_pdn {{check_size 1}} {
  add_global_connection -net VDD -inst_pattern .* -pin_pattern {^VDD$} -power
  add_global_connection -net VDD -inst_pattern .* -pin_pattern {^VDDPE$}
  add_global_connection -net VDD -inst_pattern .* -pin_pattern {^VDDCE$}
  add_global_connection -net VSS -inst_pattern .* -pin_pattern {^VSS$} -ground
  add_global_connection -net VSS -inst_pattern .* -pin_pattern {^VSSE$}

  set_voltage_domain -power VDD -ground VSS

  define_pdn_grid -name "Core"
  add_pdn_stripe -followpins -layer metal1 -width 0.17

  if {$check_size} {
    set core_area [ord::get_db_core]
    set core_width [expr {([$core_area xMax] - [$core_area xMin]) / 1000.0}]
    set core_height [expr {([$core_area yMax] - [$core_area yMin]) / 1000.0}]
    puts "PDN: core dimensions = ${core_width} x ${core_height} um"

    if {$core_width > 30.0 && $core_height > 30.0} {
      add_pdn_stripe -layer metal4 -width 0.48 -pitch 56.0 -offset 2
      add_pdn_stripe -layer metal7 -width 1.40 -pitch 40.0 -offset 2
      add_pdn_connect -layers {metal1 metal4}
      add_pdn_connect -layers {metal4 metal7}
    } else {
      puts "PDN: core too small for metal4/metal7 straps, using followpins only"
    }
  } else {
    add_pdn_stripe -layer metal4 -width 0.48 -pitch 56.0 -offset 2
    add_pdn_stripe -layer metal7 -width 1.40 -pitch 40.0 -offset 2
    add_pdn_connect -layers {metal1 metal4}
    add_pdn_connect -layers {metal4 metal7}
  }

  pdngen
}

# Routing layer configuration
proc platform_routing_setup {} {
  global MIN_ROUTING_LAYER MAX_ROUTING_LAYER
  set_routing_layers \
    -signal ${MIN_ROUTING_LAYER}-${MAX_ROUTING_LAYER} \
    -clock metal3-${MAX_ROUTING_LAYER}

  set_global_routing_layer_adjustment metal2 0.8
  set_global_routing_layer_adjustment metal3 0.7
  set_global_routing_layer_adjustment metal4-${MAX_ROUTING_LAYER} 0.25

  set_macro_extension 2
}
