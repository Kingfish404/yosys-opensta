#===========================================================
#   set parameter
#===========================================================
set DESIGN                  [lindex $argv 0]
set VERILOG_FILES           [string map {"\"" ""} [lindex $argv 1]]
set VERILOG_INCLUDE_DIRS    [string map {"\"" ""} [lindex $argv 2]]
set NETLIST_SYN_V           [lindex $argv 3]
set RESULT_DIR              [file dirname $NETLIST_SYN_V]
puts "DESIGN: $DESIGN"
puts "VERILOG_FILES: $VERILOG_FILES"
puts "VERILOG_INCLUDE_DIRS: $VERILOG_INCLUDE_DIRS"
puts "NETLIST_SYN_V: $NETLIST_SYN_V"

set FOUNDRY_PATH           "[file dirname [info script]]/../third_party/lib/nangate45"
set PLATFORM_CONFIG_DIR     "[file dirname [info script]]/../platforms/nangate45"
if {[info exists env(PLATFORM)]} {
  set FOUNDRY_PATH         "[file dirname [info script]]/../third_party/lib/$::env(PLATFORM)"
  set PLATFORM_CONFIG_DIR   "[file dirname [info script]]/../platforms/$::env(PLATFORM)"
}

# Source platform-specific synthesis configuration
source "$PLATFORM_CONFIG_DIR/yosys_config.tcl"

# Build liberty args list from LIB_FILES (set by yosys_config.tcl)
if {![info exists LIB_FILES]} {
    set LIB_FILES [list $MERGED_LIB_FILE]
}
set liberty_args {}
foreach lib $LIB_FILES {
    lappend liberty_args -liberty $lib
}

set CLK_FREQ_MHZ            50
if {[info exists env(CLK_FREQ_MHZ)]} {
  set CLK_FREQ_MHZ          $::env(CLK_FREQ_MHZ)
} else {
  puts "Warning: Environment CLK_FREQ_MHZ is not defined. Use $CLK_FREQ_MHZ MHz by default."
}
set CLK_PERIOD_NS           [expr 1000.0 / $CLK_FREQ_MHZ]

# Build dont_use args for dfflibmap/abc (from DONT_USE_CELLS if set by yosys_config.tcl)
set dont_use_args {}
if {[info exists DONT_USE_CELLS]} {
    foreach cell $DONT_USE_CELLS {
        lappend dont_use_args -dont_use $cell
    }
}

# TIEHI/TIELO/BUF cells are set by yosys_config.tcl above

#===========================================================
#   main running
#===========================================================
yosys -import

# Don't change these unless you know what you are doing
set stat_ext    "_stat.rep"
set gl_ext      "_gl.v"
# ABC script: override via ABC_SCRIPT env var for area- vs timing-focused optimization
if {[info exists env(ABC_SCRIPT)] && $::env(ABC_SCRIPT) ne ""} {
  set abc_script $::env(ABC_SCRIPT)
} else {
  set abc_script  "+strash;ifraig;retime,-D,{D},-M,6;strash;dch,-f;map,-p,-M,1,{D},-f;topo;dnsize;buffer,-p;upsize;"
}

# Setup verilog include directories
set vIdirsArgs ""
if {[info exist VERILOG_INCLUDE_DIRS]} {
    foreach dir $VERILOG_INCLUDE_DIRS {
        lappend vIdirsArgs "-I$dir"
    }
    set vIdirsArgs [join $vIdirsArgs]
}



# read verilog files
read_slang {*}$vIdirsArgs --top $DESIGN {*}$VERILOG_FILES


# Read blackbox stubs of standard/io/ip/memory cells. This allows for standard/io/ip/memory cell (or
# structural netlist support in the input verilog
if {[info exist BLACKBOX_V_FILE] && $BLACKBOX_V_FILE ne ""} {
  read_slang $BLACKBOX_V_FILE
}

# Apply toplevel parameters (if exist
if {[info exist VERILOG_TOP_PARAMS]} {
    dict for {key value} $VERILOG_TOP_PARAMS {
        chparam -set $key $value $DESIGN
    }
}


# Read platform specific mapfile for OPENROAD_CLKGATE cells
if {[info exist CLKGATE_MAP_FILE] && $CLKGATE_MAP_FILE ne ""} {
    read_slang $CLKGATE_MAP_FILE
}

# Use hierarchy to automatically generate blackboxes for known memory macro.
# Pins are enumerated for proper mapping
if {[info exist BLACKBOX_MAP_TCL] && $BLACKBOX_MAP_TCL ne ""} {
    source $BLACKBOX_MAP_TCL
}

# generate architecture diagram data (preserves module hierarchy)
# write_json BEFORE hierarchy/proc — read_slang already parsed all modules
# hierarchy and proc would flatten sub-modules into primitives
write_json $RESULT_DIR/${DESIGN}_hier.json

# generic synthesis
# SYNTH_HIERARCHICAL: 0 = flat (default), 1 = preserve sub-module hierarchy
set synth_hierarchical 0
if {[info exists env(SYNTH_HIERARCHICAL)] && $::env(SYNTH_HIERARCHICAL) ne "0"} {
  set synth_hierarchical 1
}
if {$synth_hierarchical} {
  puts ">>> Hierarchical synthesis (preserving sub-module boundaries)"
  synth -top $DESIGN -noflatten
} else {
  synth -top $DESIGN
}

# Optimize the design
opt -purge

# Technology mapping of adders (if platform provides an adder map file)
if {[info exist ADDER_MAP_FILE] && $ADDER_MAP_FILE ne ""} {
  extract_fa
  techmap -map $ADDER_MAP_FILE
  techmap
  opt -fast -purge
}

# technology mapping of latches
if {[info exist LATCH_MAP_FILE] && $LATCH_MAP_FILE ne ""} {
  techmap -map $LATCH_MAP_FILE
}

# technology mapping of flip-flops
dfflibmap {*}$liberty_args {*}$dont_use_args
opt -undriven

# Technology mapping for cells
abc -D [expr $CLK_PERIOD_NS * 1000] \
    {*}$liberty_args \
    -showtmp \
    -script $abc_script

# replace undef values with defined constants
setundef -zero

# Splitting nets resolves unwanted compound assign statements in netlist (assign {..} = {..}
splitnets

# technology mapping of constant hi- and/or lo-drivers
hilomap -singleton \
        -hicell {*}$TIEHI_CELL_AND_PORT \
        -locell {*}$TIELO_CELL_AND_PORT

# insert buffer cells for pass through wires
insbuf -buf {*}$MIN_BUF_CELL_AND_PORTS

# remove unused cells and wires
opt_clean -purge

# write post-synthesis JSON (cells with net connections, for per-module area)
write_json $RESULT_DIR/${DESIGN}_syn.json

# reports
tee -o $RESULT_DIR/synth_check.txt check
tee -o $RESULT_DIR/input.json stat {*}$liberty_args -json
tee -o $RESULT_DIR/synth_stat.txt stat {*}$liberty_args

# Verify all cells are mapped to target library (report only, don't abort on warnings)
check -mapped

# write synthesized design
write_verilog -noattr -noexpr -nohex -nodec $NETLIST_SYN_V

# write source-annotated netlist (preserves src attributes for timing-to-RTL mapping)
write_verilog -noexpr -nohex -nodec $RESULT_DIR/${DESIGN}.netlist.src.v
