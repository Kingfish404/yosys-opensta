#===========================================================
# OpenROAD Physical Design Flow — Standard Mode
#
# Full-quality PnR with post-GRT incremental repair cycles.
# See openroad_pnr_common.tcl for the shared flow implementation.
#===========================================================

# --- Mode-specific defaults ---
set PNR_MODE                "standard"
set _DEFAULT_CORE_UTILIZATION 40
set _DEFAULT_PLACE_DENSITY    0.60
set _PDN_CHECK_SIZE           1
set _GRT_CONGESTION_ITERS     15
set _SKIP_POST_GRT_REPAIR     0
set _RPT_MAX_GROUP_COUNT      10
set _RPT_MAX_ENDPOINT_COUNT   3
set _RPT_MIN_GROUP_COUNT      5
set _RPT_MIN_ENDPOINT_COUNT   2

# --- Run the common PnR flow ---
source [file dirname [info script]]/openroad_pnr_common.tcl
