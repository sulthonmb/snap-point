//! Geometry utility unit tests.

const std = @import("std");
const geo = @import("../src/util/geometry.zig");

fn rect(x: f64, y: f64, w: f64, h: f64) geo.Rect {
    return .{ .origin=.{.x=x,.y=y}, .size=.{.width=w,.height=h} };
}

test "rect contains point inside" {
    const r = rect(0, 0, 100, 100);
    try std.testing.expect(r.contains(.{ .x = 50, .y = 50 }));
}

test "rect contains point on boundary" {
    const r = rect(0, 0, 100, 100);
    try std.testing.expect(r.contains(.{ .x = 0, .y = 0 }));
    try std.testing.expect(r.contains(.{ .x = 100, .y = 100 }));
}

test "rect does not contain point outside" {
    const r = rect(0, 0, 100, 100);
    try std.testing.expect(!r.contains(.{ .x = 101, .y = 50 }));
    try std.testing.expect(!r.contains(.{ .x = -1,  .y = 50 }));
}

test "rect intersects overlapping" {
    const a = rect(0,   0, 100, 100);
    const b = rect(50, 50, 100, 100);
    try std.testing.expect(a.intersects(b));
    try std.testing.expect(b.intersects(a));
}

test "rect intersects touching edge" {
    const a = rect(0, 0, 100, 100);
    const b = rect(100, 0, 100, 100);
    try std.testing.expect(a.intersects(b));
}

test "rect does not intersect separate" {
    const a = rect(0, 0, 100, 100);
    const b = rect(200, 0, 100, 100);
    try std.testing.expect(!a.intersects(b));
}

test "rect center" {
    const r = rect(0, 0, 200, 100);
    const c = r.center();
    try std.testing.expectApproxEqAbs(c.x, 100.0, 0.001);
    try std.testing.expectApproxEqAbs(c.y,  50.0, 0.001);
}

test "rect center with offset origin" {
    const r = rect(100, 200, 400, 300);
    const c = r.center();
    try std.testing.expectApproxEqAbs(c.x, 300.0, 0.001);
    try std.testing.expectApproxEqAbs(c.y, 350.0, 0.001);
}

test "rect inset" {
    const r    = rect(0, 0, 200, 100);
    const inset = r.inset(10, 5);
    try std.testing.expectApproxEqAbs(inset.origin.x,    10.0, 0.001);
    try std.testing.expectApproxEqAbs(inset.origin.y,     5.0, 0.001);
    try std.testing.expectApproxEqAbs(inset.size.width,  180.0, 0.001);
    try std.testing.expectApproxEqAbs(inset.size.height,  90.0, 0.001);
}

test "rect maxX maxY" {
    const r = rect(10, 20, 100, 50);
    try std.testing.expectApproxEqAbs(r.maxX(), 110.0, 0.001);
    try std.testing.expectApproxEqAbs(r.maxY(),  70.0, 0.001);
}

test "nsToCG coordinate conversion" {
    // NS rect at bottom-left, primary height 1440
    const ns = geo.Rect{ .origin=.{.x=0,.y=0}, .size=.{.width=2560,.height=1417} };
    const cg = geo.nsToCG(ns, 1440.0);
    // CG y = 1440 - 0 - 1417 = 23  (menu bar is 23 pts high)
    try std.testing.expectApproxEqAbs(cg.origin.y, 23.0, 0.5);
    try std.testing.expectApproxEqAbs(cg.size.height, 1417.0, 0.001);
}

test "nsToCG and cgToNS are inverse" {
    const ns = geo.Rect{ .origin=.{.x=100,.y=200}, .size=.{.width=800,.height=600} };
    const cg = geo.nsToCG(ns, 2000.0);
    const back = geo.cgToNS(cg, 2000.0);
    try std.testing.expectApproxEqAbs(back.origin.x, ns.origin.x, 0.001);
    try std.testing.expectApproxEqAbs(back.origin.y, ns.origin.y, 0.001);
    try std.testing.expectApproxEqAbs(back.size.width,  ns.size.width,  0.001);
    try std.testing.expectApproxEqAbs(back.size.height, ns.size.height, 0.001);
}
