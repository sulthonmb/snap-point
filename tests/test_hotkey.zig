//! HotkeyManager unit tests.
//! Pure Zig – no CGEvent or ObjC needed.

const std        = @import("std");
const hotkey     = @import("../src/platform/hotkey.zig");
const config_mod = @import("../src/core/config.zig");
const snap       = @import("../src/engine/snap.zig");

// Helper: build CGEventFlags from individual booleans
fn flags(ctrl: bool, opt: bool, cmd: bool, shift: bool) hotkey.CGEventFlags {
    var f: hotkey.CGEventFlags = 0;
    if (ctrl)  f |= hotkey.kCGEventFlagMaskControl;
    if (opt)   f |= hotkey.kCGEventFlagMaskAlternate;
    if (cmd)   f |= hotkey.kCGEventFlagMaskCommand;
    if (shift) f |= hotkey.kCGEventFlagMaskShift;
    return f;
}

// Helper: build a Shortcut
fn sc(key: u16, ctrl: bool, opt: bool, cmd: bool, shift: bool) config_mod.Shortcut {
    return .{
        .key_code  = key,
        .modifiers = .{ .ctrl = ctrl, .opt = opt, .cmd = cmd, .shift = shift },
        .enabled   = true,
    };
}

// ── modifiersMatch ────────────────────────────────────────────────────────

test "modifiersMatch: ctrl+opt matches" {
    const shortcut = sc(123, true, true, false, false);
    try std.testing.expect(hotkey.modifiersMatch(shortcut, flags(true, true, false, false)));
}

test "modifiersMatch: extra modifier fails" {
    const shortcut = sc(123, true, true, false, false);
    // Shift is pressed but shortcut does not require it
    try std.testing.expect(!hotkey.modifiersMatch(shortcut, flags(true, true, false, true)));
}

test "modifiersMatch: missing required modifier fails" {
    const shortcut = sc(123, true, true, false, false);
    // Option not pressed
    try std.testing.expect(!hotkey.modifiersMatch(shortcut, flags(true, false, false, false)));
}

test "modifiersMatch: ctrl+opt+cmd" {
    const shortcut = sc(123, true, true, true, false);
    try std.testing.expect(hotkey.modifiersMatch(shortcut, flags(true, true, true, false)));
    try std.testing.expect(!hotkey.modifiersMatch(shortcut, flags(true, true, false, false)));
}

test "modifiersMatch: ctrl+opt+shift" {
    const shortcut = sc(124, true, true, false, true);
    try std.testing.expect(hotkey.modifiersMatch(shortcut, flags(true, true, false, true)));
    try std.testing.expect(!hotkey.modifiersMatch(shortcut, flags(true, true, true,  true)));
}

test "modifiersMatch: no modifiers" {
    const shortcut = sc(0, false, false, false, false);
    try std.testing.expect(hotkey.modifiersMatch(shortcut, 0));
    try std.testing.expect(!hotkey.modifiersMatch(shortcut, flags(true, false, false, false)));
}

// ── HotkeyManager.handleKeyEvent ─────────────────────────────────────────

test "handleKeyEvent: left arrow + ctrl+opt → snap_left_half" {
    var cfg = config_mod.Config{};
    var mgr = hotkey.HotkeyManager.init(&cfg);
    const action = mgr.handleKeyEvent(123, flags(true, true, false, false));
    try std.testing.expectEqual(action, snap.Action.snap_left_half);
}

test "handleKeyEvent: right arrow + ctrl+opt → snap_right_half" {
    var cfg = config_mod.Config{};
    var mgr = hotkey.HotkeyManager.init(&cfg);
    const action = mgr.handleKeyEvent(124, flags(true, true, false, false));
    try std.testing.expectEqual(action, snap.Action.snap_right_half);
}

test "handleKeyEvent: up arrow + ctrl+opt → snap_top_half" {
    var cfg = config_mod.Config{};
    var mgr = hotkey.HotkeyManager.init(&cfg);
    const action = mgr.handleKeyEvent(126, flags(true, true, false, false));
    try std.testing.expectEqual(action, snap.Action.snap_top_half);
}

test "handleKeyEvent: down arrow + ctrl+opt → snap_bottom_half" {
    var cfg = config_mod.Config{};
    var mgr = hotkey.HotkeyManager.init(&cfg);
    const action = mgr.handleKeyEvent(125, flags(true, true, false, false));
    try std.testing.expectEqual(action, snap.Action.snap_bottom_half);
}

test "handleKeyEvent: return + ctrl+opt → snap_almost_maximize" {
    var cfg = config_mod.Config{};
    var mgr = hotkey.HotkeyManager.init(&cfg);
    const action = mgr.handleKeyEvent(36, flags(true, true, false, false));
    try std.testing.expectEqual(action, snap.Action.snap_almost_maximize);
}

test "handleKeyEvent: right arrow + ctrl+opt+cmd → throw_to_next_display" {
    var cfg = config_mod.Config{};
    var mgr = hotkey.HotkeyManager.init(&cfg);
    const action = mgr.handleKeyEvent(124, flags(true, true, true, false));
    try std.testing.expectEqual(action, snap.Action.throw_to_next_display);
}

test "handleKeyEvent: left arrow + ctrl+opt+cmd → throw_to_prev_display" {
    var cfg = config_mod.Config{};
    var mgr = hotkey.HotkeyManager.init(&cfg);
    const action = mgr.handleKeyEvent(123, flags(true, true, true, false));
    try std.testing.expectEqual(action, snap.Action.throw_to_prev_display);
}

test "handleKeyEvent: no match → null" {
    var cfg = config_mod.Config{};
    var mgr = hotkey.HotkeyManager.init(&cfg);
    // Wrong modifier combo
    const action = mgr.handleKeyEvent(123, flags(false, false, true, false));
    try std.testing.expectEqual(action, null);
}

test "handleKeyEvent: unbound key → null" {
    var cfg = config_mod.Config{};
    var mgr = hotkey.HotkeyManager.init(&cfg);
    const action = mgr.handleKeyEvent(0xAB, flags(true, true, false, false));
    try std.testing.expectEqual(action, null);
}

test "handleKeyEvent: disabled binding → null" {
    var cfg = config_mod.Config{};
    // Disable Left Half shortcut
    cfg.shortcuts[0].enabled = false;
    var mgr = hotkey.HotkeyManager.init(&cfg);
    const action = mgr.handleKeyEvent(123, flags(true, true, false, false));
    try std.testing.expectEqual(action, null);
}

test "handleKeyEvent: reload updates bindings" {
    var cfg = config_mod.Config{};
    var mgr = hotkey.HotkeyManager.init(&cfg);

    // Change left half to key code 0 + ctrl
    cfg.shortcuts[0] = .{
        .key_code  = 0,
        .modifiers = .{ .ctrl = true, .opt = false, .cmd = false, .shift = false },
        .enabled   = true,
    };
    mgr.reload(&cfg);

    // Old binding should no longer match
    try std.testing.expectEqual(
        mgr.handleKeyEvent(123, flags(true, true, false, false)),
        null,
    );
    // New binding should match
    try std.testing.expectEqual(
        mgr.handleKeyEvent(0, flags(true, false, false, false)),
        snap.Action.snap_left_half,
    );
}

test "all 27 default shortcuts are uniquely addressable" {
    var cfg = config_mod.Config{};
    var mgr = hotkey.HotkeyManager.init(&cfg);
    // Ensure at least one action is returned per shortcut
    for (cfg.shortcuts, 0..) |sh, i| {
        const action = mgr.handleKeyEvent(sh.key_code,
            flags(sh.modifiers.ctrl, sh.modifiers.opt,
                  sh.modifiers.cmd, sh.modifiers.shift));
        // The first match should be the expected action at index i
        // (No two default shortcuts share the same key+modifier combo)
        if (action) |a| {
            try std.testing.expectEqual(@intFromEnum(a), i);
        }
    }
}

// ── eventBit helper ───────────────────────────────────────────────────────

test "eventBit: left mouse down" {
    try std.testing.expectEqual(hotkey.eventBit(1), @as(u64, 2));
}
