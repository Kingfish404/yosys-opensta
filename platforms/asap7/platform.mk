# ASAP7 Platform Configuration for Makefile
# Included by the top-level Makefile when PLATFORM=asap7
# PLATFORM_DIR = platforms/asap7 (build configs)
# LIB_DIR      = lib/asap7       (downloaded PDK data)

PLATFORM_TECH_LEF   = $(LIB_DIR)/lef/asap7_tech_1x_201209.lef
PLATFORM_SC_LEF     = $(LIB_DIR)/lef/asap7sc7p5t_28_R_1x_220121a.lef
PLATFORM_LIB_FILE   = $(LIB_DIR)/lib/merged.lib
PLATFORM_MERGED_LIB = $(LIB_DIR)/lib/merged.lib
PLATFORM_CELL_GDS   = $(LIB_DIR)/gds/asap7sc7p5t_28_R_220121a.gds
PLATFORM_KLAYOUT_TECH = $(LIB_DIR)/KLayout/asap7.lyt
PLATFORM_KLAYOUT_LYP =

# Default routing layers (ASAP7 uses M1-M7 naming)
MIN_ROUTING_LAYER ?= M2
MAX_ROUTING_LAYER ?= M7
