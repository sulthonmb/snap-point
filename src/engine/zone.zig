//! Trigger zone detection – Phase 2 implementation.
//! A "zone" is a region of the screen edge/corner that triggers a snap preset
//! when the user drags a window title bar into it.

const geo = @import("../util/geometry.zig");

pub const ZoneType = enum {
    none,
    left_half,
    right_half,
    top_maximize,
    bottom_first_third,
    bottom_center_third,
    bottom_last_third,
    top_left_quarter,
    top_right_quarter,
    bottom_left_quarter,
    bottom_right_quarter,
};

/// Detect which snap zone the cursor falls into, given a display's safe area.
/// `sensitivity` is the pixel margin (from the edge) that counts as "in zone".
pub fn detectZone(
    cursor:      geo.Point,
    safe_area:   geo.Rect,
    sensitivity: u8,
) ZoneType {
    const s = @as(f64, @floatFromInt(sensitivity));
    const sa = safe_area;

    const at_left   = cursor.x - sa.origin.x                   < s;
    const at_right  = (sa.origin.x + sa.size.width)  - cursor.x < s;
    const at_top    = cursor.y - sa.origin.y                   < s;
    const at_bottom = (sa.origin.y + sa.size.height) - cursor.y < s;

    // Corners take priority over edges
    if (at_top    and at_left)  return .top_left_quarter;
    if (at_top    and at_right) return .top_right_quarter;
    if (at_bottom and at_left)  return .bottom_left_quarter;
    if (at_bottom and at_right) return .bottom_right_quarter;

    if (at_top)   return .top_maximize;
    if (at_left)  return .left_half;
    if (at_right) return .right_half;

    if (at_bottom) {
        const rel_x = (cursor.x - sa.origin.x) / sa.size.width;
        if (rel_x < 0.333) return .bottom_first_third;
        if (rel_x < 0.667) return .bottom_center_third;
        return .bottom_last_third;
    }

    return .none;
}
