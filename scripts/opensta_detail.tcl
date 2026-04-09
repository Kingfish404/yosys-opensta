#===========================================================
# OpenSTA Detailed Timing Report with Source Attribution
#
# Reads the source-annotated netlist to map timing paths
# back to original RTL modules and Verilog source lines.
#===========================================================

# Common setup: env, platform config, liberty loading, setup_sdc proc
source [file dirname [info script]]/opensta_common.tcl

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

# Create SDC constraints (no I/O delay capping for detail report)
setup_sdc 0

set detail_rpt $PROJ_PATH/$RESULT_DIR/timing_detail.rpt

puts "======================================================="
puts "  Detailed Timing Report (with source attribution)"
puts "======================================================="

# Top critical paths with source attributes
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
