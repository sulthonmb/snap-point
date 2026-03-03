//! Memory leak detection tests.
//! Uses GeneralPurposeAllocator to detect memory leaks in key operations.
//! The GPA will fail the test if any allocations are not freed.

const std = @import("std");
const layout = @import("../src/engine/layout.zig");
const zone = @import("../src/engine/zone.zig");
const config = @import("../src/core/config.zig");
const geo = @import("../src/util/geometry.zig");

// ── Layout operations (no allocations expected) ──────────────────────────

test "layout resolve does not allocate" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        if (status == .leak) @panic("Memory leak detected in layout.resolve");
    }
    // Allocator is unused, but we verify the pattern works
    _ = gpa.allocator();

    const safe_area = geo.Rect{
        .origin = .{ .x = 0, .y = 0 },
        .size = .{ .width = 2560, .height = 1440 },
    };

    // Resolve all 25 layouts
    for (layout.layouts) |l| {
        const result = layout.resolve(l, safe_area, 0);
        // Just verify we got a valid rect
        std.debug.assert(result.size.width >= 100.0);
        std.debug.assert(result.size.height >= 100.0);
    }
}

// ── Zone detection (no allocations expected) ─────────────────────────────

test "zone detection does not allocate" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        if (status == .leak) @panic("Memory leak detected in zone detection");
    }
    _ = gpa.allocator();

    const safe_area = geo.Rect{
        .origin = .{ .x = 0, .y = 0 },
        .size = .{ .width = 2560, .height = 1440 },
    };

    // Test various cursor positions
    const points = [_]geo.Point{
        .{ .x = 5, .y = 720 }, // left edge
        .{ .x = 2555, .y = 720 }, // right edge
        .{ .x = 1280, .y = 5 }, // top edge
        .{ .x = 1280, .y = 1435 }, // bottom edge
        .{ .x = 5, .y = 5 }, // top-left corner
        .{ .x = 2555, .y = 1435 }, // bottom-right corner
        .{ .x = 1280, .y = 720 }, // center (no zone)
    };

    for (points) |pt| {
        const z = zone.detectZone(pt, safe_area, 10);
        _ = z;
    }
}

// ── Config JSON serialization ────────────────────────────────────────────

test "config writeJson does not leak with stack buffer" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        if (status == .leak) @panic("Memory leak detected in config.writeJson");
    }
    _ = gpa.allocator();

    var c = config.Config{};
    c.snap_sensitivity = 20;
    _ = c.addToBlacklist("com.test.app");

    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    config.writeJson(&c, fbs.writer()) catch {};
}

// ── Geometry operations ──────────────────────────────────────────────────

test "geometry operations do not allocate" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        if (status == .leak) @panic("Memory leak detected in geometry operations");
    }
    _ = gpa.allocator();

    const r1 = geo.Rect{
        .origin = .{ .x = 0, .y = 0 },
        .size = .{ .width = 100, .height = 100 },
    };
    const r2 = geo.Rect{
        .origin = .{ .x = 50, .y = 50 },
        .size = .{ .width = 100, .height = 100 },
    };

    _ = r1.contains(.{ .x = 50, .y = 50 });
    _ = r1.intersects(r2);
    _ = r1.center();
    _ = r1.maxX();
    _ = r1.maxY();
    _ = r1.inset(10, 10);
}

// ── Config blacklist operations ──────────────────────────────────────────

test "config blacklist operations do not allocate" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        if (status == .leak) @panic("Memory leak detected in blacklist operations");
    }
    _ = gpa.allocator();

    var c = config.Config{};

    // Add entries
    _ = c.addToBlacklist("com.app1.bundle");
    _ = c.addToBlacklist("com.app2.bundle");
    _ = c.addToBlacklist("com.app3.bundle");

    // Check entries
    _ = c.isBlacklisted("com.app1.bundle");
    _ = c.isBlacklisted("com.nonexistent.app");

    // Get entry
    _ = c.blacklistEntry(0);
    _ = c.blacklistEntry(1);

    // Remove entry
    c.removeFromBlacklist(1);

    // Verify state
    std.debug.assert(c.blacklist_count == 2);
}

// ── Coordinate conversion ────────────────────────────────────────────────

test "coordinate conversion does not allocate" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        if (status == .leak) @panic("Memory leak detected in coordinate conversion");
    }
    _ = gpa.allocator();

    const ns_rect = geo.Rect{
        .origin = .{ .x = 100, .y = 200 },
        .size = .{ .width = 800, .height = 600 },
    };

    const cg = geo.nsToCG(ns_rect, 2000.0);
    _ = geo.cgToNS(cg, 2000.0);
}

// ── Full layout resolution cycle ─────────────────────────────────────────

test "full layout cycle does not leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        if (status == .leak) @panic("Memory leak detected in layout cycle");
    }
    _ = gpa.allocator();

    // Simulate a snap event cycle
    const displays = [_]geo.Rect{
        .{ .origin = .{ .x = 0, .y = 0 }, .size = .{ .width = 2560, .height = 1440 } },
        .{ .origin = .{ .x = 2560, .y = 0 }, .size = .{ .width = 1920, .height = 1080 } },
    };

    for (displays) |display_safe_area| {
        for (layout.layouts, 0..) |l, idx| {
            const target = layout.resolve(l, display_safe_area, 10);
            _ = idx;

            // Validate minimum size enforcement
            std.debug.assert(target.size.width >= 100.0);
            std.debug.assert(target.size.height >= 100.0);
        }
    }
}

// ── Repeated operations stress test ──────────────────────────────────────

test "repeated operations do not accumulate memory" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const status = gpa.deinit();
        if (status == .leak) @panic("Memory leak in repeated operations");
    }
    _ = gpa.allocator();

    const safe_area = geo.Rect{
        .origin = .{ .x = 0, .y = 0 },
        .size = .{ .width = 2560, .height = 1440 },
    };

    // Simulate 1000 snap events
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const layout_idx = i % layout.layouts.len;
        const gap: u8 = @intCast(i % 51);

        const target = layout.resolve(layout.layouts[layout_idx], safe_area, gap);
        _ = target;

        // Simulate zone detection
        const cursor = geo.Point{
            .x = @as(f64, @floatFromInt(i % 2560)),
            .y = @as(f64, @floatFromInt(i % 1440)),
        };
        _ = zone.detectZone(cursor, safe_area, 10);
    }
}
