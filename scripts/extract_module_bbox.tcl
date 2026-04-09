#===========================================================
# Extract module bounding boxes from ODB
#
# The design is flattened (single top module), so we reconstruct
# module membership from hierarchical net naming (e.g. "exu.io_xxx").
#
# Usage:
#   ODB=<path> HIER_JSON=<path> OUT_JSON=<path> \
#     openroad -no_splash scripts/extract_module_bbox.tcl
#
# Output: JSON with module name -> {x0, y0, x1, y1, count}
#===========================================================

set ODB_FILE   $::env(ODB)
set HIER_JSON  $::env(HIER_JSON)
set OUT_JSON   [expr {[info exists ::env(OUT_JSON)] ? $::env(OUT_JSON) : "[file rootname $ODB_FILE].modules.json"}]

puts "======================================================="
puts "  Extract Module Bounding Boxes"
puts "  ODB:       $ODB_FILE"
puts "  HIER_JSON: $HIER_JSON"
puts "  OUT_JSON:  $OUT_JSON"
puts "======================================================="

# --- Load ODB ---
read_db $ODB_FILE
set db    [ord::get_db]
set chip  [$db getChip]
set block [$chip getBlock]
set dbu   [$block getDbUnitsPerMicron]

# --- Parse module prefixes from hier JSON ---
# Read the file and extract module prefixes from net names with "."
package require Tcl 8.5
set fh [open $HIER_JSON r]
set json_text [read $fh]
close $fh

# Simple JSON net name extraction: find all "netnames" keys with "."
# We use regex to find all quoted keys under netnames that contain a dot
set module_prefixes [dict create]
set pattern {\"([a-zA-Z_][a-zA-Z0-9_]*)\.[a-zA-Z_]}
foreach {match prefix} [regexp -all -inline $pattern $json_text] {
    if {![dict exists $module_prefixes $prefix]} {
        dict set module_prefixes $prefix 1
    }
}
puts "Found [dict size $module_prefixes] module prefixes"
dict for {pfx _} $module_prefixes {
    puts "  $pfx"
}

# Some prefixes with underscores are bridges (e.g. "rou_cmu" connects "rou" and "cmu")
# We only keep primary modules (those without underscore, plus known compound names)
set primary_modules [dict create]
set compound_modules [dict create]
dict for {pfx _} $module_prefixes {
    if {[string first "_" $pfx] == -1} {
        dict set primary_modules $pfx 1
    } else {
        dict set compound_modules $pfx 1
    }
}

# Check if compound names are bridges (both parts are primary modules)
dict for {pfx _} $compound_modules {
    set parts [split $pfx "_"]
    set is_bridge 0
    for {set i 1} {$i < [llength $parts]} {incr i} {
        set left [join [lrange $parts 0 [expr {$i-1}]] "_"]
        set right [join [lrange $parts $i end] "_"]
        if {[dict exists $primary_modules $left] && [dict exists $primary_modules $right]} {
            set is_bridge 1
            break
        }
    }
    if {!$is_bridge} {
        # Keep as primary module
        dict set primary_modules $pfx 1
    }
}
puts "\nPrimary modules: [dict size $primary_modules]"
dict for {pfx _} $primary_modules {
    puts "  $pfx"
}

# --- Build net → module prefix mapping ---
# For each net in the block, check if name starts with a known prefix + "."
puts "\nScanning nets..."
set nets [$block getNets]
set total_nets [llength $nets]
puts "Total nets: $total_nets"

# net_ptr → prefix mapping
set net_to_module [dict create]
set mapped_nets 0
foreach net $nets {
    set nname [$net getName]
    # Check for hierarchical prefix (name starts with "prefix.")
    set dot_idx [string first "." $nname]
    if {$dot_idx > 0} {
        set prefix [string range $nname 0 [expr {$dot_idx - 1}]]
        # Remove backslash escape if present
        set prefix [string trimleft $prefix "\\"]
        if {[dict exists $primary_modules $prefix]} {
            dict set net_to_module $net $prefix
            incr mapped_nets
        }
    }
}
puts "Nets mapped to modules: $mapped_nets"

# --- Map instances to modules via connected nets ---
puts "\nMapping instances to modules..."
set insts [$block getInsts]
set total_insts [llength $insts]
puts "Total instances: $total_insts"

# module_name → {min_x min_y max_x max_y count}
set module_bbox [dict create]
set assigned 0
set unassigned 0
set skip_types {FILLCELL FILLER TAPCELL WELLTAP ENDCAP DECAP clkbuf}

foreach inst $insts {
    set master_name [[$inst getMaster] getName]
    # Skip filler/infra cells
    set skip 0
    foreach patt $skip_types {
        if {[string match "${patt}*" $master_name] || [string match "*${patt}*" $master_name]} {
            set skip 1
            break
        }
    }
    if {$skip} continue

    # Get placement
    set bbox [$inst getBBox]
    set ix [$bbox xMin]
    set iy [$bbox yMin]
    set ix2 [$bbox xMax]
    set iy2 [$bbox yMax]

    # Vote for module based on connected nets
    set votes [dict create]
    foreach iterm [$inst getITerms] {
        set net [$iterm getNet]
        if {$net eq "NULL"} continue
        if {[dict exists $net_to_module $net]} {
            set mod [dict get $net_to_module $net]
            if {[dict exists $votes $mod]} {
                dict set votes $mod [expr {[dict get $votes $mod] + 1}]
            } else {
                dict set votes $mod 1
            }
        }
    }

    if {[dict size $votes] == 0} {
        incr unassigned
        continue
    }

    # Pick module with most votes
    set best_mod ""
    set best_cnt 0
    dict for {mod cnt} $votes {
        if {$cnt > $best_cnt} {
            set best_mod $mod
            set best_cnt $cnt
        }
    }

    incr assigned
    # Update bounding box
    if {[dict exists $module_bbox $best_mod]} {
        set cur [dict get $module_bbox $best_mod]
        lassign $cur cx0 cy0 cx1 cy1 cc
        if {$ix < $cx0}  { set cx0 $ix }
        if {$iy < $cy0}  { set cy0 $iy }
        if {$ix2 > $cx1} { set cx1 $ix2 }
        if {$iy2 > $cy1} { set cy1 $iy2 }
        dict set module_bbox $best_mod [list $cx0 $cy0 $cx1 $cy1 [expr {$cc + 1}]]
    } else {
        dict set module_bbox $best_mod [list $ix $iy $ix2 $iy2 1]
    }
}
puts "Assigned: $assigned, Unassigned: $unassigned"

# --- Write JSON output ---
set die [[$block getDieArea] rect]
lassign $die die_x0 die_y0 die_x1 die_y1

set fh [open $OUT_JSON w]
puts $fh "\{"
puts $fh "  \"dbu\": $dbu,"
puts $fh "  \"die_area\": \[$die_x0, $die_y0, $die_x1, $die_y1\],"
puts $fh "  \"modules\": \{"
set first 1
dict for {mod vals} $module_bbox {
    lassign $vals x0 y0 x1 y1 cnt
    if {!$first} { puts $fh "," }
    set first 0
    # Convert to microns
    set x0_um [expr {double($x0) / $dbu}]
    set y0_um [expr {double($y0) / $dbu}]
    set x1_um [expr {double($x1) / $dbu}]
    set y1_um [expr {double($y1) / $dbu}]
    puts -nonewline $fh "    \"$mod\": \{\"x0\": $x0_um, \"y0\": $y0_um, \"x1\": $x1_um, \"y1\": $y1_um, \"count\": $cnt\}"
}
puts $fh "\n  \}"
puts $fh "\}"
close $fh

puts "\nWrote: $OUT_JSON"
puts "Done."
exit 0
