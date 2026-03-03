//! SnapPoint – entry point.
//! Phase 5: Multi-monitor display change handling, Check for Updates.

const std = @import("std");
const objc = @import("objc");
const app_mod = @import("core/app.zig");
const log = @import("core/log.zig");
const constants = @import("core/constants.zig");
const config_mod = @import("core/config.zig");
const state_mod = @import("core/state.zig");
const perm = @import("platform/permission.zig");
const display = @import("platform/display.zig");
const event_tap = @import("platform/event_tap.zig");
const ghost_mod = @import("ui/ghost_window.zig");
const status_mod = @import("ui/status_bar.zig");
const onboarding_mod = @import("ui/onboarding.zig");

pub fn main() !void {
    var pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    log.info("SnapPoint v{s} starting", .{constants.version.string});

    // ── Permission check ────────────────────────────────────────────────
    perm.logStatus();
    if (!perm.isGranted()) {
        log.warn("main: Accessibility not granted – event tap will fail", .{});
        perm.openSystemSettings();
        // In the shipped app the onboarding window handles this gracefully.
        // For development: grant Accessibility in System Settings, re-launch.
    }

    // ── Allocator & config ──────────────────────────────────────────────
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = config_mod.Config{};
    config_mod.load(&config, allocator) catch |e| {
        log.warn("main: config load failed ({any}); using defaults", .{e});
    };

    // ── Display enumeration ─────────────────────────────────────────────
    var display_mgr = display.DisplayManager.init();
    display_mgr.refresh() catch |e| {
        log.warn("main: display refresh failed ({any})", .{e});
    };

    // ── Bootstrap NSApplication ─────────────────────────────────────────
    try app_mod.init();

    // ── Initialise global state (used by CGEventTap callback) ───────────
    state_mod.init(config, display_mgr);

    // ── Ghost window (translucent snap preview overlay) ─────────────────
    state_mod.g_ghost = ghost_mod.GhostWindow.init();

    // ── Menu bar status item ─────────────────────────────────────────────
    state_mod.g_status_bar = status_mod.StatusBar.init();

    // ── Onboarding (Phase 4) ─────────────────────────────────────────────
    // Show three-step onboarding on first launch (or when permission was lost).
    if (!state_mod.g.config.has_completed_onboarding or !perm.isGranted()) {
        state_mod.g_onboarding = onboarding_mod.OnboardingWindow.init();
        if (state_mod.g_onboarding) |*ow| ow.show();
    }

    // ── Install CGEventTap ──────────────────────────────────────────────
    event_tap.install() catch |e| {
        log.err("main: event tap not installed: {any}", .{e});
        log.err("main: Grant Accessibility in System Settings and restart.", .{});
    };

    // ── Register display reconfiguration callback ───────────────────────
    display.registerChangeCallback(onDisplayReconfigured);

    // ── Enter run loop (blocks until quit) ─────────────────────────────
    app_mod.run();

    // ── Cleanup ─────────────────────────────────────────────────────────
    if (state_mod.g_ghost) |*gw| gw.deinit();
    if (state_mod.g_onboarding) |*ow| ow.close();
}

// ── Display reconfiguration callback ─────────────────────────────────────

/// CGDisplay calls this when a display is connected, disconnected, or
/// reconfigured.  Registered from the main thread, so macOS delivers this
/// callback via the main CFRunLoop — safe to call ObjC (NSScreen) directly.
export fn onDisplayReconfigured(
    _display_id: display.CGDirectDisplayID,
    _flags: display.CGDisplayChangeSummaryFlags,
    _user_info: ?*anyopaque,
) callconv(.c) void {
    _ = _display_id;
    _ = _flags;
    _ = _user_info;
    state_mod.g.display_mgr.refresh() catch |e| {
        log.warn("main: display reconfiguration refresh failed: {any}", .{e});
    };
    log.info("main: display topology updated after reconfiguration", .{});
}
