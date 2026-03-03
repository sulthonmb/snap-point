//! Layout engine unit tests – root of the test binary.
//! Imports all other test modules so `zig build test` runs everything.

const std = @import("std");

// ── Layout tests ─────────────────────────────────────────────────────────

const layout = @import("../src/engine/layout.zig");
const geo = @import("../src/util/geometry.zig");

/// A 2560×1440 display with a 0-origin CG safe area (no gap).
const test_sa = geo.Rect{
    .origin = .{ .x = 0, .y = 0 },
    .size = .{ .width = 2560, .height = 1440 },
};

fn r(x: f64, y: f64, w: f64, h: f64) geo.Rect {
    return .{ .origin = .{ .x = x, .y = y }, .size = .{ .width = w, .height = h } };
}

test "left half" {
    const result = layout.resolve(layout.layouts[0], test_sa, 0);
    try std.testing.expectApproxEqAbs(result.origin.x, 0.0, 0.01);
    try std.testing.expectApproxEqAbs(result.origin.y, 0.0, 0.01);
    try std.testing.expectApproxEqAbs(result.size.width, 1280.0, 0.01);
    try std.testing.expectApproxEqAbs(result.size.height, 1440.0, 0.01);
}

test "right half" {
    const result = layout.resolve(layout.layouts[1], test_sa, 0);
    try std.testing.expectApproxEqAbs(result.origin.x, 1280.0, 0.01);
    try std.testing.expectApproxEqAbs(result.size.width, 1280.0, 0.01);
    try std.testing.expectApproxEqAbs(result.size.height, 1440.0, 0.01);
}

test "top half" {
    const result = layout.resolve(layout.layouts[2], test_sa, 0);
    try std.testing.expectApproxEqAbs(result.size.width, 2560.0, 0.01);
    try std.testing.expectApproxEqAbs(result.size.height, 720.0, 0.01);
}

test "bottom half" {
    const result = layout.resolve(layout.layouts[3], test_sa, 0);
    try std.testing.expectApproxEqAbs(result.origin.y, 720.0, 0.01);
    try std.testing.expectApproxEqAbs(result.size.height, 720.0, 0.01);
}

test "top-left quarter" {
    const result = layout.resolve(layout.layouts[4], test_sa, 0);
    try std.testing.expectApproxEqAbs(result.origin.x, 0.0, 0.01);
    try std.testing.expectApproxEqAbs(result.origin.y, 0.0, 0.01);
    try std.testing.expectApproxEqAbs(result.size.width, 1280.0, 0.01);
    try std.testing.expectApproxEqAbs(result.size.height, 720.0, 0.01);
}

test "bottom-right quarter" {
    const result = layout.resolve(layout.layouts[7], test_sa, 0);
    try std.testing.expectApproxEqAbs(result.origin.x, 1280.0, 0.01);
    try std.testing.expectApproxEqAbs(result.origin.y, 720.0, 0.01);
    try std.testing.expectApproxEqAbs(result.size.width, 1280.0, 0.01);
    try std.testing.expectApproxEqAbs(result.size.height, 720.0, 0.01);
}

test "first vertical third" {
    const result = layout.resolve(layout.layouts[8], test_sa, 0);
    try std.testing.expectApproxEqAbs(result.origin.x, 0.0, 0.01);
    const expected_w = 2560.0 / 3.0;
    try std.testing.expectApproxEqAbs(result.size.width, expected_w, 0.01);
    try std.testing.expectApproxEqAbs(result.size.height, 1440.0, 0.01);
}

test "center vertical third" {
    const result = layout.resolve(layout.layouts[9], test_sa, 0);
    try std.testing.expectApproxEqAbs(result.origin.x, 2560.0 / 3.0, 0.01);
}

test "last vertical third" {
    const result = layout.resolve(layout.layouts[10], test_sa, 0);
    try std.testing.expectApproxEqAbs(result.origin.x, 2560.0 * 2.0 / 3.0, 0.01);
}

test "left two-thirds" {
    const result = layout.resolve(layout.layouts[14], test_sa, 0);
    try std.testing.expectApproxEqAbs(result.size.width, 2560.0 * 2.0 / 3.0, 0.01);
}

test "right two-thirds" {
    const result = layout.resolve(layout.layouts[15], test_sa, 0);
    try std.testing.expectApproxEqAbs(result.origin.x, 2560.0 / 3.0, 0.01);
    try std.testing.expectApproxEqAbs(result.size.width, 2560.0 * 2.0 / 3.0, 0.01);
}

test "top-left sixth" {
    const result = layout.resolve(layout.layouts[18], test_sa, 0);
    try std.testing.expectApproxEqAbs(result.origin.x, 0.0, 0.01);
    try std.testing.expectApproxEqAbs(result.origin.y, 0.0, 0.01);
    try std.testing.expectApproxEqAbs(result.size.width, 2560.0 / 3.0, 0.01);
    try std.testing.expectApproxEqAbs(result.size.height, 1440.0 / 2.0, 0.01);
}

test "bottom-right sixth" {
    const result = layout.resolve(layout.layouts[23], test_sa, 0);
    try std.testing.expectApproxEqAbs(result.origin.x, 2560.0 * 2.0 / 3.0, 0.01);
    try std.testing.expectApproxEqAbs(result.origin.y, 720.0, 0.01);
}

test "almost maximize" {
    const result = layout.resolve(layout.layouts[24], test_sa, 0);
    // 95% of 2560 = 2432, centred at 64px margin
    try std.testing.expectApproxEqAbs(result.size.width, 2560.0 * 19.0 / 20.0, 0.01);
    try std.testing.expectApproxEqAbs(result.size.height, 1440.0 * 19.0 / 20.0, 0.01);
}

test "gap is applied" {
    const result = layout.resolve(layout.layouts[0], test_sa, 10);
    // x origin shifted by gap, width reduced by 2*gap
    try std.testing.expectApproxEqAbs(result.origin.x, 10.0, 0.01);
    try std.testing.expectApproxEqAbs(result.size.width, 1260.0, 0.01);
}

test "all 25 layouts resolve without panic" {
    for (layout.layouts) |l| {
        const result = layout.resolve(l, test_sa, 0);
        try std.testing.expect(result.size.width >= 100.0);
        try std.testing.expect(result.size.height >= 100.0);
    }
}

test "layout_names has 25 entries" {
    try std.testing.expectEqual(layout.layout_names.len, 25);
}

test "layout resolve on non-zero origin safe area" {
    const sa = geo.Rect{
        .origin = .{ .x = 2560, .y = 40 }, // second display / non-zero origin
        .size = .{ .width = 1920, .height = 1160 },
    };
    const result = layout.resolve(layout.layouts[0], sa, 0); // Left Half
    try std.testing.expectApproxEqAbs(result.origin.x, 2560.0, 0.01);
    try std.testing.expectApproxEqAbs(result.origin.y, 40.0, 0.01);
    try std.testing.expectApproxEqAbs(result.size.width, 960.0, 0.01);
    try std.testing.expectApproxEqAbs(result.size.height, 1160.0, 0.01);
}

// ── Performance Tests ────────────────────────────────────────────────────

test "layout.resolve executes under 1µs average" {
    const start = std.time.nanoTimestamp();

    // Resolve all 25 layouts 1000 times each = 25,000 iterations
    for (0..1000) |_| {
        for (layout.layouts) |l| {
            const result = layout.resolve(l, test_sa, 0);
            // Prevent optimizer from eliminating the computation
            std.mem.doNotOptimizeAway(&result);
        }
    }

    const elapsed_ns = std.time.nanoTimestamp() - start;
    const per_resolve_ns = @divFloor(elapsed_ns, 25_000);

    // Each resolve should complete in under 1µs (1000ns)
    // This is a very generous budget; actual should be ~10-100ns
    try std.testing.expect(per_resolve_ns < 1000);
}

test "layout.resolve with gap executes efficiently" {
    const start = std.time.nanoTimestamp();

    // Test with various gap values
    const gaps = [_]u8{ 0, 5, 10, 20, 50 };

    for (0..200) |_| {
        for (gaps) |gap| {
            for (layout.layouts) |l| {
                const result = layout.resolve(l, test_sa, gap);
                std.mem.doNotOptimizeAway(&result);
            }
        }
    }

    // 200 * 5 * 25 = 25,000 iterations
    const elapsed_ns = std.time.nanoTimestamp() - start;
    const per_resolve_ns = @divFloor(elapsed_ns, 25_000);

    try std.testing.expect(per_resolve_ns < 1000);
}

test "all layouts resolve to minimum size constraints" {
    // Even with extreme gaps, layouts should never resolve to zero size
    const extreme_gap: u8 = 50;
    for (layout.layouts) |l| {
        const result = layout.resolve(l, test_sa, extreme_gap);
        try std.testing.expect(result.size.width >= 100.0);
        try std.testing.expect(result.size.height >= 100.0);
    }
}

test "layout fractions are mathematically sound" {
    // Verify that layout fractions produce expected coverage
    // Left half + Right half should cover full width
    const left = layout.resolve(layout.layouts[0], test_sa, 0);
    const right = layout.resolve(layout.layouts[1], test_sa, 0);

    const total_width = left.size.width + right.size.width;
    try std.testing.expectApproxEqAbs(total_width, test_sa.size.width, 0.01);

    // Top half + Bottom half should cover full height
    const top = layout.resolve(layout.layouts[2], test_sa, 0);
    const bottom = layout.resolve(layout.layouts[3], test_sa, 0);

    const total_height = top.size.height + bottom.size.height;
    try std.testing.expectApproxEqAbs(total_height, test_sa.size.height, 0.01);
}

test "thirds sum to whole" {
    // First third + Center third + Last third = full width
    const first = layout.resolve(layout.layouts[8], test_sa, 0);
    const center = layout.resolve(layout.layouts[9], test_sa, 0);
    const last = layout.resolve(layout.layouts[10], test_sa, 0);

    const total_width = first.size.width + center.size.width + last.size.width;
    try std.testing.expectApproxEqAbs(total_width, test_sa.size.width, 0.01);
}

test "sixths cover full screen" {
    // 6 sixths should cover full screen area
    var total_area: f64 = 0;
    for (18..24) |i| {
        const rect = layout.resolve(layout.layouts[i], test_sa, 0);
        total_area += rect.size.width * rect.size.height;
    }

    const expected_area = test_sa.size.width * test_sa.size.height;
    try std.testing.expectApproxEqAbs(total_area, expected_area, 1.0);
}
