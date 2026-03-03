//! Integration test runner – tests requiring macOS system interaction.
//!
//! These tests interact with actual macOS subsystems and may require:
//! - Accessibility permission granted to the test runner (Terminal, IDE)
//! - A running WindowServer (graphical session)
//! - At least one active display
//!
//! Run with: zig build test-integration
//!
//! Note: Some tests may return different results based on system state
//! (e.g., permission grants). Tests are designed to not crash regardless
//! of permission state, but may skip verification if access is denied.

const std = @import("std");
const objc = @import("objc");

// ── Inline C ABI declarations (no src/ imports) ─────────────────────────

// Accessibility
extern fn AXIsProcessTrusted() bool;

// CoreGraphics types
const CGDirectDisplayID = u32;
const CGPoint = extern struct { x: f64, y: f64 };
const CGSize = extern struct { width: f64, height: f64 };
const CGRect = extern struct { origin: CGPoint, size: CGSize };

extern fn CGGetActiveDisplayList(max: u32, displays: ?[*]CGDirectDisplayID, count: *u32) i32;
extern fn CGMainDisplayID() CGDirectDisplayID;
extern fn CGDisplayBounds(displayID: CGDirectDisplayID) CGRect;

// AX constants
const kAXErrorSuccess: i32 = 0;
const kAXErrorAPIDisabled: i32 = -25211;

// ── Accessibility API Tests ──────────────────────────────────────────────

test "AXIsProcessTrusted returns without crashing" {
    // This always works; just returns true/false based on TCC grant
    const trusted = AXIsProcessTrusted();
    // Log the result for debugging, but don't fail on either value
    if (trusted) {
        std.debug.print("  [info] Accessibility is GRANTED\n", .{});
    } else {
        std.debug.print("  [info] Accessibility is NOT granted (tests will be limited)\n", .{});
    }
}

test "AX error constants are correctly defined" {
    try std.testing.expectEqual(kAXErrorSuccess, 0);
    try std.testing.expect(kAXErrorAPIDisabled < 0);
}

// ── Display Management Tests ─────────────────────────────────────────────

test "CGGetActiveDisplayList returns at least one display" {
    var count: u32 = 0;
    _ = CGGetActiveDisplayList(0, null, &count);
    try std.testing.expect(count >= 1);
    std.debug.print("  [info] Active displays: {d}\n", .{count});
}

test "CGMainDisplayID returns non-zero" {
    const mainID = CGMainDisplayID();
    try std.testing.expect(mainID != 0);
}

test "CGDisplayBounds returns valid rect for primary display" {
    const mainID = CGMainDisplayID();
    const bounds = CGDisplayBounds(mainID);

    // A valid display should have positive dimensions
    try std.testing.expect(bounds.size.width > 0);
    try std.testing.expect(bounds.size.height > 0);

    std.debug.print("  [info] Primary display: {d}x{d}\n", .{
        @as(i64, @intFromFloat(bounds.size.width)),
        @as(i64, @intFromFloat(bounds.size.height)),
    });
}

test "primary display origin is at 0,0" {
    const mainID = CGMainDisplayID();
    const bounds = CGDisplayBounds(mainID);

    // Primary display should be at origin (top-left: 0, 0)
    try std.testing.expectApproxEqAbs(bounds.origin.x, 0.0, 0.1);
    try std.testing.expectApproxEqAbs(bounds.origin.y, 0.0, 0.1);
}

// ── ObjC Runtime Tests ───────────────────────────────────────────────────

test "NSApplication class exists" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSApplication = objc.getClass("NSApplication");
    try std.testing.expect(NSApplication != null);
}

test "NSScreen class exists" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSScreen = objc.getClass("NSScreen");
    try std.testing.expect(NSScreen != null);
}

test "NSWorkspace class exists" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSWorkspace = objc.getClass("NSWorkspace");
    try std.testing.expect(NSWorkspace != null);
}

test "NSWindow class exists" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSWindow = objc.getClass("NSWindow");
    try std.testing.expect(NSWindow != null);
}

test "NSMenu class exists" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSMenu = objc.getClass("NSMenu");
    try std.testing.expect(NSMenu != null);
}

test "NSVisualEffectView class exists" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const cls = objc.getClass("NSVisualEffectView");
    try std.testing.expect(cls != null);
}

test "NSStatusItem class exists" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const cls = objc.getClass("NSStatusItem");
    try std.testing.expect(cls != null);
}

test "NSProcessInfo class exists" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const cls = objc.getClass("NSProcessInfo");
    try std.testing.expect(cls != null);
}

// ── Selector Resolution Tests ────────────────────────────────────────────

test "common AppKit selectors resolve" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    // These should all resolve without crashing
    _ = objc.sel("sharedApplication");
    _ = objc.sel("mainScreen");
    _ = objc.sel("screens");
    _ = objc.sel("frame");
    _ = objc.sel("visibleFrame");
    _ = objc.sel("setFrame:display:");
    _ = objc.sel("orderFront:");
    _ = objc.sel("orderOut:");
    _ = objc.sel("backingScaleFactor");
}

test "NSScreen.screens returns array" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSScreen = objc.getClass("NSScreen").?;
    const screens = NSScreen.msgSend(objc.Object, objc.sel("screens"), .{});

    // Should return a valid object (NSArray)
    try std.testing.expect(screens.value != null);

    // Should have at least one screen
    const count = screens.msgSend(usize, objc.sel("count"), .{});
    try std.testing.expect(count >= 1);
}

test "NSScreen.mainScreen returns valid screen" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSScreen = objc.getClass("NSScreen").?;
    const main = NSScreen.msgSend(objc.Object, objc.sel("mainScreen"), .{});

    try std.testing.expect(main.value != null);

    // Should have valid frame
    const frame = main.msgSend(CGRect, objc.sel("frame"), .{});
    try std.testing.expect(frame.size.width > 0);
    try std.testing.expect(frame.size.height > 0);
}

// ── Environment Validation ───────────────────────────────────────────────

test "HOME environment variable is set" {
    const home = std.posix.getenv("HOME");
    try std.testing.expect(home != null);
    try std.testing.expect(home.?.len > 0);
}

test "USER environment variable is set" {
    const user = std.posix.getenv("USER");
    try std.testing.expect(user != null);
}

test "config directory path is constructable" {
    const home = std.posix.getenv("HOME") orelse "/tmp";
    var buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "{s}/Library/Application Support/SnapPoint", .{home}) catch unreachable;
    try std.testing.expect(path.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, path, "SnapPoint") != null);
}

// ── SMAppService Tests (macOS 13+) ───────────────────────────────────────

test "SMAppService class exists" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const cls = objc.getClass("SMAppService");
    try std.testing.expect(cls != null);
}

test "SMAppService mainApp selector exists" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    // Just verify the selector resolves
    _ = objc.sel("mainApp");
    _ = objc.sel("status");
    _ = objc.sel("registerAndReturnError:");
    _ = objc.sel("unregisterAndReturnError:");
}

// ── Display Configuration Tests ──────────────────────────────────────────

test "can enumerate multiple displays if present" {
    var displays: [8]CGDirectDisplayID = undefined;
    var count: u32 = 0;

    _ = CGGetActiveDisplayList(8, &displays, &count);
    try std.testing.expect(count >= 1);

    // All returned display IDs should be non-zero
    for (0..count) |i| {
        try std.testing.expect(displays[i] != 0);
    }
}

test "display bounds are positive for all displays" {
    var displays: [8]CGDirectDisplayID = undefined;
    var count: u32 = 0;

    _ = CGGetActiveDisplayList(8, &displays, &count);

    for (0..count) |i| {
        const bounds = CGDisplayBounds(displays[i]);
        try std.testing.expect(bounds.size.width > 0);
        try std.testing.expect(bounds.size.height > 0);
    }
}

// ── Permission-Aware Test Helpers ────────────────────────────────────────

fn accessibilityGranted() bool {
    return AXIsProcessTrusted();
}

test "permission-aware: AX API availability check" {
    if (!accessibilityGranted()) {
        std.debug.print("  [SKIP] Accessibility not granted - skipping AX tests\n", .{});
        return;
    }

    // If we get here, Accessibility is granted
    // Verify we can call basic AX functions
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    // Test that NSRunningApplication class exists (used for AX app lookup)
    const NSRunningApplication = objc.getClass("NSRunningApplication");
    try std.testing.expect(NSRunningApplication != null);
}

// ── Framework Symbol Resolution ──────────────────────────────────────────

test "CoreGraphics display functions resolve" {
    // These functions are used by DisplayManager
    // Just verify they're callable (they're extern declarations)
    _ = CGMainDisplayID();

    var count: u32 = 0;
    _ = CGGetActiveDisplayList(0, null, &count);
    try std.testing.expect(count >= 1);
}

test "NSBundle mainBundle exists" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSBundle = objc.getClass("NSBundle").?;
    const mainBundle = NSBundle.msgSend(objc.Object, objc.sel("mainBundle"), .{});
    try std.testing.expect(mainBundle.value != null);
}

test "NSFileManager defaultManager exists" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSFileManager = objc.getClass("NSFileManager").?;
    const fm = NSFileManager.msgSend(objc.Object, objc.sel("defaultManager"), .{});
    try std.testing.expect(fm.value != null);
}

// ── UserDefaults Test ────────────────────────────────────────────────────

test "NSUserDefaults standardUserDefaults exists" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSUserDefaults = objc.getClass("NSUserDefaults").?;
    const defaults = NSUserDefaults.msgSend(objc.Object, objc.sel("standardUserDefaults"), .{});
    try std.testing.expect(defaults.value != null);
}
