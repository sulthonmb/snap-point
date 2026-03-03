//! 2-D geometry primitives used throughout SnapPoint.
//! All coordinates are f64, matching CGFloat on 64-bit macOS.

const std = @import("std");

pub const Point = struct {
    x: f64 = 0,
    y: f64 = 0,

    pub fn eql(a: Point, b: Point) bool {
        return a.x == b.x and a.y == b.y;
    }
};

pub const Size = struct {
    width:  f64 = 0,
    height: f64 = 0,

    pub fn eql(a: Size, b: Size) bool {
        return a.width == b.width and a.height == b.height;
    }
};

pub const Rect = struct {
    origin: Point = .{},
    size:   Size  = .{},

    pub fn eql(a: Rect, b: Rect) bool {
        return a.origin.eql(b.origin) and a.size.eql(b.size);
    }

    /// True when `point` falls inside or on the boundary of `self`.
    pub fn contains(self: Rect, point: Point) bool {
        return point.x >= self.origin.x
            and point.x <= self.origin.x + self.size.width
            and point.y >= self.origin.y
            and point.y <= self.origin.y + self.size.height;
    }

    /// True when `self` and `other` overlap (touching edges count).
    pub fn intersects(self: Rect, other: Rect) bool {
        return !(self.origin.x + self.size.width  < other.origin.x or
                 other.origin.x + other.size.width  < self.origin.x or
                 self.origin.y + self.size.height < other.origin.y or
                 other.origin.y + other.size.height < self.origin.y);
    }

    /// Geometric centre of the rect.
    pub fn center(self: Rect) Point {
        return .{
            .x = self.origin.x + self.size.width  * 0.5,
            .y = self.origin.y + self.size.height * 0.5,
        };
    }

    /// Right edge x coordinate.
    pub fn maxX(self: Rect) f64 { return self.origin.x + self.size.width; }
    /// Bottom edge y coordinate.
    pub fn maxY(self: Rect) f64 { return self.origin.y + self.size.height; }

    /// Inset rect by `dx` on left/right and `dy` on top/bottom.
    /// Returns a zero-size rect if inset is too large.
    pub fn inset(self: Rect, dx: f64, dy: f64) Rect {
        const new_w = @max(self.size.width  - dx * 2.0, 0.0);
        const new_h = @max(self.size.height - dy * 2.0, 0.0);
        return .{
            .origin = .{ .x = self.origin.x + dx, .y = self.origin.y + dy },
            .size   = .{ .width = new_w, .height = new_h },
        };
    }
};

// ── CGFloat / C interop helpers ──────────────────────────────────────────
// These extern structs match the macOS CG ABI so they can be cast directly
// to/from CGPoint / CGSize / CGRect without a copy.

pub const CGPoint = extern struct { x: f64, y: f64 };
pub const CGSize  = extern struct { width: f64, height: f64 };
pub const CGRect  = extern struct { origin: CGPoint, size: CGSize };

pub fn rectFromCG(cg: CGRect) Rect {
    return .{
        .origin = .{ .x = cg.origin.x, .y = cg.origin.y },
        .size   = .{ .width = cg.size.width, .height = cg.size.height },
    };
}

pub fn toCGPoint(p: Point) CGPoint {
    return .{ .x = p.x, .y = p.y };
}

pub fn toCGSize(s: Size) CGSize {
    return .{ .width = s.width, .height = s.height };
}

// ── Coordinate system conversion ─────────────────────────────────────────
// macOS has two coordinate systems:
//   CG  – origin at TOP-LEFT of the primary display   (used by AXUIElement)
//   NS  – origin at BOTTOM-LEFT of the primary display (used by NSScreen)
//
// When we obtain safe areas from NSScreen and pass positions to AXUIElement
// we must convert between them.

/// Convert an NSScreen rect (bottom-left origin) to a CG rect (top-left origin).
/// `primary_height` is the full pixel height of the primary display.
pub fn nsToCG(ns: Rect, primary_height: f64) Rect {
    return .{
        .origin = .{
            .x = ns.origin.x,
            .y = primary_height - ns.origin.y - ns.size.height,
        },
        .size = ns.size,
    };
}

/// Convert a CG rect (top-left origin) back to NS rect (bottom-left origin).
pub fn cgToNS(cg: Rect, primary_height: f64) Rect {
    return .{
        .origin = .{
            .x = cg.origin.x,
            .y = primary_height - cg.origin.y - cg.size.height,
        },
        .size = cg.size,
    };
}
