#===========================================================
# Detailed timing report with source-line attribution
# Reads the source-annotated netlist to map timing paths
# back to original RTL modules and Verilog source lines
#===========================================================

set PROJ_PATH /data
if {[info exists env(PROJ_PATH)]} {
  set PROJ_PATH $::env(PROJ_PATH)
} else {
  puts "Warning: Environment PROJ_PATH is not defined. Use $PROJ_PATH by default."
}
set DESIGN $::env(DESIGN)
set RESULT_DIR $::env(RESULT_DIR)
set NETLIST_SYN_V $::env(NETLIST_SYN_V)
puts "DESIGN: $DESIGN"
puts "NETLIST_SYN_V: $NETLIST_SYN_V"

read_liberty $PROJ_PATH/nangate45/lib/merged.lib

# Read source-annotated netlist (preserves src attributes from yosys)
set SRC_NETLIST $PROJ_PATH/$RESULT_DIR/${DESIGN}.netlist.src.v
if {[file exists $SRC_NETLIST]} {
  read_verilog $SRC_NETLIST
} else {
  puts "Warning: Source-annotated netlist not found: $SRC_NETLIST"
  puts "Falling back to $NETLIST_SYN_V (without source attributes)"
  read_verilog $PROJ_PATH/$RESULT_DIR/$NETLIST_SYN_V
}
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

set clk_port [get_ports $clk_port_name]
create_clock -name core_clock -period [expr 1000.0 / $CLK_FREQ_MHZ] $clk_port
# === sdc end   ===

set detail_rpt $PROJ_PATH/$RESULT_DIR/timing_detail.rpt

puts "======================================================="
puts "  Detailed Timing Report (with source attribution)"
puts "======================================================="

# Top critical paths with source attributes
# -group_path_count: number of paths per path group
# -endpoint_path_count: number of paths per endpoint
# -fields src_attr: show Verilog source file:line for each cell
report_checks \
  -path_delay max \
  -group_path_count 10 \
  -endpoint_path_count 3 \
  -format full_clock_expanded \
  -fields {slew input_pin net fanout src_attr} \
  -digits 3 \
  > $detail_rpt

# Append min-delay (hold) critical paths
report_checks \
  -path_delay min \
  -group_path_count 5 \
  -endpoint_path_count 2 \
  -format full_clock_expanded \
  -fields {slew input_pin net fanout src_attr} \
  -digits 3 \
  >> $detail_rpt

# Append all violating paths (if any)
report_check_types -violators -verbose \
  -max_delay -min_delay \
  >> $detail_rpt

puts "Detailed timing report written to: $detail_rpt"

exit
