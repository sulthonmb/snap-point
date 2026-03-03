//! Structured logging for SnapPoint.
//! Phase 0: wraps std.debug.print (stderr).
//! TODO Phase 1+: replace with os_log via ObjC interop for Console.app integration.

const std     = @import("std");
const builtin = @import("builtin");

const prefix = "[SnapPoint] ";

pub fn info(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("[INFO]  " ++ prefix ++ fmt ++ "\n", args);
}

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    if (builtin.mode == .Debug) {
        std.debug.print("[DEBUG] " ++ prefix ++ fmt ++ "\n", args);
    }
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("[WARN]  " ++ prefix ++ fmt ++ "\n", args);
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("[ERROR] " ++ prefix ++ fmt ++ "\n", args);
}

pub fn fault(comptime fmt: []const u8, args: anytype) void {
    std.debug.print("[FAULT] " ++ prefix ++ fmt ++ "\n", args);
}
