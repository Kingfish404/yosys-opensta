#===========================================================
# Pin Constraint File for 'op' Design
#
# This file defines IO pin placement constraints for OpenROAD.
# It is sourced BEFORE place_pins so that set_io_pin_constraint
# calls take effect during automatic pin placement.
#
# Supported constraint types:
#   set_io_pin_constraint -pin_names {pin1 pin2} -region <edge>:<begin>-<end>
#   set_io_pin_constraint -pin_names {pin1 pin2} -region <edge>:*
#   set_io_pin_constraint -mirrored_pins {pin1 pin2 pin3 pin4}
#   exclude_io_pin_constraint -region <edge>:<begin>-<end>
#
# Edges: top, bottom, left, right
# Coordinates: fractional (0.0-1.0) of die edge length, or absolute in microns
#
# See: https://openroad.readthedocs.io/en/latest/main/src/ppl/README.html
#===========================================================

# --- Clock & Control signals → bottom edge ---
set_io_pin_constraint -pin_names {clock reset} -region bottom:*

# --- Input operands → left edge ---
set_io_pin_constraint -pin_names {a[*] b[*] op_sel[*] acc_en} -region left:*

# --- Outputs → right edge ---
set_io_pin_constraint -pin_names {out[*] acc[*] zero overflow} -region left:*
