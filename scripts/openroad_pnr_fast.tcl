#===========================================================
# OpenROAD Physical Design Flow — FAST Mode
#
# Optimized for large designs with relaxed timing.
# Key differences vs standard mode:
#   - Higher utilization / density (smaller die, faster routing)
#   - Fewer congestion iterations in global routing
#   - Skip post-GRT incremental repair cycles
#   - Fewer report paths
#
# See openroad_pnr_common.tcl for the shared flow implementation.
#===========================================================

# --- Mode-specific defaults ---
set PNR_MODE                "fast"
set _DEFAULT_CORE_UTILIZATION 60
set _DEFAULT_PLACE_DENSITY    0.70
set _PDN_CHECK_SIZE           0
set _GRT_CONGESTION_ITERS     5
set _SKIP_POST_GRT_REPAIR     1
set _RPT_MAX_GROUP_COUNT      5
set _RPT_MAX_ENDPOINT_COUNT   1
set _RPT_MIN_GROUP_COUNT      3
set _RPT_MIN_ENDPOINT_COUNT   1

# --- Run the common PnR flow ---
source [file dirname [info script]]/openroad_pnr_common.tcl
