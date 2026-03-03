//! Config struct unit tests.

const std    = @import("std");
const config = @import("../src/core/config.zig");

test "default config has expected values" {
    const c = config.Config{};
    try std.testing.expect(!c.launch_at_login);
    try std.testing.expectEqual(c.snap_sensitivity, 10);
    try std.testing.expect(c.show_ghost_window);
    try std.testing.expectEqual(c.window_gap, 0);
    try std.testing.expectApproxEqAbs(c.ghost_opacity, 0.3, 0.001);
    try std.testing.expect(!c.has_completed_onboarding);
    try std.testing.expectEqual(c.config_version, 1);
}

test "default shortcuts count" {
    const c = config.Config{};
    try std.testing.expectEqual(c.shortcuts.len, 27);
}

test "default shortcuts are enabled" {
    const c = config.Config{};
    for (c.shortcuts) |s| {
        try std.testing.expect(s.enabled);
    }
}

test "blacklist empty by default" {
    const c = config.Config{};
    try std.testing.expectEqual(c.blacklist_count, 0);
    try std.testing.expect(!c.isBlacklisted("com.apple.finder"));
}

test "blacklist add and check" {
    var c = config.Config{};
    _ = c.addToBlacklist("com.example.app");
    try std.testing.expect(c.isBlacklisted("com.example.app"));
    try std.testing.expect(!c.isBlacklisted("com.other.app"));
}

test "blacklist multiple entries" {
    var c = config.Config{};
    _ = c.addToBlacklist("app.one");
    _ = c.addToBlacklist("app.two");
    _ = c.addToBlacklist("app.three");
    try std.testing.expect(c.isBlacklisted("app.one"));
    try std.testing.expect(c.isBlacklisted("app.two"));
    try std.testing.expect(c.isBlacklisted("app.three"));
    try std.testing.expect(!c.isBlacklisted("app.four"));
}

test "modifier bitfield" {
    const m = config.Modifiers{ .ctrl = true, .opt = true };
    try std.testing.expect(m.ctrl);
    try std.testing.expect(m.opt);
    try std.testing.expect(!m.cmd);
    try std.testing.expect(!m.shift);
}

test "left half shortcut default" {
    const c  = config.Config{};
    const sh = c.shortcuts[0]; // Left Half
    try std.testing.expect(sh.enabled);
    try std.testing.expect(sh.modifiers.ctrl);
    try std.testing.expect(sh.modifiers.opt);
    try std.testing.expect(!sh.modifiers.cmd);
    // key code 123 = left arrow
    try std.testing.expectEqual(sh.key_code, 123);
}
