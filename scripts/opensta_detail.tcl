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
# TIME_SCALE is set by platform config.tcl (1e3 for ns, 1e6 for ps)
if {![info exists TIME_SCALE]} { set TIME_SCALE 1000.0 }
set clk_period [expr $TIME_SCALE / $CLK_FREQ_MHZ]
create_clock -name core_clock -period $clk_period $clk_port

# I/O delay constraints (20% of clock period, excluding clock port)
set clk_io_pct 0.2
set io_delay [expr $clk_period * $clk_io_pct]
set non_clk_inputs [all_inputs -no_clocks]
if {[llength $non_clk_inputs] > 0} {
  set_input_delay  $io_delay -clock core_clock $non_clk_inputs
}
if {[llength [all_outputs]] > 0} {
  set_output_delay $io_delay -clock core_clock [all_outputs]
}
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
