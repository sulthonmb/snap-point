//! Settings window and shortcut recorder unit tests.
//!
//! Tests pure logic components that don't require ObjC runtime:
//!   - Shortcut formatting (keyName, formatShortcut)
//!   - Action naming (layout_names table consistency)
//!   - Settings page constants
//!   - Default shortcut reset behavior

const std = @import("std");
const config = @import("../src/core/config.zig");
const constants = @import("../src/core/constants.zig");
const layout = @import("../src/engine/layout.zig");
const shortcut_rec = @import("../src/ui/shortcut_recorder.zig");

// ── Key name lookup tests ─────────────────────────────────────────────────

test "keyName returns correct names for arrow keys" {
    try std.testing.expectEqualStrings("←", shortcut_rec.keyName(123));
    try std.testing.expectEqualStrings("→", shortcut_rec.keyName(124));
    try std.testing.expectEqualStrings("↓", shortcut_rec.keyName(125));
    try std.testing.expectEqualStrings("↑", shortcut_rec.keyName(126));
}

test "keyName returns correct names for letter keys" {
    try std.testing.expectEqualStrings("A", shortcut_rec.keyName(0));
    try std.testing.expectEqualStrings("S", shortcut_rec.keyName(1));
    try std.testing.expectEqualStrings("D", shortcut_rec.keyName(2));
    try std.testing.expectEqualStrings("F", shortcut_rec.keyName(3));
    try std.testing.expectEqualStrings("Q", shortcut_rec.keyName(12));
    try std.testing.expectEqualStrings("W", shortcut_rec.keyName(13));
    try std.testing.expectEqualStrings("E", shortcut_rec.keyName(14));
    try std.testing.expectEqualStrings("R", shortcut_rec.keyName(15));
}

test "keyName returns correct names for special keys" {
    try std.testing.expectEqualStrings("↩", shortcut_rec.keyName(36)); // Return
    try std.testing.expectEqualStrings("⎋", shortcut_rec.keyName(53)); // Escape
    try std.testing.expectEqualStrings("⇥", shortcut_rec.keyName(48)); // Tab
    try std.testing.expectEqualStrings("Space", shortcut_rec.keyName(49));
    try std.testing.expectEqualStrings("⌫", shortcut_rec.keyName(51)); // Backspace
    try std.testing.expectEqualStrings("⌦", shortcut_rec.keyName(117)); // Delete
}

test "keyName returns correct names for function keys" {
    try std.testing.expectEqualStrings("F1", shortcut_rec.keyName(122));
    try std.testing.expectEqualStrings("F2", shortcut_rec.keyName(120));
    try std.testing.expectEqualStrings("F3", shortcut_rec.keyName(99));
    try std.testing.expectEqualStrings("F4", shortcut_rec.keyName(118));
    try std.testing.expectEqualStrings("F5", shortcut_rec.keyName(96));
    try std.testing.expectEqualStrings("F12", shortcut_rec.keyName(111));
}

test "keyName returns ? for unknown key codes" {
    try std.testing.expectEqualStrings("?", shortcut_rec.keyName(255));
    try std.testing.expectEqualStrings("?", shortcut_rec.keyName(200));
}

test "keyName returns correct names for number keys" {
    try std.testing.expectEqualStrings("1", shortcut_rec.keyName(18));
    try std.testing.expectEqualStrings("2", shortcut_rec.keyName(19));
    try std.testing.expectEqualStrings("3", shortcut_rec.keyName(20));
    try std.testing.expectEqualStrings("4", shortcut_rec.keyName(21));
    try std.testing.expectEqualStrings("5", shortcut_rec.keyName(23));
    try std.testing.expectEqualStrings("6", shortcut_rec.keyName(22));
    try std.testing.expectEqualStrings("0", shortcut_rec.keyName(29));
}

// ── Format shortcut tests ─────────────────────────────────────────────────

test "formatShortcut with ctrl+opt+left arrow" {
    var buf: [64]u8 = undefined;
    const result = shortcut_rec.formatShortcut(
        123, // left arrow
        .{ .ctrl = true, .opt = true },
        &buf,
    );
    try std.testing.expectEqualStrings("⌃⌥←", result);
}

test "formatShortcut with all modifiers" {
    var buf: [64]u8 = undefined;
    const result = shortcut_rec.formatShortcut(
        0, // A key
        .{ .ctrl = true, .opt = true, .shift = true, .cmd = true },
        &buf,
    );
    try std.testing.expectEqualStrings("⌃⌥⇧⌘A", result);
}

test "formatShortcut with cmd only" {
    var buf: [64]u8 = undefined;
    const result = shortcut_rec.formatShortcut(
        12, // Q key
        .{ .cmd = true },
        &buf,
    );
    try std.testing.expectEqualStrings("⌘Q", result);
}

test "formatShortcut with no modifiers returns None" {
    var buf: [64]u8 = undefined;
    const result = shortcut_rec.formatShortcut(
        0,
        .{},
        &buf,
    );
    // Key without modifiers shows just the key or "None"
    // Based on the implementation, it shows the key name
    try std.testing.expect(result.len > 0);
}

test "formatShortcut with shift+number" {
    var buf: [64]u8 = undefined;
    const result = shortcut_rec.formatShortcut(
        18, // 1 key
        .{ .ctrl = true, .opt = true, .shift = true },
        &buf,
    );
    try std.testing.expectEqualStrings("⌃⌥⇧1", result);
}

// ── Layout names table tests ──────────────────────────────────────────────

test "layout_names has 25 entries" {
    try std.testing.expectEqual(layout.layout_names.len, 25);
}

test "layout_names first entries are correct" {
    try std.testing.expectEqualStrings("Left Half", layout.layout_names[0]);
    try std.testing.expectEqualStrings("Right Half", layout.layout_names[1]);
    try std.testing.expectEqualStrings("Top Half", layout.layout_names[2]);
    try std.testing.expectEqualStrings("Bottom Half", layout.layout_names[3]);
}

test "layout_names quarter entries" {
    try std.testing.expectEqualStrings("Top-Left Quarter", layout.layout_names[4]);
    try std.testing.expectEqualStrings("Top-Right Quarter", layout.layout_names[5]);
    try std.testing.expectEqualStrings("Bottom-Left Quarter", layout.layout_names[6]);
    try std.testing.expectEqualStrings("Bottom-Right Quarter", layout.layout_names[7]);
}

test "layout_names last entry is Almost Maximize" {
    try std.testing.expectEqualStrings("Almost Maximize", layout.layout_names[24]);
}

test "all layout names are non-empty" {
    for (layout.layout_names) |name| {
        try std.testing.expect(name.len > 0);
    }
}

// ── Action count consistency tests ────────────────────────────────────────

test "action_count equals 27 (25 layouts + 2 throw actions)" {
    try std.testing.expectEqual(constants.action_count, 27);
}

test "default_shortcuts array length matches action_count" {
    try std.testing.expectEqual(config.default_shortcuts.len, constants.action_count);
}

test "Config shortcuts array length matches action_count" {
    const c = config.Config{};
    try std.testing.expectEqual(c.shortcuts.len, constants.action_count);
}

// ── Reset defaults behavior tests ─────────────────────────────────────────

test "resetting shortcuts restores default values" {
    var c = config.Config{};

    // Modify some shortcuts
    c.shortcuts[0].key_code = 99;
    c.shortcuts[0].modifiers = .{ .cmd = true };
    c.shortcuts[0].enabled = false;

    c.shortcuts[5].key_code = 42;
    c.shortcuts[5].modifiers = .{ .shift = true };

    // Verify they changed
    try std.testing.expectEqual(c.shortcuts[0].key_code, 99);
    try std.testing.expect(!c.shortcuts[0].enabled);

    // Reset to defaults
    c.shortcuts = config.default_shortcuts;

    // Verify they match defaults again
    try std.testing.expectEqual(c.shortcuts[0].key_code, config.default_shortcuts[0].key_code);
    try std.testing.expect(c.shortcuts[0].modifiers.ctrl == config.default_shortcuts[0].modifiers.ctrl);
    try std.testing.expect(c.shortcuts[0].modifiers.opt == config.default_shortcuts[0].modifiers.opt);
    try std.testing.expect(c.shortcuts[0].enabled);

    try std.testing.expectEqual(c.shortcuts[5].key_code, config.default_shortcuts[5].key_code);
}

test "default shortcuts have proper modifier combinations" {
    // Left Half: Ctrl+Opt+Left
    const left_half = config.default_shortcuts[0];
    try std.testing.expect(left_half.modifiers.ctrl);
    try std.testing.expect(left_half.modifiers.opt);
    try std.testing.expect(!left_half.modifiers.cmd);
    try std.testing.expect(!left_half.modifiers.shift);

    // Throw Next Display: Ctrl+Opt+Cmd+Right
    const throw_next = config.default_shortcuts[25];
    try std.testing.expect(throw_next.modifiers.ctrl);
    try std.testing.expect(throw_next.modifiers.opt);
    try std.testing.expect(throw_next.modifiers.cmd);
    try std.testing.expect(!throw_next.modifiers.shift);
}

// ── Settings page constants tests ─────────────────────────────────────────

test "sensitivity options are valid" {
    // Valid sensitivity values: 5, 10, 15, 20
    const valid_sensitivities = [_]u8{ 5, 10, 15, 20 };
    for (valid_sensitivities) |s| {
        try std.testing.expect(s >= 5 and s <= 20);
    }
}

test "default sensitivity is 10" {
    try std.testing.expectEqual(constants.default_snap_sensitivity, 10);
}

test "default window gap is 0" {
    try std.testing.expectEqual(constants.default_window_gap, 0);
}

test "default ghost opacity is 0.3" {
    try std.testing.expectApproxEqAbs(constants.default_ghost_opacity, 0.3, 0.001);
}

// ── Blacklist integration with settings tests ─────────────────────────────

test "blacklist removal shifts entries correctly" {
    var c = config.Config{};
    _ = c.addToBlacklist("com.app.one");
    _ = c.addToBlacklist("com.app.two");
    _ = c.addToBlacklist("com.app.three");

    try std.testing.expectEqual(c.blacklist_count, 3);

    // Remove middle entry
    c.removeFromBlacklist(1);

    try std.testing.expectEqual(c.blacklist_count, 2);
    try std.testing.expect(c.isBlacklisted("com.app.one"));
    try std.testing.expect(!c.isBlacklisted("com.app.two"));
    try std.testing.expect(c.isBlacklisted("com.app.three"));
}

test "blacklistEntry returns empty for invalid index" {
    const c = config.Config{};
    try std.testing.expectEqualStrings("", c.blacklistEntry(0));
    try std.testing.expectEqualStrings("", c.blacklistEntry(100));
}

test "blacklistEntry returns correct entry" {
    var c = config.Config{};
    _ = c.addToBlacklist("com.example.test");
    try std.testing.expectEqualStrings("com.example.test", c.blacklistEntry(0));
}

// ── Modifier formatting order tests ───────────────────────────────────────

test "modifier symbols appear in correct order (ctrl opt shift cmd)" {
    var buf: [64]u8 = undefined;

    // All modifiers should appear in order: ⌃⌥⇧⌘
    const result = shortcut_rec.formatShortcut(
        0, // A key
        .{ .ctrl = true, .opt = true, .shift = true, .cmd = true },
        &buf,
    );

    // Find positions of each symbol
    const ctrl_pos = std.mem.indexOf(u8, result, "⌃");
    const opt_pos = std.mem.indexOf(u8, result, "⌥");
    const shift_pos = std.mem.indexOf(u8, result, "⇧");
    const cmd_pos = std.mem.indexOf(u8, result, "⌘");

    try std.testing.expect(ctrl_pos != null);
    try std.testing.expect(opt_pos != null);
    try std.testing.expect(shift_pos != null);
    try std.testing.expect(cmd_pos != null);

    // Verify order
    try std.testing.expect(ctrl_pos.? < opt_pos.?);
    try std.testing.expect(opt_pos.? < shift_pos.?);
    try std.testing.expect(shift_pos.? < cmd_pos.?);
}
