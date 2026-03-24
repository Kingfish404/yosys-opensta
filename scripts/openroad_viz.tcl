#===========================================================
# OpenROAD Layout Visualization (headless)
#
# Loads an ODB or DEF from the PnR results and generates
# PNG images of the chip layout at each stage.
#
# Usage: openroad -gui -exit scripts/openroad_viz.tcl
#   (requires X11 / Xvfb for headless rendering)
#
# Environment variables:
#   PROJ_PATH, DESIGN, PNR_RESULT_DIR
#   IMG_WIDTH (default 2048), IMG_HEIGHT (default 2048)
#===========================================================

set PROJ_PATH /data
if {[info exists env(PROJ_PATH)]} {
  set PROJ_PATH $::env(PROJ_PATH)
}

set DESIGN      $::env(DESIGN)
set PNR_RESULT_DIR $::env(PNR_RESULT_DIR)

set PLATFORM nangate45
if {[info exists env(PLATFORM)]} {
  set PLATFORM $::env(PLATFORM)
}
set PLATFORM_DIR $PROJ_PATH/platforms/$PLATFORM
set LIB_DIR $PROJ_PATH/third_party/lib/$PLATFORM

# Source platform-specific configuration
source $PLATFORM_DIR/config.tcl

set PNR_DIR $PROJ_PATH/$PNR_RESULT_DIR
set IMG_DIR $PROJ_PATH/$PNR_RESULT_DIR/images
file mkdir $IMG_DIR

set IMG_W 2048
set IMG_H 2048
if {[info exists env(IMG_WIDTH)]}  { set IMG_W $::env(IMG_WIDTH) }
if {[info exists env(IMG_HEIGHT)]} { set IMG_H $::env(IMG_HEIGHT) }

puts "======================================================="
puts "  OpenROAD Layout Visualization"
puts "  DESIGN:  $DESIGN"
puts "  PNR_DIR: $PNR_DIR"
puts "  IMG_DIR: $IMG_DIR"
puts "  Size:    ${IMG_W}x${IMG_H}"
puts "======================================================="

# Read LEF/Liberty for cell geometry
read_lef $TECH_LEF
read_lef $SC_LEF
read_liberty $LIB_FILE

# Helper: load a DEF stage, render images
proc render_stage {stage def_file img_dir design img_w img_h} {
  if {![file exists $def_file]} {
    puts "  Skip $stage: $def_file not found"
    return
  }
  puts "\n>>> Rendering stage: $stage ..."
  read_def $def_file

  gui::fit

  # Full view
  save_image -width $img_w $img_dir/${design}_${stage}_full.png
  puts "  -> $img_dir/${design}_${stage}_full.png"
}

# Helper: load ODB and render comprehensive views
proc render_odb {odb_file img_dir design img_w img_h} {
  if {![file exists $odb_file]} {
    puts "  ODB not found: $odb_file"
    return
  }
  puts "\n>>> Loading ODB: $odb_file"
  read_db $odb_file

  gui::fit

  # 1. Full chip view (all layers)
  save_image -width $img_w $img_dir/${design}_chip_full.png
  puts "  -> ${design}_chip_full.png"

  # 2. Placement view (cells + metal1 only)
  foreach layer {metal2 metal3 metal4 metal5 metal6 metal7 \
                 via1 via2 via3 via4 via5 via6} {
    catch {gui::set_display_controls $layer visible false}
  }
  save_image -width $img_w $img_dir/${design}_chip_placement.png
  puts "  -> ${design}_chip_placement.png"

  # 3. Routing view (show routing, dim cells)
  foreach layer {metal2 metal3 metal4 metal5 metal6 metal7 \
                 via1 via2 via3 via4 via5 via6} {
    catch {gui::set_display_controls $layer visible true}
  }
  catch {gui::set_display_controls "Instances/StdCells" visible false}
  save_image -width $img_w $img_dir/${design}_chip_routing.png
  puts "  -> ${design}_chip_routing.png"

  # 4. Power grid view
  catch {gui::set_display_controls "Instances/StdCells" visible true}
  catch {gui::set_display_controls "Nets/Power" visible true}
  catch {gui::set_display_controls "Nets/Signal" visible false}
  save_image -width $img_w $img_dir/${design}_chip_power.png
  puts "  -> ${design}_chip_power.png"

  # 5. Clock tree view
  catch {gui::set_display_controls "Nets/Signal" visible false}
  catch {gui::set_display_controls "Nets/Power" visible false}
  catch {gui::set_display_controls "Nets/Clock" visible true}
  save_image -width $img_w $img_dir/${design}_chip_clock.png
  puts "  -> ${design}_chip_clock.png"

  # Restore defaults
  catch {gui::set_display_controls "Nets/Signal" visible true}
  catch {gui::set_display_controls "Nets/Power" visible true}
  catch {gui::set_display_controls "Instances/StdCells" visible true}
}

# --- Render per-stage DEFs ---
foreach {stage suffix} {
  floorplan _floorplan.def
  placed    _placed.def
  cts       _cts.def
  grouted   _grouted.def
  final     _final.def
} {
  set def_path $PNR_DIR/${DESIGN}${suffix}
  render_stage $stage $def_path $IMG_DIR $DESIGN $IMG_W $IMG_H
}

# --- Render comprehensive views from final ODB ---
set odb_path $PNR_DIR/${DESIGN}_final.odb
render_odb $odb_path $IMG_DIR $DESIGN $IMG_W $IMG_H

puts ""
puts "======================================================="
puts "  Layout images generated in: $IMG_DIR/"
puts "======================================================="

exit
