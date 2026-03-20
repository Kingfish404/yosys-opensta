# NanGate45 Platform Configuration for Makefile
# Included by the top-level Makefile when PLATFORM=nangate45
# PLATFORM_DIR = platforms/nangate45 (build configs)
# LIB_DIR      = lib/nangate45       (downloaded PDK data)

PLATFORM_TECH_LEF   = $(LIB_DIR)/lef/NangateOpenCellLibrary.tech.lef
PLATFORM_SC_LEF     = $(LIB_DIR)/lef/NangateOpenCellLibrary.macro.mod.lef
PLATFORM_LIB_FILE   = $(LIB_DIR)/lib/NangateOpenCellLibrary_typical.lib
PLATFORM_MERGED_LIB = $(LIB_DIR)/lib/merged.lib
PLATFORM_CELL_GDS   = $(LIB_DIR)/gds/NangateOpenCellLibrary.gds
PLATFORM_KLAYOUT_TECH = $(LIB_DIR)/klayout.lyt
PLATFORM_KLAYOUT_LYP = $(LIB_DIR)/klayout.lyp

# Default routing layers
MIN_ROUTING_LAYER ?= metal2
MAX_ROUTING_LAYER ?= metal7
