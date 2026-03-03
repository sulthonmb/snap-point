//! 25 window layout definitions and resolver.
//! All geometry is expressed as fractions of the display's safe area,
//! computed at comptime so zero CPU cycles are spent on layout math at runtime.

const geo = @import("../util/geometry.zig");
const constants = @import("../core/constants.zig");

// ── Layout region: fractional rectangle ──────────────────────────────────

/// A layout defined as rational fractions of safe-area width / height.
/// Resolves to: x = x_num/x_den * W,  y = y_num/y_den * H,
///               w = w_num/w_den * W,  h = h_num/h_den * H
pub const LayoutRegion = struct {
    x_num: u8,
    x_den: u8, // origin x fraction
    y_num: u8,
    y_den: u8, // origin y fraction
    w_num: u8,
    w_den: u8, // width  fraction
    h_num: u8,
    h_den: u8, // height fraction
};

// ── 25 comptime layout definitions ───────────────────────────────────────

pub const layouts: [constants.layout_count]LayoutRegion = blk: {
    var l: [25]LayoutRegion = undefined;

    // Standard (1-8): halves and quarter corners
    l[0] = .{ .x_num = 0, .x_den = 1, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 2, .h_num = 1, .h_den = 1 }; // Left Half
    l[1] = .{ .x_num = 1, .x_den = 2, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 2, .h_num = 1, .h_den = 1 }; // Right Half
    l[2] = .{ .x_num = 0, .x_den = 1, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 1, .h_num = 1, .h_den = 2 }; // Top Half
    l[3] = .{ .x_num = 0, .x_den = 1, .y_num = 1, .y_den = 2, .w_num = 1, .w_den = 1, .h_num = 1, .h_den = 2 }; // Bottom Half
    l[4] = .{ .x_num = 0, .x_den = 1, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 2, .h_num = 1, .h_den = 2 }; // Top-Left Quarter
    l[5] = .{ .x_num = 1, .x_den = 2, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 2, .h_num = 1, .h_den = 2 }; // Top-Right Quarter
    l[6] = .{ .x_num = 0, .x_den = 1, .y_num = 1, .y_den = 2, .w_num = 1, .w_den = 2, .h_num = 1, .h_den = 2 }; // Bottom-Left Quarter
    l[7] = .{ .x_num = 1, .x_den = 2, .y_num = 1, .y_den = 2, .w_num = 1, .w_den = 2, .h_num = 1, .h_den = 2 }; // Bottom-Right Quarter

    // Vertical Thirds (9-11)
    l[8] = .{ .x_num = 0, .x_den = 1, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 3, .h_num = 1, .h_den = 1 }; // First Third
    l[9] = .{ .x_num = 1, .x_den = 3, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 3, .h_num = 1, .h_den = 1 }; // Center Third
    l[10] = .{ .x_num = 2, .x_den = 3, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 3, .h_num = 1, .h_den = 1 }; // Last Third

    // Portrait/Horizontal Thirds (12-14)
    l[11] = .{ .x_num = 0, .x_den = 1, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 1, .h_num = 1, .h_den = 3 }; // Top Third
    l[12] = .{ .x_num = 0, .x_den = 1, .y_num = 1, .y_den = 3, .w_num = 1, .w_den = 1, .h_num = 1, .h_den = 3 }; // Middle Third
    l[13] = .{ .x_num = 0, .x_den = 1, .y_num = 2, .y_den = 3, .w_num = 1, .w_den = 1, .h_num = 1, .h_den = 3 }; // Bottom Third

    // Two-Thirds (15-18)
    l[14] = .{ .x_num = 0, .x_den = 1, .y_num = 0, .y_den = 1, .w_num = 2, .w_den = 3, .h_num = 1, .h_den = 1 }; // Left Two-Thirds
    l[15] = .{ .x_num = 1, .x_den = 3, .y_num = 0, .y_den = 1, .w_num = 2, .w_den = 3, .h_num = 1, .h_den = 1 }; // Right Two-Thirds
    l[16] = .{ .x_num = 0, .x_den = 1, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 1, .h_num = 2, .h_den = 3 }; // Top Two-Thirds
    l[17] = .{ .x_num = 0, .x_den = 1, .y_num = 1, .y_den = 3, .w_num = 1, .w_den = 1, .h_num = 2, .h_den = 3 }; // Bottom Two-Thirds

    // Sixths – 3×2 grid (19-24)
    l[18] = .{ .x_num = 0, .x_den = 3, .y_num = 0, .y_den = 2, .w_num = 1, .w_den = 3, .h_num = 1, .h_den = 2 }; // Top-Left Sixth
    l[19] = .{ .x_num = 1, .x_den = 3, .y_num = 0, .y_den = 2, .w_num = 1, .w_den = 3, .h_num = 1, .h_den = 2 }; // Top-Center Sixth
    l[20] = .{ .x_num = 2, .x_den = 3, .y_num = 0, .y_den = 2, .w_num = 1, .w_den = 3, .h_num = 1, .h_den = 2 }; // Top-Right Sixth
    l[21] = .{ .x_num = 0, .x_den = 3, .y_num = 1, .y_den = 2, .w_num = 1, .w_den = 3, .h_num = 1, .h_den = 2 }; // Bottom-Left Sixth
    l[22] = .{ .x_num = 1, .x_den = 3, .y_num = 1, .y_den = 2, .w_num = 1, .w_den = 3, .h_num = 1, .h_den = 2 }; // Bottom-Center Sixth
    l[23] = .{ .x_num = 2, .x_den = 3, .y_num = 1, .y_den = 2, .w_num = 1, .w_den = 3, .h_num = 1, .h_den = 2 }; // Bottom-Right Sixth

    // Focus (25): Almost Maximize – 95% with centred margin
    l[24] = .{ .x_num = 1, .x_den = 40, .y_num = 1, .y_den = 40, .w_num = 19, .w_den = 20, .h_num = 19, .h_den = 20 };

    // ── Comptime validation ──────────────────────────────────────────────
    // Ensure no division by zero and all layouts are well-formed.
    for (l) |layout| {
        if (layout.x_den == 0 or layout.y_den == 0 or
            layout.w_den == 0 or layout.h_den == 0)
        {
            @compileError("Layout has zero denominator - would cause division by zero");
        }
        if (layout.w_num == 0 or layout.h_num == 0) {
            @compileError("Layout has zero width or height numerator - window would be invisible");
        }
    }

    break :blk l;
};

// ── Comptime assertions ──────────────────────────────────────────────────
comptime {
    // Ensure exactly 25 layouts are defined (matches constants.layout_count)
    if (layouts.len != constants.layout_count) {
        @compileError("Layout count mismatch: layouts.len != constants.layout_count");
    }
    // Ensure layout_names matches layouts array length
    if (layout_names.len != layouts.len) {
        @compileError("layout_names length must match layouts length");
    }
}

// ── Display names ────────────────────────────────────────────────────────

pub const layout_names: [25][:0]const u8 = .{
    "Left Half",        "Right Half",        "Top Half",            "Bottom Half",
    "Top-Left Quarter", "Top-Right Quarter", "Bottom-Left Quarter", "Bottom-Right Quarter",
    "First Third",      "Center Third",      "Last Third",          "Top Third",
    "Middle Third",     "Bottom Third",      "Left Two-Thirds",     "Right Two-Thirds",
    "Top Two-Thirds",   "Bottom Two-Thirds", "Top-Left Sixth",      "Top-Center Sixth",
    "Top-Right Sixth",  "Bottom-Left Sixth", "Bottom-Center Sixth", "Bottom-Right Sixth",
    "Almost Maximize",
};

// ── Resolver ─────────────────────────────────────────────────────────────

/// Resolve a `LayoutRegion` to absolute pixel coordinates within `safe_area`.
/// `gap` is the pixel gap to leave between tiled windows (0-50).
/// The origin in the returned rect is in CG coordinates (top-left origin),
/// matching the coordinate system used by AXUIElement.
pub fn resolve(layout: LayoutRegion, safe_area: geo.Rect, gap: u8) geo.Rect {
    const g = @as(f64, @floatFromInt(gap));
    const W = safe_area.size.width;
    const H = safe_area.size.height;

    const x = safe_area.origin.x + (W * f(layout.x_num) / f(layout.x_den)) + g;
    const y = safe_area.origin.y + (H * f(layout.y_num) / f(layout.y_den)) + g;
    const w = (W * f(layout.w_num) / f(layout.w_den)) - g * 2.0;
    const h = (H * f(layout.h_num) / f(layout.h_den)) - g * 2.0;

    return .{
        .origin = .{ .x = x, .y = y },
        .size = .{
            .width = @max(w, constants.min_window_size),
            .height = @max(h, constants.min_window_size),
        },
    };
}

inline fn f(v: u8) f64 {
    return @as(f64, @floatFromInt(v));
}

// ── Zone-to-layout mapping ───────────────────────────────────────────────
// Maps ZoneType indices (from engine/zone.zig) to layout indices.

pub const ZoneLayoutMap = struct {
    pub const left_half: usize = 0;
    pub const right_half: usize = 1;
    pub const top_maximize: usize = 2; // top  → Top Half (maximize TBD)
    pub const bottom_first_third: usize = 8; // bottom-left  → First Third
    pub const bottom_center_third: usize = 9; // bottom-mid   → Center Third
    pub const bottom_last_third: usize = 10; // bottom-right → Last Third
    pub const top_left_quarter: usize = 4;
    pub const top_right_quarter: usize = 5;
    pub const bottom_left_quarter: usize = 6;
    pub const bottom_right_quarter: usize = 7;
};
