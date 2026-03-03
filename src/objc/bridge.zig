//! Type-safe helpers built on top of the raw zig-objc API.
//! Centralises class/selector lookups and provides ergonomic wrappers
//! so application code avoids sprinkling .? and @as casts everywhere.

const std  = @import("std");
const objc = @import("objc");

// ── Class resolution ────────────────────────────────────────────────────

/// Return an ObjC class, panicking with a useful message when missing.
pub fn getClass(name: [:0]const u8) objc.Class {
    return objc.getClass(name) orelse
        std.debug.panic("ObjC class not found: {s}", .{name});
}

// ── Common singletons ───────────────────────────────────────────────────

/// NSApplication.sharedApplication
pub fn sharedApplication() objc.Object {
    return getClass("NSApplication")
        .msgSend(objc.Object, objc.sel("sharedApplication"), .{});
}

/// NSWorkspace.sharedWorkspace
pub fn sharedWorkspace() objc.Object {
    return getClass("NSWorkspace")
        .msgSend(objc.Object, objc.sel("sharedWorkspace"), .{});
}

// ── NSString helpers ────────────────────────────────────────────────────

/// Wrap a Zig slice in an NSString (UTF-8).
/// The returned object is autoreleased; keep a pool alive.
pub fn nsString(str: []const u8) objc.Object {
    return getClass("NSString").msgSend(
        objc.Object,
        objc.sel("stringWithUTF8String:"),
        .{str.ptr},
    );
}

/// Copy a NULL-terminated C string out of an NSString into a Zig buffer.
/// Returns a slice of `buf`; caller must ensure `buf` is large enough.
pub fn zigString(ns_str: objc.Object, buf: []u8) []const u8 {
    const c_str: [*:0]const u8 = ns_str.msgSend(
        [*:0]const u8,
        objc.sel("UTF8String"),
        .{},
    );
    const len = std.mem.len(c_str);
    const copy_len = @min(len, buf.len);
    @memcpy(buf[0..copy_len], c_str[0..copy_len]);
    return buf[0..copy_len];
}

// ── BOOL helpers ────────────────────────────────────────────────────────
    // On macOS (Xcode SDK), ObjC BOOL is `bool`. Use these helpers for
    // cross-platform clarity and to match the zig-objc boolResult/boolParam API.
    pub inline fn fromBool(b: bool) bool { return b; }
    pub inline fn toBool(b: bool) bool   { return b; }
// ── NSLog (convenience, visible in Console.app) ─────────────────────────
// Uses NSLog via a format-less string to avoid variadic C call issues.
pub fn nsLog(comptime fmt: []const u8, args: anytype) void {
    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, "[SnapPoint] " ++ fmt, args)
        catch "[SnapPoint] <log fmt error>";
    const ns_str = nsString(msg);
    // NSLog(NSString *format, ...) — pass NSString directly as the format.
    // Using %@ would require a second variadic arg; instead pass the
    // message as the format string (it contains no % characters after
    // bufPrintZ, since our fmt is comptime).
    _ = getClass("NSString").msgSend(
        objc.Object,
        objc.sel("stringWithFormat:"),
        .{ns_str},
    );
    // For Phase 0 also mirror to stderr so it appears during development.
    @import("std").debug.print("[NSLog] {s}\n", .{msg});
}
