//! Trigger zone detection unit tests.

const std  = @import("std");
const zone = @import("../src/engine/zone.zig");
const geo  = @import("../src/util/geometry.zig");

const sa = geo.Rect{
    .origin = .{ .x = 0, .y = 0 },
    .size   = .{ .width = 2560, .height = 1440 },
};
const sens: u8 = 10;

test "centre of screen is no zone" {
    const z = zone.detectZone(.{ .x = 1280, .y = 720 }, sa, sens);
    try std.testing.expectEqual(z, .none);
}

test "left edge" {
    const z = zone.detectZone(.{ .x = 5, .y = 720 }, sa, sens);
    try std.testing.expectEqual(z, .left_half);
}

test "right edge" {
    const z = zone.detectZone(.{ .x = 2558, .y = 720 }, sa, sens);
    try std.testing.expectEqual(z, .right_half);
}

test "top edge" {
    const z = zone.detectZone(.{ .x = 1280, .y = 5 }, sa, sens);
    try std.testing.expectEqual(z, .top_maximize);
}

test "bottom-left third" {
    const z = zone.detectZone(.{ .x = 100, .y = 1438 }, sa, sens);
    try std.testing.expectEqual(z, .bottom_first_third);
}

test "bottom-center third" {
    const z = zone.detectZone(.{ .x = 1280, .y = 1438 }, sa, sens);
    try std.testing.expectEqual(z, .bottom_center_third);
}

test "bottom-right third" {
    const z = zone.detectZone(.{ .x = 2400, .y = 1438 }, sa, sens);
    try std.testing.expectEqual(z, .bottom_last_third);
}

test "top-left corner" {
    const z = zone.detectZone(.{ .x = 5, .y = 5 }, sa, sens);
    try std.testing.expectEqual(z, .top_left_quarter);
}

test "top-right corner" {
    const z = zone.detectZone(.{ .x = 2558, .y = 5 }, sa, sens);
    try std.testing.expectEqual(z, .top_right_quarter);
}

test "bottom-left corner" {
    const z = zone.detectZone(.{ .x = 5, .y = 1438 }, sa, sens);
    try std.testing.expectEqual(z, .bottom_left_quarter);
}

test "bottom-right corner" {
    const z = zone.detectZone(.{ .x = 2558, .y = 1438 }, sa, sens);
    try std.testing.expectEqual(z, .bottom_right_quarter);
}

test "corner priority over edge" {
    // A point that is both at_top AND at_left should be a corner, not just top
    const z = zone.detectZone(.{ .x = 5, .y = 5 }, sa, sens);
    try std.testing.expectEqual(z, .top_left_quarter);
}

test "just outside sensitivity is no zone" {
    const z = zone.detectZone(.{ .x = 15, .y = 720 }, sa, sens);
    try std.testing.expectEqual(z, .none);
}
