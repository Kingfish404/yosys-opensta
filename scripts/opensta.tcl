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

# Source platform config for liberty file paths
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
read_verilog $PROJ_PATH/$RESULT_DIR/$NETLIST_SYN_V
link_design $DESIGN

# === sdc start ===
set clk_port_name clock
if {[info exists env(CLK_PORT_NAME)]} {
  set clk_port_name $::env(CLK_PORT_NAME)
} else {
  puts "Warning: Environment CLK_PORT_NAME is not defined. Use $clk_port_name by default."
}
set CLK_FREQ_MHZ 50
if {[info exists env(CLK_FREQ_MHZ)]} {
  set CLK_FREQ_MHZ $::env(CLK_FREQ_MHZ)
} else {
  puts "Warning: Environment CLK_FREQ_MHZ is not defined. Use $CLK_FREQ_MHZ MHz by default."
}
set clk_io_pct 0.2
# Max I/O delay cap in ns (prevents overly large I/O budget at low frequencies)
set IO_DELAY_CAP_NS 2.0

set clk_port [get_ports $clk_port_name]
# TIME_SCALE is set by platform config.tcl (1e3 for ns, 1e6 for ps)
if {![info exists TIME_SCALE]} { set TIME_SCALE 1000.0 }
set clk_period [expr $TIME_SCALE / $CLK_FREQ_MHZ]
create_clock -name core_clock -period $clk_period $clk_port

if {![info exists TIME_UNIT]} { set TIME_UNIT "ns" }

# I/O delay: use env override, or min(pct * period, cap)
if {[info exists env(IO_DELAY)]} {
  set io_delay $::env(IO_DELAY)
} else {
  set io_delay_pct [expr $clk_period * $clk_io_pct]
  set io_delay_cap [expr $IO_DELAY_CAP_NS * ($TIME_SCALE / 1000.0)]
  if {$io_delay_pct < $io_delay_cap} {
    set io_delay $io_delay_pct
  } else {
    set io_delay $io_delay_cap
  }
}
set non_clk_inputs [all_inputs -no_clocks]
if {[llength $non_clk_inputs] > 0} {
  set_input_delay  $io_delay -clock core_clock $non_clk_inputs
}
if {[llength [all_outputs]] > 0} {
  set_output_delay $io_delay -clock core_clock [all_outputs]
}
# === sdc end   ===

puts "--- Timing (critical path, time unit: $TIME_UNIT) ---"
report_checks
puts ""
puts "--- Power estimation ---"
report_power
puts ""

puts "=========================================================="
puts "  fmax Summary (period: $TIME_UNIT, freq: MHz)"
puts "=========================================================="
puts "  Clock period = $clk_period $TIME_UNIT ($CLK_FREQ_MHZ MHz target)"
set _io_pct_actual [expr {$io_delay / $clk_period * 100.0}]
puts [format "  I/O delay    = %.1f %s (%.1f%% of period)" $io_delay $TIME_UNIT $_io_pct_actual]
puts ""
puts "  Overall (including I/O paths):"
report_clock_min_period -include_port_paths
puts ""
# Delete and recreate clock to clear I/O delay state for pure reg-to-reg fmax
delete_clock [all_clocks]
create_clock -name core_clock -period $clk_period $clk_port
puts "  Register-to-register only (no I/O constraints):"
report_clock_min_period
puts "=========================================================="
# Restore I/O delays for write_sdc output
set non_clk_inputs [all_inputs -no_clocks]
if {[llength $non_clk_inputs] > 0} {
  set_input_delay  $io_delay -clock core_clock $non_clk_inputs
}
if {[llength [all_outputs]] > 0} {
  set_output_delay $io_delay -clock core_clock [all_outputs]
}

write_sdc $PROJ_PATH/$RESULT_DIR/$NETLIST_SYN_V.sdc
write_sdf $PROJ_PATH/$RESULT_DIR/$NETLIST_SYN_V.sdf
write_timing_model $PROJ_PATH/$RESULT_DIR/$NETLIST_SYN_V.timing_model
write_verilog $PROJ_PATH/$RESULT_DIR/$NETLIST_SYN_V.opensta.v

exit