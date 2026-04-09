#===========================================================
# OpenROAD Physical Design Flow — Common Implementation
#
# This file contains the shared PnR flow logic.
# It is sourced by openroad_pnr.tcl and openroad_pnr_fast.tcl
# after they set mode-specific default variables:
#
#   PNR_MODE                  - "standard" or "fast"
#   _DEFAULT_CORE_UTILIZATION - default core utilization %
#   _DEFAULT_PLACE_DENSITY    - default placement density
#   _PDN_CHECK_SIZE           - 1 to skip upper-metal straps on small cores
#   _GRT_CONGESTION_ITERS     - global routing congestion iterations
#   _SKIP_POST_GRT_REPAIR     - 1 to skip post-GRT incremental repair
#   _RPT_MAX_GROUP_COUNT      - report_checks group_path_count (max delay)
#   _RPT_MAX_ENDPOINT_COUNT   - report_checks endpoint_path_count (max delay)
#   _RPT_MIN_GROUP_COUNT      - report_checks group_path_count (min delay)
#   _RPT_MIN_ENDPOINT_COUNT   - report_checks endpoint_path_count (min delay)
#
# Optional resume support:
#   PNR_RESUME_FROM env var   - stage name to resume from (skip earlier stages)
#                               Valid: floorplan, place, cts, route, finish
#                               Requires the corresponding ODB checkpoint to exist.
#
# Input:  result/<DESIGN>-<FREQ>MHz/<DESIGN>.netlist.syn.v
#         result/<DESIGN>-<FREQ>MHz/<DESIGN>.netlist.syn.v.sdc (optional)
# Output: result/<DESIGN>-<FREQ>MHz-pnr/<DESIGN>_final.{def,odb,v}
#===========================================================

# === Environment / Configuration ===
set PROJ_PATH /data
if {[info exists env(PROJ_PATH)]} {
  set PROJ_PATH $::env(PROJ_PATH)
} else {
  puts "Warning: Environment PROJ_PATH is not defined. Use $PROJ_PATH by default."
}

set DESIGN      $::env(DESIGN)
set RESULT_DIR  $::env(RESULT_DIR)
set NETLIST_SYN_V $::env(NETLIST_SYN_V)

set _mode_label ""
if {$PNR_MODE eq "fast"} { set _mode_label " (FAST)" }

puts "======================================================="
puts "  OpenROAD PnR Flow${_mode_label}"
puts "  DESIGN: $DESIGN"
puts "  NETLIST: $NETLIST_SYN_V"
puts "======================================================="

# Tunable parameters: use env override, else mode-specific default
set CORE_UTILIZATION $_DEFAULT_CORE_UTILIZATION
if {[info exists env(CORE_UTILIZATION)]} {
  set CORE_UTILIZATION $::env(CORE_UTILIZATION)
}

set CORE_ASPECT_RATIO 1.0
if {[info exists env(CORE_ASPECT_RATIO)]} {
  set CORE_ASPECT_RATIO $::env(CORE_ASPECT_RATIO)
}

set PLACE_DENSITY $_DEFAULT_PLACE_DENSITY
if {[info exists env(PLACE_DENSITY)]} {
  set PLACE_DENSITY $::env(PLACE_DENSITY)
}

# Routing layers: read from env if present; otherwise let config.tcl set them
if {[info exists env(MIN_ROUTING_LAYER)]} {
  set MIN_ROUTING_LAYER $::env(MIN_ROUTING_LAYER)
}

if {[info exists env(MAX_ROUTING_LAYER)]} {
  set MAX_ROUTING_LAYER $::env(MAX_ROUTING_LAYER)
}

# Platform paths
set PLATFORM nangate45
if {[info exists env(PLATFORM)]} {
  set PLATFORM $::env(PLATFORM)
}
set PLATFORM_DIR $PROJ_PATH/platforms/$PLATFORM
set LIB_DIR $PROJ_PATH/third_party/lib/$PLATFORM

# Source platform-specific configuration (sets TECH_LEF, SC_LEF, LIB_FILE,
# PLACE_SITE, FILL_CELLS, DONT_USE_CELLS, CTS_BUF_CELL, CTS_BUF_LIST,
# PIN_HOR_LAYER, PIN_VER_LAYER, SET_RC_TCL, and defines platform_tapcell,
# platform_pdn, platform_routing_setup procs)
source $PLATFORM_DIR/config.tcl

# Input / Output paths
set NETLIST_FILE $PROJ_PATH/$RESULT_DIR/$NETLIST_SYN_V
set SDC_FILE     $PROJ_PATH/$RESULT_DIR/${NETLIST_SYN_V}.sdc
if {[info exists env(PNR_RESULT_DIR)]} {
  set PNR_DIR $PROJ_PATH/$::env(PNR_RESULT_DIR)
} else {
  set PNR_DIR $PROJ_PATH/$RESULT_DIR/pnr
}
file mkdir $PNR_DIR

# === Stage resume support ===
# Map stage names to numeric order for comparison
array set _STAGE_ORDER {
  "" 0
  floorplan 1
  place 2
  cts 3
  route 4
  finish 5
}

set _resume_from ""
if {[info exists env(PNR_RESUME_FROM)]} {
  set _resume_from $::env(PNR_RESUME_FROM)
}

# Validate resume stage
if {$_resume_from ne "" && ![info exists _STAGE_ORDER($_resume_from)]} {
  puts "Error: Invalid PNR_RESUME_FROM='$_resume_from'. Valid: floorplan, place, cts, route, finish"
  exit 1
}

set _resume_order 0
if {$_resume_from ne ""} {
  set _resume_order $_STAGE_ORDER($_resume_from)
}

# Helper: returns 1 if stage should run (not skipped by resume)
proc _should_run_stage {stage_name} {
  upvar _STAGE_ORDER so
  upvar _resume_order ro
  return [expr {$so($stage_name) >= $ro}]
}

# If resuming, load the checkpoint ODB from the previous stage
if {$_resume_from ne ""} {
  # Determine which checkpoint to load
  set _ckpt_map [dict create \
    floorplan "" \
    place     "1_floorplan.odb" \
    cts       "2_place.odb" \
    route     "3_cts.odb" \
    finish    "4_route.odb" \
  ]
  set _ckpt [dict get $_ckpt_map $_resume_from]
  if {$_ckpt ne ""} {
    set _ckpt_file $PNR_DIR/$_ckpt
    if {![file exists $_ckpt_file]} {
      puts "Error: Checkpoint not found: $_ckpt_file"
      puts "  Run earlier stages first, or use PNR_RESUME_FROM with an earlier stage."
      exit 1
    }
    puts "\n>>> Resuming from stage '$_resume_from' — loading $_ckpt_file ..."
    read_db $_ckpt_file
  }
}

#===========================================================
# 1. Read Design
#===========================================================
if {[_should_run_stage floorplan]} {
puts "\n>>> Reading LEF / Liberty / Verilog ..."
read_lef $TECH_LEF
read_lef $SC_LEF
foreach lib $LIB_FILES {
  read_liberty $lib
}
read_verilog $NETLIST_FILE
link_design $DESIGN

# Read SDC (from STA step) or create minimal constraints
if {[file exists $SDC_FILE]} {
  read_sdc $SDC_FILE
  puts "Read SDC: $SDC_FILE"
} else {
  puts "Warning: SDC not found ($SDC_FILE), creating inline constraints"
  if {![info exists TIME_SCALE]} { set TIME_SCALE 1000.0 }
  set CLK_FREQ_MHZ 50
  if {[info exists env(CLK_FREQ_MHZ)]} {
    set CLK_FREQ_MHZ $::env(CLK_FREQ_MHZ)
  }
  set clk_port_name clock
  if {[info exists env(CLK_PORT_NAME)]} {
    set clk_port_name $::env(CLK_PORT_NAME)
  }
  create_clock -name core_clock \
    -period [expr {$TIME_SCALE / $CLK_FREQ_MHZ}] \
    [get_ports $clk_port_name]
}

#===========================================================
# 2. Floorplan
#===========================================================
puts "\n>>> Initializing floorplan ..."
initialize_floorplan \
  -utilization $CORE_UTILIZATION \
  -aspect_ratio $CORE_ASPECT_RATIO \
  -core_space 2 \
  -site $PLACE_SITE

platform_make_tracks

# Set layer RC for parasitics estimation
source $SET_RC_TCL

# Apply IO pin constraints (if provided)
set PIN_CONSTRAINT_FILE ""
if {[info exists env(PIN_CONSTRAINT_FILE)] && $::env(PIN_CONSTRAINT_FILE) ne ""} {
  set PIN_CONSTRAINT_FILE $PROJ_PATH/$::env(PIN_CONSTRAINT_FILE)
  if {[file exists $PIN_CONSTRAINT_FILE]} {
    puts "Sourcing pin constraints: $PIN_CONSTRAINT_FILE"
    source $PIN_CONSTRAINT_FILE
  } else {
    puts "Warning: PIN_CONSTRAINT_FILE not found: $PIN_CONSTRAINT_FILE"
  }
}

# Place IO pins
place_pins -hor_layers $PIN_HOR_LAYER -ver_layers $PIN_VER_LAYER

# Repair high-fanout tie cells
puts "Repair tie lo fanout..."
set tielo_cell_name [lindex $TIELO_CELL_AND_PORT 0]
if {[info exists TIELO_CELL_AND_PORT] && $tielo_cell_name ne ""} {
  set tielo_lib_name [get_name [get_property [lindex [get_lib_cell $tielo_cell_name] 0] library]]
  set tielo_pin $tielo_lib_name/$tielo_cell_name/[lindex $TIELO_CELL_AND_PORT 1]
  repair_tie_fanout $tielo_pin
}
puts "Repair tie hi fanout..."
set tiehi_cell_name [lindex $TIEHI_CELL_AND_PORT 0]
if {[info exists TIEHI_CELL_AND_PORT] && $tiehi_cell_name ne ""} {
  set tiehi_lib_name [get_name [get_property [lindex [get_lib_cell $tiehi_cell_name] 0] library]]
  set tiehi_pin $tiehi_lib_name/$tiehi_cell_name/[lindex $TIEHI_CELL_AND_PORT 1]
  repair_tie_fanout $tiehi_pin
}

# Tap cells
platform_tapcell

write_def $PNR_DIR/${DESIGN}_floorplan.def
puts "Floorplan DEF written: $PNR_DIR/${DESIGN}_floorplan.def"

#===========================================================
# 3. Power Distribution Network
#===========================================================
puts "\n>>> Generating PDN ..."

platform_pdn $_PDN_CHECK_SIZE

# Save floorplan checkpoint
write_db $PNR_DIR/1_floorplan.odb
puts "Checkpoint: $PNR_DIR/1_floorplan.odb"
}; # end floorplan stage

#===========================================================
# 4. Global Placement
#===========================================================
if {[_should_run_stage place]} {
puts "\n>>> Global placement ..."
foreach cell $DONT_USE_CELLS {
  set_dont_use [get_lib_cells */$cell]
}

global_placement -density $PLACE_DENSITY

# Estimate parasitics for timing-driven optimization
estimate_parasitics -placement

# Gate resizing and buffer insertion
repair_design

#===========================================================
# 5. Detailed Placement
#===========================================================
puts "\n>>> Detailed placement ..."
detailed_placement
check_placement -verbose

puts "\n--- Post-Placement Reports ---"
report_design_area

write_def $PNR_DIR/${DESIGN}_placed.def
puts "Placed DEF written: $PNR_DIR/${DESIGN}_placed.def"

# Save placement checkpoint
write_db $PNR_DIR/2_place.odb
puts "Checkpoint: $PNR_DIR/2_place.odb"
}; # end place stage

#===========================================================
# 6. Clock Tree Synthesis
#===========================================================
if {[_should_run_stage cts]} {
puts "\n>>> Clock Tree Synthesis ..."
clock_tree_synthesis \
  -root_buf $CTS_BUF_CELL \
  -buf_list $CTS_BUF_LIST \
  -sink_clustering_enable

repair_clock_nets
detailed_placement

estimate_parasitics -placement

# Post-CTS timing repair (setup and hold)
puts "\n>>> Post-CTS repair timing ..."
repair_timing -setup
repair_timing -hold
detailed_placement
check_placement -verbose

estimate_parasitics -placement
puts "\n--- Post-CTS Reports ---"
report_checks -path_delay min_max -format full_clock_expanded -digits 3
report_clock_skew

write_def $PNR_DIR/${DESIGN}_cts.def
puts "CTS DEF written: $PNR_DIR/${DESIGN}_cts.def"

# Save CTS checkpoint
write_db $PNR_DIR/3_cts.odb
puts "Checkpoint: $PNR_DIR/3_cts.odb"
}; # end cts stage

#===========================================================
# 7. Global Routing
#===========================================================
if {[_should_run_stage route]} {
puts "\n>>> Global routing ..."
platform_routing_setup

global_route \
  -guide_file $PNR_DIR/${DESIGN}.route.guide \
  -congestion_iterations $_GRT_CONGESTION_ITERS

set_propagated_clock [all_clocks]
estimate_parasitics -global_routing

if {!$_SKIP_POST_GRT_REPAIR} {
  # Post-GRT incremental repair cycle
  puts "\n>>> Post-GRT repair design ..."
  repair_design

  # Fix overlaps from repair, then incrementally re-route modified nets
  global_route -start_incremental
  detailed_placement
  global_route -end_incremental \
    -congestion_iterations $_GRT_CONGESTION_ITERS

  puts "\n>>> Post-GRT repair timing ..."
  estimate_parasitics -global_routing
  repair_timing -setup
  repair_timing -hold

  # Fix overlaps again and incrementally re-route
  global_route -start_incremental
  detailed_placement
  global_route -end_incremental \
    -congestion_iterations $_GRT_CONGESTION_ITERS

  estimate_parasitics -global_routing
}

write_def $PNR_DIR/${DESIGN}_grouted.def
puts "Global-routed DEF written: $PNR_DIR/${DESIGN}_grouted.def"

#===========================================================
# 8. Detailed Routing
#===========================================================
puts "\n>>> Detailed routing ..."
detailed_route \
  -output_drc $PNR_DIR/${DESIGN}_route_drc.rpt \
  -output_maze $PNR_DIR/${DESIGN}_maze.log \
  -verbose 1

# Save route checkpoint
write_db $PNR_DIR/4_route.odb
puts "Checkpoint: $PNR_DIR/4_route.odb"
}; # end route stage

#===========================================================
# 9. Fill Cells & Finishing
#===========================================================
if {[_should_run_stage finish]} {
puts "\n>>> Inserting filler cells ..."
filler_placement $FILL_CELLS
check_placement

#===========================================================
# 9b. Parasitics Extraction (OpenRCX)
#===========================================================
puts "\n>>> Extracting parasitics (OpenRCX) ..."
set RCX_RULES $LIB_DIR/rcx_patterns.rules
if {[file exists $RCX_RULES]} {
  define_process_corner -ext_model_index 0 X
  extract_parasitics -ext_model_file $RCX_RULES
  write_spef $PNR_DIR/${DESIGN}_final.spef
  puts "SPEF written: $PNR_DIR/${DESIGN}_final.spef"
  # Use extracted parasitics for final reports
  read_spef $PNR_DIR/${DESIGN}_final.spef
} else {
  puts "Warning: RCX rules not found ($RCX_RULES), using estimated parasitics"
  estimate_parasitics -global_routing
}

#===========================================================
# 10. Final Reports
#===========================================================
puts "\n>>> Generating final reports ..."

report_checks -path_delay max \
  -group_path_count $_RPT_MAX_GROUP_COUNT \
  -endpoint_path_count $_RPT_MAX_ENDPOINT_COUNT \
  -format full_clock_expanded \
  -fields {slew cap input_pin net fanout} \
  -digits 3 \
  > $PNR_DIR/timing_max_final.rpt

report_checks -path_delay min \
  -group_path_count $_RPT_MIN_GROUP_COUNT \
  -endpoint_path_count $_RPT_MIN_ENDPOINT_COUNT \
  -format full_clock_expanded \
  -fields {slew cap input_pin net fanout} \
  -digits 3 \
  > $PNR_DIR/timing_min_final.rpt

report_check_types -max_delay -min_delay -violators \
  > $PNR_DIR/timing_violators.rpt

report_power  > $PNR_DIR/power_final.rpt

set area_rpt [open $PNR_DIR/area_final.rpt w]
puts $area_rpt "=== Design Area ==="
close $area_rpt
report_design_area >> $PNR_DIR/area_final.rpt

report_clock_skew > $PNR_DIR/clock_skew_final.rpt

check_antennas -report_file $PNR_DIR/antenna_final.rpt

#===========================================================
# 11. Write Final Outputs
#===========================================================
puts "\n>>> Writing final outputs ..."
write_def $PNR_DIR/${DESIGN}_final.def
write_db  $PNR_DIR/${DESIGN}_final.odb
write_verilog $PNR_DIR/${DESIGN}_final.v

#===========================================================
# 12. Generate Layout Images (headless GUI rendering)
#===========================================================
puts "\n>>> Generating layout images ..."

if {[namespace exists ::gui] && [info commands gui::initialized] ne "" && [gui::initialized]} {
  # Full layout view
  gui::save_image $PNR_DIR/${DESIGN}_final.png 2048 2048
  puts "Layout image: $PNR_DIR/${DESIGN}_final.png"

  # Placement heatmap (hide routing layers)
  gui::clear_highlights
  set viz_layers [concat $VIZ_METAL_LAYERS $VIZ_VIA_LAYERS]
  foreach layer $viz_layers {
    gui::set_display_controls $layer visible false
  }
  gui::save_image $PNR_DIR/${DESIGN}_placement.png 2048 2048
  puts "Placement image: $PNR_DIR/${DESIGN}_placement.png"

  # Routing-only view (hide cells)
  foreach layer $viz_layers {
    gui::set_display_controls $layer visible true
  }
  gui::set_display_controls "Instances/StdCells" visible false
  gui::save_image $PNR_DIR/${DESIGN}_routing.png 2048 2048
  puts "Routing image: $PNR_DIR/${DESIGN}_routing.png"

  # Power grid view
  gui::set_display_controls "Instances/StdCells" visible true
  gui::set_display_controls "Nets/Power" visible true
  gui::set_display_controls "Nets/Signal" visible false
  gui::save_image $PNR_DIR/${DESIGN}_power.png 2048 2048
  puts "Power grid image: $PNR_DIR/${DESIGN}_power.png"
} else {
  puts "Note: GUI not available. Use 'make viz_layout' to generate images via KLayout."
  puts "      Or re-run with: openroad -gui scripts/openroad_pnr.tcl"
}

puts ""
puts "======================================================="
puts "  Physical Design Complete!${_mode_label}"
puts "  DEF:     $PNR_DIR/${DESIGN}_final.def"
puts "  ODB:     $PNR_DIR/${DESIGN}_final.odb"
puts "  Verilog: $PNR_DIR/${DESIGN}_final.v"
puts "  Reports: $PNR_DIR/*.rpt"
puts "  Images:  $PNR_DIR/${DESIGN}_*.png (if GUI available)"
puts "  SPEF:    $PNR_DIR/${DESIGN}_final.spef (if RCX rules available)"
puts ""
puts "  Note: To generate GDS, run 'make gds' (requires KLayout)"
puts "======================================================="
}; # end finish stage

exit
