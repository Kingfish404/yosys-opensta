#===========================================================
# OpenSTA Common Setup
#
# Shared environment, platform config, liberty loading, and
# SDC constraint generation for opensta.tcl / opensta_detail.tcl.
#
# After sourcing, the following variables are available:
#   PROJ_PATH, PLATFORM, DESIGN, RESULT_DIR, NETLIST_SYN_V,
#   PLATFORM_DIR, LIB_DIR, clk_port_name, CLK_FREQ_MHZ,
#   clk_port, clk_period, io_delay, TIME_UNIT
#
# Usage: source this file, then read_verilog + link_design
#        in the caller, then call setup_sdc.
#===========================================================

# === Environment ===
set PROJ_PATH /data
if {[info exists env(PROJ_PATH)]} {
  set PROJ_PATH $::env(PROJ_PATH)
} else {
  puts "Warning: Environment PROJ_PATH is not defined. Use $PROJ_PATH by default."
}
set PLATFORM nangate45
if {[info exists env(PLATFORM)]} {
  set PLATFORM $::env(PLATFORM)
}
set DESIGN $::env(DESIGN)
set RESULT_DIR $::env(RESULT_DIR)
set NETLIST_SYN_V $::env(NETLIST_SYN_V)
puts "DESIGN: $DESIGN"
puts "NETLIST_SYN_V: $NETLIST_SYN_V"

# === Platform config & liberty ===
set PLATFORM_DIR $PROJ_PATH/platforms/$PLATFORM
set LIB_DIR $PROJ_PATH/third_party/lib/$PLATFORM
source $PLATFORM_DIR/config.tcl

if {[info exists LIB_FILES]} {
  foreach lib_file $LIB_FILES {
    read_liberty $lib_file
  }
} else {
  read_liberty $LIB_FILE
}

# === SDC setup procedure ===
# Call after read_verilog + link_design.
# Args:
#   use_io_delay_cap - if 1, cap I/O delay at IO_DELAY_CAP_NS (default: 0)
proc setup_sdc {{use_io_delay_cap 0}} {
  # Clock port
  set clk_port_name clock
  if {[info exists ::env(CLK_PORT_NAME)]} {
    set clk_port_name $::env(CLK_PORT_NAME)
  } else {
    puts "Warning: Environment CLK_PORT_NAME is not defined. Use $clk_port_name by default."
  }
  set ::clk_port_name $clk_port_name

  # Clock frequency
  set CLK_FREQ_MHZ 50
  if {[info exists ::env(CLK_FREQ_MHZ)]} {
    set CLK_FREQ_MHZ $::env(CLK_FREQ_MHZ)
  } else {
    puts "Warning: Environment CLK_FREQ_MHZ is not defined. Use $CLK_FREQ_MHZ MHz by default."
  }
  set ::CLK_FREQ_MHZ $CLK_FREQ_MHZ

  # Time scale from platform config
  if {![info exists ::TIME_SCALE]} { set ::TIME_SCALE 1000.0 }
  if {![info exists ::TIME_UNIT]}  { set ::TIME_UNIT "ns" }

  set clk_port [get_ports $clk_port_name]
  set clk_period [expr $::TIME_SCALE / $CLK_FREQ_MHZ]
  set ::clk_port $clk_port
  set ::clk_period $clk_period
  create_clock -name core_clock -period $clk_period $clk_port

  # I/O delay
  set clk_io_pct 0.2
  if {[info exists ::env(IO_DELAY)]} {
    set io_delay $::env(IO_DELAY)
  } elseif {$use_io_delay_cap} {
    set IO_DELAY_CAP_NS 2.0
    set io_delay_pct [expr $clk_period * $clk_io_pct]
    set io_delay_cap [expr $IO_DELAY_CAP_NS * ($::TIME_SCALE / 1000.0)]
    if {$io_delay_pct < $io_delay_cap} {
      set io_delay $io_delay_pct
    } else {
      set io_delay $io_delay_cap
    }
  } else {
    set io_delay [expr $clk_period * $clk_io_pct]
  }
  set ::io_delay $io_delay

  set non_clk_inputs [all_inputs -no_clocks]
  if {[llength $non_clk_inputs] > 0} {
    set_input_delay  $io_delay -clock core_clock $non_clk_inputs
  }
  if {[llength [all_outputs]] > 0} {
    set_output_delay $io_delay -clock core_clock [all_outputs]
  }
}
