//! Accessibility permission check and request.
//! Uses AXIsProcessTrusted() from the ApplicationServices framework.

const std   = @import("std");
const objc  = @import("objc");
const log   = @import("../core/log.zig");
const bridge = @import("../objc/bridge.zig");

// AXIsProcessTrusted – declared directly (ApplicationServices is linked).
extern fn AXIsProcessTrusted() bool;

/// Returns true if SnapPoint has been granted Accessibility access.
pub fn isGranted() bool {
    return AXIsProcessTrusted();
}

/// Open Privacy & Security > Accessibility in System Settings via deep link.
/// Call this when isGranted() returns false.
pub fn openSystemSettings() void {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const url_string = bridge.nsString(
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    );
    const NSURL = bridge.getClass("NSURL");
    const url = NSURL.msgSend(objc.Object, objc.sel("URLWithString:"), .{url_string});

    const ws = bridge.sharedWorkspace();
    _ = ws.msgSend(bool, objc.sel("openURL:"), .{url});

    log.info("permission: opened System Settings > Accessibility", .{});
}

/// Log current permission state for diagnostics.
pub fn logStatus() void {
    if (isGranted()) {
        log.info("permission: Accessibility GRANTED", .{});
    } else {
        log.warn("permission: Accessibility NOT granted – onboarding required", .{});
    }
}
