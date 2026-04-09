#===========================================================
# OpenSTA Timing Analysis — Summary + fmax Report
#
# Outputs: timing report, power report, fmax summary,
#          SDC, SDF, timing model, OpenSTA verilog
#===========================================================

# Common setup: env, platform config, liberty loading, setup_sdc proc
source [file dirname [info script]]/opensta_common.tcl

# Read synthesized netlist
read_verilog $PROJ_PATH/$RESULT_DIR/$NETLIST_SYN_V
link_design $DESIGN

# Create SDC constraints (with I/O delay capping enabled)
setup_sdc 1

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
