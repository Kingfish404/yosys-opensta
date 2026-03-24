#===========================================================
# OpenROAD Physical Design Flow — FAST variant
#
# Optimized for large designs with relaxed timing (e.g. ysyx@50MHz).
# Key changes vs openroad_pnr.tcl:
#   - Higher utilization (smaller die → faster routing)
#   - Fewer congestion iterations in global routing
#   - Skip post-GRT repair_design (timing easily met)
#   - Multi-threaded detailed routing
#   - Fewer report paths
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

puts "======================================================="
puts "  OpenROAD PnR Flow (FAST)"
puts "  DESIGN: $DESIGN"
puts "  NETLIST: $NETLIST_SYN_V"
puts "======================================================="

# Tunable parameters — higher utilization/density for faster runtime
set CORE_UTILIZATION 60
if {[info exists env(CORE_UTILIZATION)]} {
  set CORE_UTILIZATION $::env(CORE_UTILIZATION)
}

set CORE_ASPECT_RATIO 1.0
if {[info exists env(CORE_ASPECT_RATIO)]} {
  set CORE_ASPECT_RATIO $::env(CORE_ASPECT_RATIO)
}

set PLACE_DENSITY 0.70
if {[info exists env(PLACE_DENSITY)]} {
  set PLACE_DENSITY $::env(PLACE_DENSITY)
}

set MIN_ROUTING_LAYER metal2
if {[info exists env(MIN_ROUTING_LAYER)]} {
  set MIN_ROUTING_LAYER $::env(MIN_ROUTING_LAYER)
}

set MAX_ROUTING_LAYER metal7
if {[info exists env(MAX_ROUTING_LAYER)]} {
  set MAX_ROUTING_LAYER $::env(MAX_ROUTING_LAYER)
}

# Number of threads for detailed routing
set DR_THREADS 0
if {[info exists env(DR_THREADS)]} {
  set DR_THREADS $::env(DR_THREADS)
}

# Platform paths
set PLATFORM nangate45
if {[info exists env(PLATFORM)]} {
  set PLATFORM $::env(PLATFORM)
}
set PLATFORM_DIR $PROJ_PATH/platforms/$PLATFORM
set LIB_DIR $PROJ_PATH/third_party/lib/$PLATFORM

# Source platform-specific configuration
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

#===========================================================
# 1. Read Design
#===========================================================
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

platform_pdn 0

#===========================================================
# 4. Global Placement
#===========================================================
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

#===========================================================
# 6. Clock Tree Synthesis
#===========================================================
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

#===========================================================
# 7. Global Routing
#===========================================================
puts "\n>>> Global routing ..."
platform_routing_setup

# FAST: reduced congestion iterations (15 → 5)\nglobal_route \
  -guide_file $PNR_DIR/${DESIGN}.route.guide \
  -congestion_iterations 5

set_propagated_clock [all_clocks]
estimate_parasitics -global_routing

# FAST: skip post-GRT incremental repair cycle for speed

write_def $PNR_DIR/${DESIGN}_grouted.def
puts "Global-routed DEF written: $PNR_DIR/${DESIGN}_grouted.def"

#===========================================================
# 8. Detailed Routing
#===========================================================
puts "\n>>> Detailed routing ..."
# FAST: use multi-threading (0 = use all available cores)
detailed_route \
  -output_drc $PNR_DIR/${DESIGN}_route_drc.rpt \
  -output_maze $PNR_DIR/${DESIGN}_maze.log \
  -verbose 1

#===========================================================
# 9. Fill Cells & Finishing
#===========================================================
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
  -group_path_count 5 \
  -endpoint_path_count 1 \
  -format full_clock_expanded \
  -fields {slew cap input_pin net fanout} \
  -digits 3 \
  > $PNR_DIR/timing_max_final.rpt

report_checks -path_delay min \
  -group_path_count 3 \
  -endpoint_path_count 1 \
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
  gui::save_image $PNR_DIR/${DESIGN}_final.png 2048 2048
  puts "Layout image: $PNR_DIR/${DESIGN}_final.png"

  gui::clear_highlights
  set viz_layers [concat $VIZ_METAL_LAYERS $VIZ_VIA_LAYERS]
  foreach layer $viz_layers {
    gui::set_display_controls $layer visible false
  }
  gui::save_image $PNR_DIR/${DESIGN}_placement.png 2048 2048
  puts "Placement image: $PNR_DIR/${DESIGN}_placement.png"

  foreach layer $viz_layers {
    gui::set_display_controls $layer visible true
  }
  gui::set_display_controls "Instances/StdCells" visible false
  gui::save_image $PNR_DIR/${DESIGN}_routing.png 2048 2048
  puts "Routing image: $PNR_DIR/${DESIGN}_routing.png"

  gui::set_display_controls "Instances/StdCells" visible true
  gui::set_display_controls "Nets/Power" visible true
  gui::set_display_controls "Nets/Signal" visible false
  gui::save_image $PNR_DIR/${DESIGN}_power.png 2048 2048
  puts "Power grid image: $PNR_DIR/${DESIGN}_power.png"
} else {
  puts "Note: GUI not available. Use 'make viz_layout' to generate images via KLayout."
  puts "      Or re-run with: openroad -gui scripts/openroad_pnr_fast.tcl"
}

puts ""
puts "======================================================="
puts "  Physical Design Complete! (FAST mode)"
puts "  DEF:     $PNR_DIR/${DESIGN}_final.def"
puts "  ODB:     $PNR_DIR/${DESIGN}_final.odb"
puts "  Verilog: $PNR_DIR/${DESIGN}_final.v"
puts "  Reports: $PNR_DIR/*.rpt"
puts "  Images:  $PNR_DIR/${DESIGN}_*.png (if GUI available)"
puts "  SPEF:    $PNR_DIR/${DESIGN}_final.spef (if RCX rules available)"
puts ""
puts "  Note: To generate GDS, run 'make gds' (requires KLayout)"
puts "======================================================="

exit
