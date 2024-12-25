set PROJ_PATH /data
set DESIGN $::env(DESIGN)
set RESULT_DIR $::env(RESULT_DIR)
set NETLIST_SYN_V $::env(NETLIST_SYN_V)
puts "DESIGN: $DESIGN"
puts "NETLIST_SYN_V: $NETLIST_SYN_V"

read_liberty $PROJ_PATH/nangate45/lib/merged.lib
read_verilog $PROJ_PATH/$RESULT_DIR/$NETLIST_SYN_V
link_design $DESIGN

# === sdc start ===
set clk_port_name clock
if {[info exists env(CLK_PORT_NAME)]} {
  set clk_port_name $::env(CLK_PORT_NAME)
} else {
  puts "Warning: Environment CLK_PORT_NAME is not defined. Use $clk_port_name by default."
}
set CLK_FREQ_MHZ 500
if {[info exists env(CLK_FREQ_MHZ)]} {
  set CLK_FREQ_MHZ $::env(CLK_FREQ_MHZ)
} else {
  puts "Warning: Environment CLK_FREQ_MHZ is not defined. Use $CLK_FREQ_MHZ MHz by default."
}
set clk_io_pct 0.2

set clk_port [get_ports $clk_port_name]
create_clock -name core_clock -period [expr 1000.0 / $CLK_FREQ_MHZ] $clk_port
# === sdc end   ===

report_checks
report_power
report_clock_min_period

write_sdc $PROJ_PATH/$RESULT_DIR/$NETLIST_SYN_V.sdc
write_sdf $PROJ_PATH/$RESULT_DIR/$NETLIST_SYN_V.sdf
write_timing_model $PROJ_PATH/$RESULT_DIR/$NETLIST_SYN_V.timing_model
write_verilog $PROJ_PATH/$RESULT_DIR/$NETLIST_SYN_V.opensta.v

exit