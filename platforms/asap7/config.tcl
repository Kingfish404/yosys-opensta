# ASAP7 Platform Configuration for OpenROAD / OpenSTA scripts
# Requires: PLATFORM_DIR and LIB_DIR are set before sourcing this file
#   PLATFORM_DIR = platforms/asap7 (build configs)
#   LIB_DIR      = lib/asap7       (downloaded PDK data)

# Technology files
set TECH_LEF     $LIB_DIR/lef/asap7_tech_1x_201209.lef
set SC_LEF       $LIB_DIR/lef/asap7sc7p5t_28_R_1x_220121a.lef
set LIB_FILE     $LIB_DIR/lib/merged.lib

# RC extraction configuration (sourced by PnR scripts)
set SET_RC_TCL   $PLATFORM_DIR/setRC.tcl

# Placement site
set PLACE_SITE   asap7sc7p5t

# Cell configuration (RVT cells)
set FILL_CELLS     "FILLERxp5_ASAP7_75t_R FILLER_ASAP7_75t_R DECAPx1_ASAP7_75t_R DECAPx2_ASAP7_75t_R DECAPx4_ASAP7_75t_R DECAPx6_ASAP7_75t_R DECAPx10_ASAP7_75t_R"
set DONT_USE_CELLS {*x1p*_ASAP7* *xp*_ASAP7* SDF* ICG*}
set CTS_BUF_CELL   BUFx4_ASAP7_75t_R
set CTS_BUF_LIST   {BUFx4_ASAP7_75t_R BUFx12f_ASAP7_75t_R BUFx24_ASAP7_75t_R}

# Pin placement layers
set PIN_HOR_LAYER  M4
set PIN_VER_LAYER  M5

# Default routing layers (can be overridden by env vars before sourcing)
if {![info exists MIN_ROUTING_LAYER] || $MIN_ROUTING_LAYER eq ""} {
  set MIN_ROUTING_LAYER M2
}
if {![info exists MAX_ROUTING_LAYER] || $MAX_ROUTING_LAYER eq ""} {
  set MAX_ROUTING_LAYER M7
}

# Layer names for GUI visualization
set VIZ_METAL_LAYERS {M2 M3 M4 M5 M6 M7}
set VIZ_VIA_LAYERS   {V1 V2 V3 V4 V5 V6}

# --- Platform Procedures ---

# Tapcell insertion
proc platform_tapcell {} {
  tapcell \
    -distance 25 \
    -tapcell_master "TAPCELL_ASAP7_75t_R" \
    -endcap_master "TAPCELL_ASAP7_75t_R"
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

  define_pdn_grid -name "Core" -pins {M6}
  add_pdn_stripe -followpins -layer M1 -width 0.018
  add_pdn_stripe -followpins -layer M2 -width 0.018

  if {$check_size} {
    set core_area [ord::get_db_core]
    set core_width [expr {([$core_area xMax] - [$core_area xMin]) / 1000.0}]
    set core_height [expr {([$core_area yMax] - [$core_area yMin]) / 1000.0}]
    puts "PDN: core dimensions = ${core_width} x ${core_height} um"

    if {$core_width > 5.0 && $core_height > 5.0} {
      add_pdn_stripe -layer M5 -width 0.12 -spacing 0.072 -pitch 5.4 -offset 0.300
      add_pdn_stripe -layer M6 -width 0.288 -spacing 0.096 -pitch 5.4 -offset 0.513
      add_pdn_connect -layers {M1 M2}
      add_pdn_connect -layers {M2 M5}
      add_pdn_connect -layers {M5 M6}
    } else {
      puts "PDN: core too small for M5/M6 straps, using followpins only"
      add_pdn_connect -layers {M1 M2}
    }
  } else {
    add_pdn_stripe -layer M5 -width 0.12 -spacing 0.072 -pitch 5.4 -offset 0.300
    add_pdn_stripe -layer M6 -width 0.288 -spacing 0.096 -pitch 5.4 -offset 0.513
    add_pdn_connect -layers {M1 M2}
    add_pdn_connect -layers {M2 M5}
    add_pdn_connect -layers {M5 M6}
  }

  pdngen
}

# Routing layer configuration
proc platform_routing_setup {} {
  global MIN_ROUTING_LAYER MAX_ROUTING_LAYER
  set_routing_layers \
    -signal ${MIN_ROUTING_LAYER}-${MAX_ROUTING_LAYER} \
    -clock M4-${MAX_ROUTING_LAYER}

  set_global_routing_layer_adjustment ${MIN_ROUTING_LAYER}-${MAX_ROUTING_LAYER} 0.25

  set_macro_extension 2
}
