#===========================================================
# Export ODB to PNG visualization
#
# Usage:
#   openroad -gui -exit scripts/export_odb_webp.tcl \
#     -ODB /path/to/design.odb [-OUT /path/to/output.png] \
#     [-WIDTH 2048] [-HEIGHT 2048]
#
# Or via environment variables:
#   ODB=/path/to/design.odb openroad -gui -exit scripts/export_odb_webp.tcl
#===========================================================

# --- Parse command-line arguments ---
proc parse_args {argv} {
  set result [dict create]
  foreach arg $argv {
    if {[regexp {^-?(\w+)=(.+)$} $arg -> key val]} {
      dict set result $key $val
    }
  }
  return $result
}

set args_dict [parse_args $argv]

# ODB path
if {[dict exists $args_dict ODB]} {
  set ODB_FILE [dict get $args_dict ODB]
} elseif {[info exists env(ODB)]} {
  set ODB_FILE $::env(ODB)
} else {
  puts "Error: ODB path not specified. Use -ODB=<path> or set ODB env var."
  exit 1
}

# Output path (default: same directory, .png extension)
if {[dict exists $args_dict OUT]} {
  set OUT_FILE [dict get $args_dict OUT]
} elseif {[info exists env(OUT)]} {
  set OUT_FILE $::env(OUT)
} else {
  set OUT_FILE "[file rootname $ODB_FILE].png"
}

# Image dimensions
set IMG_W 2048
set IMG_H 2048
if {[dict exists $args_dict WIDTH]}  { set IMG_W [dict get $args_dict WIDTH] }
if {[dict exists $args_dict HEIGHT]} { set IMG_H [dict get $args_dict HEIGHT] }
if {[info exists env(WIDTH)]}  { set IMG_W $::env(WIDTH) }
if {[info exists env(HEIGHT)]} { set IMG_H $::env(HEIGHT) }

puts "======================================================="
puts "  Export ODB to PNG"
puts "  ODB:    $ODB_FILE"
puts "  OUT:    $OUT_FILE"
puts "  Size:   ${IMG_W}x${IMG_H}"
puts "======================================================="

# --- Validate input ---
if {![file exists $ODB_FILE]} {
  puts "Error: ODB file not found: $ODB_FILE"
  exit 1
}

# --- Load ODB ---
puts "Loading ODB: $ODB_FILE"
read_db $ODB_FILE

# --- Check GUI availability ---
if {[namespace exists ::gui] && [info commands gui::enabled] ne "" && [gui::enabled]} {
  puts "GUI is available."
} else {
  puts "Error: GUI not available. Run with: xvfb-run -a openroad -gui -exit scripts/export_odb_webp.tcl ..."
  exit 1
}

# --- Get die area and render with explicit coordinates ---
set db    [ord::get_db]
set chip  [$db getChip]
set block [$chip getBlock]
set dbu   [$block getDbUnitsPerMicron]
set die_rect [$block getDieArea]
set die_x0 [$die_rect xMin]
set die_y0 [$die_rect yMin]
set die_x1 [$die_rect xMax]
set die_y1 [$die_rect yMax]

# Convert to microns for save_image coordinates
set x0_um [expr {double($die_x0) / $dbu}]
set y0_um [expr {double($die_y0) / $dbu}]
set x1_um [expr {double($die_x1) / $dbu}]
set y1_um [expr {double($die_y1) / $dbu}]

set die_w [expr {$x1_um - $x0_um}]
set die_h [expr {$y1_um - $y0_um}]
puts "Die area: ${die_w} x ${die_h} um"

# Compute output width to respect die aspect ratio and IMG_W/IMG_H limit
set aspect [expr {$die_w / $die_h}]
if {$aspect >= 1.0} {
  set out_w $IMG_W
} else {
  set out_w [expr {int($IMG_H * $aspect)}]
  if {$out_w > $IMG_W} { set out_w $IMG_W }
}

gui::fit
save_image -area [list $x0_um $y0_um $x1_um $y1_um] -width $out_w $OUT_FILE
puts "Saved: $OUT_FILE (${out_w}px wide, aspect=${aspect})"

puts "Done."
exit 0