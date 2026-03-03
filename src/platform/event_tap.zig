//! CGEventTap: intercepts mouse drag events (snap-on-drag) and
//! key-down events (global hotkeys) from a dedicated CFRunLoop source
//! on the main thread.
//!
//! Coordinate system note: CGEvent mouse locations are in CG space
//! (top-left origin of primary display), matching AXUIElement.

const std = @import("std");
const objc = @import("objc");
const log = @import("../core/log.zig");
const state_mod = @import("../core/state.zig");
const hotkey_mod = @import("../platform/hotkey.zig");
const snap_mod = @import("../engine/snap.zig");
const restore_mod = @import("../engine/restore.zig");
const accessibility = @import("../platform/accessibility.zig");
const zone_mod = @import("../engine/zone.zig");
const geo = @import("../util/geometry.zig");
const timer = @import("../util/timer.zig");

// ── C ABI types ───────────────────────────────────────────────────────────

pub const CGEventRef = *anyopaque;
pub const CGEventTapProxy = *anyopaque;
pub const CFMachPortRef = *anyopaque;
pub const CFRunLoopRef = *anyopaque;
pub const CFRunLoopSourceRef = *anyopaque;
pub const CFStringRef = *anyopaque;

// CGEventType numeric constants (uint32_t in CoreGraphics)
pub const CGEventType = struct {
    pub const null_event: u32 = 0;
    pub const left_mouse_down: u32 = 1;
    pub const left_mouse_up: u32 = 2;
    pub const right_mouse_down: u32 = 3;
    pub const right_mouse_up: u32 = 4;
    pub const mouse_moved: u32 = 5;
    pub const left_mouse_dragged: u32 = 6;
    pub const key_down: u32 = 10;
    pub const tap_disabled_by_timeout: u32 = 0xFFFFFFFE;
    pub const tap_disabled_by_user_input: u32 = 0xFFFFFFFF;
};

// kCGKeyboardEventKeycode field selector
const kCGKeyboardEventKeycode: c_int = 9;

// CGEventTapLocation
const kCGHIDEventTap: u32 = 0;
// CGEventTapPlacement
const kCGHeadInsertEventTap: u32 = 0;
// CGEventTapOptions
const kCGEventTapOptionDefault: u32 = 0; // active (can swallow events)
const kCGEventTapOptionListenOnly: u32 = 1; // passive (cannot swallow)

// CFRunLoopCommonModes constant (string pointer)
extern var kCFRunLoopCommonModes: CFStringRef;

// Minimum cursor movement (in points) to count as an intentional drag
const DRAG_THRESHOLD: f64 = 8.0;

// ── CGEventTap C API ─────────────────────────────────────────────────────

const CGEventTapCallBack = *const fn (CGEventTapProxy, u32, CGEventRef, ?*anyopaque) callconv(.c) ?CGEventRef;

extern fn CGEventTapCreate(
    tap: u32, // CGEventTapLocation
    place: u32, // CGEventTapPlacement
    options: u32, // CGEventTapOptions
    events_of_interest: u64, // CGEventMask
    callback: CGEventTapCallBack,
    user_info: ?*anyopaque,
) ?CFMachPortRef;

extern fn CFMachPortCreateRunLoopSource(
    allocator: ?*anyopaque,
    port: CFMachPortRef,
    order: isize,
) ?CFRunLoopSourceRef;

extern fn CFRunLoopGetMain() CFRunLoopRef;

extern fn CFRunLoopAddSource(
    rl: CFRunLoopRef,
    source: CFRunLoopSourceRef,
    mode: CFStringRef,
) void;

extern fn CGEventTapEnable(tap: CFMachPortRef, enable: bool) void;

extern fn CGEventGetFlags(event: CGEventRef) hotkey_mod.CGEventFlags;

extern fn CGEventGetIntegerValueField(
    event: CGEventRef,
    field: c_int,
) i64;

extern fn CGEventGetLocation(event: CGEventRef) geo.CGPoint;

extern fn CFRelease(cf: *anyopaque) void;

// ── Event mask helpers ───────────────────────────────────────────────────

fn mask(event_type: u32) u64 {
    if (event_type >= 64) return 0;
    return @as(u64, 1) << @as(u6, @intCast(event_type));
}

// ── Event tap callback ───────────────────────────────────────────────────

export fn snapEventCallback(
    _proxy: CGEventTapProxy,
    event_type: u32,
    event: CGEventRef,
    _user_info: ?*anyopaque,
) callconv(.c) ?CGEventRef {
    _ = _proxy;
    _ = _user_info;

    const s = &state_mod.g;

    switch (event_type) {

        // ── Tap re-enabled after timeout ──────────────────────────────
        CGEventType.tap_disabled_by_timeout, CGEventType.tap_disabled_by_user_input => {
            // The event will be a CFMachPortRef here per Apple docs.
            // We cast and re-enable.
            CGEventTapEnable(@ptrCast(event), true);
            log.warn("event_tap: re-enabled after system timeout", .{});
            return event;
        },

        // ── Mouse button down: begin drag tracking ────────────────────
        CGEventType.left_mouse_down => {
            const loc = CGEventGetLocation(event);
            s.drag = .{
                .active = true,
                .start = .{ .x = loc.x, .y = loc.y },
                .threshold_passed = false,
                .did_restore = false,
                .zone = .none,
            };
            return event;
        },

        // ── Mouse dragged: track drag, detect snap zone ───────────────
        CGEventType.left_mouse_dragged => {
            if (!s.drag.active) return event;

            const loc = CGEventGetLocation(event);
            const cursor = geo.Point{ .x = loc.x, .y = loc.y };

            // Check if drag has crossed the movement threshold
            if (!s.drag.threshold_passed) {
                const dx = cursor.x - s.drag.start.x;
                const dy = cursor.y - s.drag.start.y;
                const dist = @sqrt(dx * dx + dy * dy);
                if (dist < DRAG_THRESHOLD) return event;
                s.drag.threshold_passed = true;
            }

            // Restore original frame on first drag after a snap
            if (!s.drag.did_restore) {
                s.drag.did_restore = true;
                restoreIfSnapped();
            }

            // Find which display the cursor is on
            const disp = s.display_mgr.displayForPoint(cursor) orelse {
                s.drag.zone = .none;
                return event;
            };

            // Detect snap zone
            const detected = zone_mod.detectZone(
                cursor,
                disp.safe_area,
                s.config.snap_sensitivity,
            );

            if (detected != s.drag.zone) {
                s.drag.zone = detected;
                if (detected != .none) {
                    log.debug("event_tap: zone={s}", .{@tagName(detected)});
                    // Show ghost window at the resolved layout rect
                    if (state_mod.g_ghost) |*gw| {
                        if (state_mod.g.config.show_ghost_window) {
                            ghostShowForZone(gw, detected, disp.safe_area);
                        }
                    }
                } else {
                    // Cursor left all zones – hide the ghost window
                    if (state_mod.g_ghost) |*gw| gw.hide();
                }
            }

            return event;
        },

        // ── Mouse up: execute snap if zone active ─────────────────────
        CGEventType.left_mouse_up => {
            defer {
                s.drag.active = false;
                s.drag.zone = .none;
                // Always hide ghost window on mouse-up
                if (state_mod.g_ghost) |*gw| gw.hide();
            }

            if (!s.drag.active or !s.drag.threshold_passed) return event;
            if (s.drag.zone == .none) return event;

            const action = zoneToAction(s.drag.zone) orelse return event;
            const t0 = timer.now();

            snap_mod.executeSnap(action, &s.display_mgr, &s.config) catch |e| {
                log.warn("event_tap: snap failed: {any}", .{e});
            };

            log.info("event_tap: drag-snap {s} -> {d:.1}ms", .{ @tagName(action), timer.elapsedMillis(t0) });
            return event;
        },

        // ── Key down: check hotkeys ───────────────────────────────────
        CGEventType.key_down => {
            const raw_key = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
            if (raw_key < 0 or raw_key > 0xFFFF) return event;
            const key_code: u16 = @intCast(raw_key);
            const flags = CGEventGetFlags(event);

            if (s.hotkey_mgr.handleKeyEvent(key_code, flags)) |action| {
                const t0 = timer.now();
                snap_mod.executeSnap(action, &s.display_mgr, &s.config) catch |e| {
                    log.warn("event_tap: hotkey snap failed: {any}", .{e});
                };
                log.info("event_tap: hotkey {s} -> {d:.1}ms", .{ @tagName(action), timer.elapsedMillis(t0) });
                // Return null to swallow the keystroke (prevent app sees it)
                return null;
            }
            return event;
        },

        else => return event,
    }
}

// ── Restore-on-drag ───────────────────────────────────────────────────────

/// If the frontmost window was previously snapped (present in restore store),
/// restore it to its original frame.  This fires once at the start of a drag
/// so the window "unsticks" and the user drags a normally-proportioned window.
fn restoreIfSnapped() void {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    var wc = accessibility.WindowController.getFocusedWindow() catch return;
    defer wc.deinit();

    wc.restoreOriginalFrame() catch |e| {
        log.debug("event_tap: restore skipped ({any})", .{e});
    };
}

// ── Zone → Action mapping ─────────────────────────────────────────────────

fn zoneToAction(z: zone_mod.ZoneType) ?snap_mod.Action {
    return switch (z) {
        .none => null,
        .left_half => .snap_left_half,
        .right_half => .snap_right_half,
        .top_maximize => .snap_almost_maximize,
        .bottom_first_third => .snap_first_third,
        .bottom_center_third => .snap_center_third,
        .bottom_last_third => .snap_last_third,
        .top_left_quarter => .snap_top_left_quarter,
        .top_right_quarter => .snap_top_right_quarter,
        .bottom_left_quarter => .snap_bottom_left_quarter,
        .bottom_right_quarter => .snap_bottom_right_quarter,
    };
}

// ── Ghost window helper ─────────────────────────────────────────────────────

const layout_engine = @import("../engine/layout.zig");
const ghost_mod = @import("../ui/ghost_window.zig");

/// Resolve `zone` to a layout rect using `safe_area` and show `gw` there.
fn ghostShowForZone(
    gw: *ghost_mod.GhostWindow,
    zone: zone_mod.ZoneType,
    safe_area: geo.Rect,
) void {
    const action = zoneToAction(zone) orelse return;
    const layout_idx = @intFromEnum(action);
    if (layout_idx >= layout_engine.layouts.len) return;

    const rect = layout_engine.resolve(
        layout_engine.layouts[layout_idx],
        safe_area,
        state_mod.g.config.window_gap,
    );

    // Primary display height for CG → NS coordinate conversion.
    const primary_h: f64 = if (state_mod.g.display_mgr.primaryDisplay()) |pd|
        pd.frame.size.height
    else
        1440.0;

    gw.show(rect, primary_h, state_mod.g.config.ghost_opacity);
}

// ── Public API ────────────────────────────────────────────────────────────

/// Install the CGEventTap on the main CFRunLoop.
/// Call after NSApplication is initialised and state_mod.g is populated.
/// Returns error.TapCreateFailed if Accessibility is not granted.
pub fn install() !void {
    // Event mask: leftMouseDown | leftMouseUp | leftMouseDragged | keyDown
    const event_mask: u64 =
        mask(CGEventType.left_mouse_down) |
        mask(CGEventType.left_mouse_up) |
        mask(CGEventType.left_mouse_dragged) |
        mask(CGEventType.key_down);

    const tap = CGEventTapCreate(
        kCGHIDEventTap,
        kCGHeadInsertEventTap,
        kCGEventTapOptionDefault,
        event_mask,
        snapEventCallback,
        null, // user_info – we use the global state_mod.g instead
    ) orelse {
        log.err("event_tap: CGEventTapCreate failed (Accessibility not granted?)", .{});
        return error.TapCreateFailed;
    };

    const source = CFMachPortCreateRunLoopSource(null, tap, 0) orelse {
        CFRelease(tap);
        return error.RunLoopSourceFailed;
    };

    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CGEventTapEnable(tap, true);

    log.info("event_tap: installed (mouse + keyboard)", .{});
}
