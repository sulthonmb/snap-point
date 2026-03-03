//! Snap action dispatch tests.
//! Validates the Action enum, layout index mapping, and snap execution logic
//! without performing actual window manipulation (no AX calls).

const std = @import("std");
const snap = @import("../src/engine/snap.zig");
const layout = @import("../src/engine/layout.zig");
const constants = @import("../src/core/constants.zig");

// ── Action enum coverage ─────────────────────────────────────────────────

test "Action enum covers all 27 actions" {
    const field_count = @typeInfo(snap.Action).@"enum".fields.len;
    try std.testing.expectEqual(field_count, constants.action_count);
}

test "Action enum has exactly 25 layout actions + 2 multi-monitor" {
    // Verify the structure: 0-24 are layouts, 25-26 are multi-monitor
    try std.testing.expectEqual(@intFromEnum(snap.Action.snap_left_half), 0);
    try std.testing.expectEqual(@intFromEnum(snap.Action.snap_almost_maximize), 24);
    try std.testing.expectEqual(@intFromEnum(snap.Action.throw_to_next_display), 25);
    try std.testing.expectEqual(@intFromEnum(snap.Action.throw_to_prev_display), 26);
}

// ── Layout index mapping ─────────────────────────────────────────────────

test "layout index mapping is correct for all snap actions" {
    // Each snap action 0-24 should map to the corresponding layout index
    const layout_actions = [_]snap.Action{
        .snap_left_half,
        .snap_right_half,
        .snap_top_half,
        .snap_bottom_half,
        .snap_top_left_quarter,
        .snap_top_right_quarter,
        .snap_bottom_left_quarter,
        .snap_bottom_right_quarter,
        .snap_first_third,
        .snap_center_third,
        .snap_last_third,
        .snap_top_third,
        .snap_middle_third,
        .snap_bottom_third,
        .snap_left_two_thirds,
        .snap_right_two_thirds,
        .snap_top_two_thirds,
        .snap_bottom_two_thirds,
        .snap_top_left_sixth,
        .snap_top_center_sixth,
        .snap_top_right_sixth,
        .snap_bottom_left_sixth,
        .snap_bottom_center_sixth,
        .snap_bottom_right_sixth,
        .snap_almost_maximize,
    };

    for (layout_actions, 0..) |action, expected_idx| {
        const actual_idx = @intFromEnum(action);
        try std.testing.expectEqual(actual_idx, expected_idx);
    }
}

test "all 25 layout actions map to valid layout indices" {
    // Ensure each layout action index is within bounds of layouts array
    for (0..25) |i| {
        const action: snap.Action = @enumFromInt(i);
        const layout_idx = @intFromEnum(action);
        try std.testing.expect(layout_idx < layout.layouts.len);
    }
}

// ── Action enum from int conversion ──────────────────────────────────────

test "Action can be created from valid integers" {
    for (0..27) |i| {
        const action: snap.Action = @enumFromInt(i);
        try std.testing.expectEqual(@intFromEnum(action), i);
    }
}

test "multi-monitor actions are distinguishable from layout actions" {
    inline for (@typeInfo(snap.Action).@"enum".fields) |field| {
        const idx = field.value;
        const is_multi_monitor = idx >= 25;
        const is_throw = std.mem.indexOf(u8, field.name, "throw") != null;
        if (is_throw) {
            try std.testing.expect(is_multi_monitor);
        }
    }
}

// ── Action naming consistency ────────────────────────────────────────────

test "all Action enum fields have valid names" {
    inline for (@typeInfo(snap.Action).@"enum".fields) |field| {
        // All fields should start with "snap_" or "throw_"
        const valid_prefix = std.mem.startsWith(u8, field.name, "snap_") or
            std.mem.startsWith(u8, field.name, "throw_");
        try std.testing.expect(valid_prefix);
    }
}

// ── Layout/Action alignment ──────────────────────────────────────────────

test "layout_names align with snap Action enum order" {
    // First 25 actions should conceptually match layout_names
    // (Not a string comparison, but index alignment)
    try std.testing.expectEqual(layout.layout_names.len, 25);
    try std.testing.expectEqual(@intFromEnum(snap.Action.snap_almost_maximize) + 1, 25);
}

// ── Edge cases ───────────────────────────────────────────────────────────

test "Action enum is exhaustive over 0-26" {
    var seen = [_]bool{false} ** 27;
    inline for (@typeInfo(snap.Action).@"enum".fields) |field| {
        seen[field.value] = true;
    }
    for (seen) |s| {
        try std.testing.expect(s);
    }
}
