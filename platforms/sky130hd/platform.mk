# SKY130 (HD) Platform Configuration for Makefile
# Included by the top-level Makefile when PLATFORM=sky130hd
# PLATFORM_DIR = platforms/sky130hd (build configs)
# LIB_DIR      = third_party/lib/sky130hd       (downloaded PDK data)
#
# Library: sky130_fd_sc_hd (high-density). This is the standard cell set
# used by TinyTapeout (https://tinytapeout.com), so synthesis results
# are tape-out compatible with the OpenLane / TT flow.

PLATFORM_TECH_LEF   = $(LIB_DIR)/lef/sky130_fd_sc_hd.tlef
PLATFORM_SC_LEF     = $(LIB_DIR)/lef/sky130_fd_sc_hd_merged.lef
PLATFORM_LIB_FILE   = $(LIB_DIR)/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
PLATFORM_MERGED_LIB = $(LIB_DIR)/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
PLATFORM_CELL_GDS   = $(LIB_DIR)/gds/sky130_fd_sc_hd.gds
PLATFORM_KLAYOUT_TECH = $(LIB_DIR)/sky130hd.lyt
PLATFORM_KLAYOUT_LYP  = $(LIB_DIR)/sky130hd.lyp

# Default routing layers (sky130hd PDK supports li1, met1-met5)
# TinyTapeout uses met1-met5 for signal routing.
MIN_ROUTING_LAYER ?= met1
MAX_ROUTING_LAYER ?= met5

# SKY130 precheck expects real OpenRCX parasitics and excludes lpflow/probe cells.
SIGNOFF_REQUIRE_SPEF ?= 1
SIGNOFF_FORBID_CELL_REGEX ?= sky130_fd_sc_hd__lpflow_|sky130_fd_sc_hd__probe
ANTENNA_REPAIR_EXTRA_ARGS ?= -diode_only
