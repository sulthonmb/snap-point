//! Display enumeration and safe-area calculation.
//! Uses CGDisplay (C API) for display IDs and bounds,
//! NSScreen (ObjC) for the usable area (minus Dock and menu bar).

const std = @import("std");
const objc = @import("objc");
const log = @import("../core/log.zig");
const bridge = @import("../objc/bridge.zig");
const geo = @import("../util/geometry.zig");

// ── C ABI declarations (CoreGraphics) ────────────────────────────────────

pub const CGDirectDisplayID = u32;

extern fn CGGetActiveDisplayList(
    maxDisplays: u32,
    activeDisplays: [*]CGDirectDisplayID,
    displayCount: *u32,
) i32;

extern fn CGDisplayBounds(displayID: CGDirectDisplayID) geo.CGRect;
extern fn CGMainDisplayID() CGDirectDisplayID;
extern fn CGDisplayScreenSize(displayID: CGDirectDisplayID) geo.CGSize;
extern fn CGDisplayModeGetPixelWidth(mode: *anyopaque) usize;
extern fn CGDisplayModeGetPixelHeight(mode: *anyopaque) usize;

// ── Display reconfiguration callback (CGDisplayRegisterReconfigurationCallback)

/// Bitmask passed to the reconfiguration callback indicating what changed.
pub const CGDisplayChangeSummaryFlags = u32;
/// Callback function type for display reconfiguration events.
pub const CGDisplayReconfigCallbackFn = *const fn (
    CGDirectDisplayID,
    CGDisplayChangeSummaryFlags,
    ?*anyopaque,
) callconv(.c) void;

extern fn CGDisplayRegisterReconfigurationCallback(
    callback: CGDisplayReconfigCallbackFn,
    userInfo: ?*anyopaque,
) i32;

/// Register a CGDisplay reconfiguration callback.
/// When registered from the main thread (which has a CFRunLoop), macOS
/// delivers the callback on that same thread via the main run loop.
/// Call once during app startup after the DisplayManager is initialised.
pub fn registerChangeCallback(callback: CGDisplayReconfigCallbackFn) void {
    _ = CGDisplayRegisterReconfigurationCallback(callback, null);
    log.info("display: registered reconfiguration callback", .{});
}

// ── DisplayInfo ──────────────────────────────────────────────────────────

pub const DisplayInfo = struct {
    display_id: CGDirectDisplayID,
    /// Full display bounds in CG coordinates (top-left origin, points).
    frame: geo.Rect,
    /// Usable area after subtracting menu bar and Dock (CG coordinates).
    safe_area: geo.Rect,
    /// Retina backing scale factor (1.0 on non-Retina, 2.0+ on Retina).
    scale_factor: f64,
    /// True for the display that holds the menu bar.
    is_primary: bool,
};

// ── DisplayManager ───────────────────────────────────────────────────────

/// Maximum number of simultaneously connected displays we support.
const MAX_DISPLAYS = 8;

pub const DisplayManager = struct {
    displays: [MAX_DISPLAYS]DisplayInfo,
    count: usize,

    pub fn init() DisplayManager {
        return .{ .displays = undefined, .count = 0 };
    }

    /// Enumerate all active displays.  Call once at startup, and again
    /// whenever a display configuration change notification arrives.
    pub fn refresh(self: *DisplayManager) !void {
        const pool = objc.AutoreleasePool.init();
        defer pool.deinit();

        // Query CGDisplay for active display IDs
        var ids: [MAX_DISPLAYS]CGDirectDisplayID = undefined;
        var cg_count: u32 = 0;
        _ = CGGetActiveDisplayList(MAX_DISPLAYS, &ids, &cg_count);
        const n = @min(cg_count, MAX_DISPLAYS);

        const primary_id = CGMainDisplayID();
        const primary_cg = CGDisplayBounds(primary_id);
        const primary_height = primary_cg.size.height;

        // Collect NSScreen objects so we can read visibleFrame (safe area).
        // NSScreen.screens returns an NSArray ordered front-to-back.
        const NSScreen = bridge.getClass("NSScreen");
        const screens_arr = NSScreen.msgSend(objc.Object, objc.sel("screens"), .{});

        self.count = 0;
        for (0..n) |i| {
            const did = ids[i];
            const cg_bounds = CGDisplayBounds(did);
            const frame_cg = geo.rectFromCG(cg_bounds);

            // Match a CGDisplay to an NSScreen by comparing frame origins.
            // NSScreen.frame is in NS coords (bottom-left origin).
            const safe_cg = findSafeArea(screens_arr, did, frame_cg, primary_height);

            // Compute backing scale factor
            const scale = getScaleFactor(screens_arr, frame_cg, primary_height);

            self.displays[self.count] = .{
                .display_id = did,
                .frame = frame_cg,
                .safe_area = safe_cg,
                .scale_factor = scale,
                .is_primary = (did == primary_id),
            };
            self.count += 1;

            log.debug("display: id={d} primary={} frame=({d:.0}x{d:.0}) safe=({d:.0}x{d:.0})", .{
                did,                 did == primary_id,
                frame_cg.size.width, frame_cg.size.height,
                safe_cg.size.width,  safe_cg.size.height,
            });
        }

        log.info("display: refreshed, {d} display(s) found", .{self.count});
    }

    /// Find which display contains `point` (CG coordinates).
    pub fn displayForPoint(self: *DisplayManager, point: geo.Point) ?*DisplayInfo {
        for (self.displays[0..self.count]) |*d| {
            if (d.frame.contains(point)) return d;
        }
        return null;
    }

    /// Find which display a window (given its CG-coords rect) currently lives on,
    /// by checking which display contains the window's midpoint.
    pub fn displayForRect(self: *DisplayManager, rect: geo.Rect) ?*DisplayInfo {
        return self.displayForPoint(rect.center());
    }

    /// Return the display after `current_id` in the ordered list, cycling back.
    pub fn nextDisplay(self: *DisplayManager, current_id: CGDirectDisplayID) ?*DisplayInfo {
        if (self.count < 2) return null;
        for (self.displays[0..self.count], 0..) |d, i| {
            if (d.display_id == current_id) {
                return &self.displays[if (i + 1 >= self.count) 0 else i + 1];
            }
        }
        return null;
    }

    /// Return the display before `current_id`, cycling at the beginning.
    pub fn prevDisplay(self: *DisplayManager, current_id: CGDirectDisplayID) ?*DisplayInfo {
        if (self.count < 2) return null;
        for (self.displays[0..self.count], 0..) |d, i| {
            if (d.display_id == current_id) {
                return &self.displays[if (i == 0) self.count - 1 else i - 1];
            }
        }
        return null;
    }

    /// Return the primary display (holds the menu bar).
    pub fn primaryDisplay(self: *DisplayManager) ?*DisplayInfo {
        for (self.displays[0..self.count]) |*d| {
            if (d.is_primary) return d;
        }
        return null;
    }
};

// ── Standalone helpers for testing ────────────────────────────────────────

/// Return the number of active displays (quick query, no ObjC).
pub fn getActiveDisplayCount() u32 {
    var count: u32 = 0;
    _ = CGGetActiveDisplayList(0, @as([*]CGDirectDisplayID, @ptrFromInt(0)), &count);
    return count;
}

/// Return the bounds of the primary (main) display in CG coordinates.
pub fn getPrimaryDisplayBounds() geo.Rect {
    const cg = CGDisplayBounds(CGMainDisplayID());
    return geo.rectFromCG(cg);
}

/// Return the safe area (visible frame) of the main display in CG coordinates.
/// This accounts for the menu bar and Dock.
pub fn getMainDisplaySafeArea() geo.Rect {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSScreen = bridge.getClass("NSScreen");
    const main_screen = NSScreen.msgSend(objc.Object, objc.sel("mainScreen"), .{});

    // Get primary display height for coordinate conversion
    const primary_cg = CGDisplayBounds(CGMainDisplayID());
    const primary_height = primary_cg.size.height;

    const ns_visible = main_screen.msgSend(geo.CGRect, objc.sel("visibleFrame"), .{});
    return geo.nsToCG(geo.rectFromCG(ns_visible), primary_height);
}

// ── Internal helpers ──────────────────────────────────────────────────────

/// Walk NSScreen.screens and find the screen whose NS frame (converted to CG)
/// matches `frame_cg` origin.  Return its visibleFrame in CG coordinates.
fn findSafeArea(
    screens_arr: objc.Object,
    _did: CGDirectDisplayID,
    frame_cg: geo.Rect,
    primary_height: f64,
) geo.Rect {
    _ = _did;
    const count = screens_arr.msgSend(usize, objc.sel("count"), .{});
    for (0..count) |i| {
        const screen = screens_arr.msgSend(
            objc.Object,
            objc.sel("objectAtIndex:"),
            .{i},
        );

        // NSScreen.frame in NS coords (bottom-left origin)
        const ns_frame = screen.msgSend(geo.CGRect, objc.sel("frame"), .{});
        const cg_frame = geo.nsToCG(geo.rectFromCG(ns_frame), primary_height);

        // Match by comparing frame origin (within 1 logical pixel)
        if (@abs(cg_frame.origin.x - frame_cg.origin.x) < 1.0 and
            @abs(cg_frame.origin.y - frame_cg.origin.y) < 1.0)
        {
            const ns_visible = screen.msgSend(geo.CGRect, objc.sel("visibleFrame"), .{});
            return geo.nsToCG(geo.rectFromCG(ns_visible), primary_height);
        }
    }
    // Fallback: return the full CG frame as safe area
    return frame_cg;
}

/// Return the backing scale factor for the NSScreen whose CG frame matches.
fn getScaleFactor(
    screens_arr: objc.Object,
    frame_cg: geo.Rect,
    primary_height: f64,
) f64 {
    const count = screens_arr.msgSend(usize, objc.sel("count"), .{});
    for (0..count) |i| {
        const screen = screens_arr.msgSend(objc.Object, objc.sel("objectAtIndex:"), .{i});
        const ns_frame = screen.msgSend(geo.CGRect, objc.sel("frame"), .{});
        const cg_frame = geo.nsToCG(geo.rectFromCG(ns_frame), primary_height);
        if (@abs(cg_frame.origin.x - frame_cg.origin.x) < 1.0 and
            @abs(cg_frame.origin.y - frame_cg.origin.y) < 1.0)
        {
            return screen.msgSend(f64, objc.sel("backingScaleFactor"), .{});
        }
    }
    return 1.0;
}
