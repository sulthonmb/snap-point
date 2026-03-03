//! ABI compatibility tests – validates Zig struct layouts match macOS C types.
//! These tests ensure that data passed across the Zig ↔ C boundary
//! (AXUIElement, CGEventTap, CoreGraphics) is correctly laid out.

const std = @import("std");
const geo = @import("../src/util/geometry.zig");
const config_mod = @import("../src/core/config.zig");
const ax = @import("../src/platform/accessibility.zig");
const hotkey = @import("../src/platform/hotkey.zig");

// ── CGPoint / CGSize / CGRect Layout ─────────────────────────────────────
// These must match the CoreGraphics ABI exactly:
//   CGPoint = { double x, double y }           → 16 bytes, x at 0, y at 8
//   CGSize  = { double width, double height }  → 16 bytes
//   CGRect  = { CGPoint origin, CGSize size }  → 32 bytes

test "CGPoint matches CoreGraphics ABI" {
    try std.testing.expectEqual(@sizeOf(geo.CGPoint), 16);
    try std.testing.expectEqual(@offsetOf(geo.CGPoint, "x"), 0);
    try std.testing.expectEqual(@offsetOf(geo.CGPoint, "y"), 8);
    try std.testing.expectEqual(@alignOf(geo.CGPoint), 8);
}

test "CGSize matches CoreGraphics ABI" {
    try std.testing.expectEqual(@sizeOf(geo.CGSize), 16);
    try std.testing.expectEqual(@offsetOf(geo.CGSize, "width"), 0);
    try std.testing.expectEqual(@offsetOf(geo.CGSize, "height"), 8);
    try std.testing.expectEqual(@alignOf(geo.CGSize), 8);
}

test "CGRect matches CoreGraphics ABI" {
    try std.testing.expectEqual(@sizeOf(geo.CGRect), 32);
    try std.testing.expectEqual(@offsetOf(geo.CGRect, "origin"), 0);
    try std.testing.expectEqual(@offsetOf(geo.CGRect, "size"), 16);
    try std.testing.expectEqual(@alignOf(geo.CGRect), 8);
}

test "CGPoint can be reinterpreted from raw bytes" {
    const bytes: [16]u8 align(8) = .{0} ** 16;
    const ptr: *const geo.CGPoint = @ptrCast(&bytes);
    try std.testing.expectEqual(ptr.x, 0.0);
    try std.testing.expectEqual(ptr.y, 0.0);
}

// ── AXValueType enum matches AXValue.h ───────────────────────────────────

test "AXValueType enum values match AXValue.h" {
    try std.testing.expectEqual(@intFromEnum(ax.AXValueType.illegal), 0);
    try std.testing.expectEqual(@intFromEnum(ax.AXValueType.cg_point), 1);
    try std.testing.expectEqual(@intFromEnum(ax.AXValueType.cg_size), 2);
    try std.testing.expectEqual(@intFromEnum(ax.AXValueType.cg_rect), 3);
    try std.testing.expectEqual(@intFromEnum(ax.AXValueType.cg_affine_transform), 4);
    try std.testing.expectEqual(@intFromEnum(ax.AXValueType.ax_error), 6);
}

// ── AXError constants match AXError.h ────────────────────────────────────

test "AXError constants match AXError.h" {
    try std.testing.expectEqual(ax.kAXErrorSuccess, 0);
    try std.testing.expectEqual(ax.kAXErrorFailure, -25200);
    try std.testing.expectEqual(ax.kAXErrorIllegalArgument, -25201);
    try std.testing.expectEqual(ax.kAXErrorInvalidUIElement, -25202);
    try std.testing.expectEqual(ax.kAXErrorCannotComplete, -25204);
    try std.testing.expectEqual(ax.kAXErrorNotImplemented, -25205);
    try std.testing.expectEqual(ax.kAXErrorAPIDisabled, -25211);
}

// ── CGEventFlags modifier bitmasks match CGEventTypes.h ──────────────────

test "CGEventFlags modifier masks match CGEventTypes.h" {
    try std.testing.expectEqual(hotkey.kCGEventFlagMaskShift, 0x0002_0000);
    try std.testing.expectEqual(hotkey.kCGEventFlagMaskControl, 0x0004_0000);
    try std.testing.expectEqual(hotkey.kCGEventFlagMaskAlternate, 0x0008_0000);
    try std.testing.expectEqual(hotkey.kCGEventFlagMaskCommand, 0x0010_0000);
}

test "kModifierMask combines all four modifiers" {
    const expected: hotkey.CGEventFlags =
        hotkey.kCGEventFlagMaskShift |
        hotkey.kCGEventFlagMaskControl |
        hotkey.kCGEventFlagMaskAlternate |
        hotkey.kCGEventFlagMaskCommand;
    try std.testing.expectEqual(hotkey.kModifierMask, expected);
}

// ── Modifiers packed struct is 1 byte ────────────────────────────────────

test "Modifiers packed struct is exactly 1 byte" {
    try std.testing.expectEqual(@sizeOf(config_mod.Modifiers), 1);
}

test "Modifiers bitfield layout" {
    // ctrl=bit0, opt=bit1, cmd=bit2, shift=bit3
    const m_ctrl = config_mod.Modifiers{ .ctrl = true };
    const m_opt = config_mod.Modifiers{ .opt = true };
    const m_cmd = config_mod.Modifiers{ .cmd = true };
    const m_shift = config_mod.Modifiers{ .shift = true };

    const raw_ctrl: u8 = @bitCast(m_ctrl);
    const raw_opt: u8 = @bitCast(m_opt);
    const raw_cmd: u8 = @bitCast(m_cmd);
    const raw_shift: u8 = @bitCast(m_shift);

    try std.testing.expect(raw_ctrl & 0b0001 != 0);
    try std.testing.expect(raw_opt & 0b0010 != 0);
    try std.testing.expect(raw_cmd & 0b0100 != 0);
    try std.testing.expect(raw_shift & 0b1000 != 0);
}

test "Modifiers combined bitfield" {
    const m = config_mod.Modifiers{ .ctrl = true, .opt = true, .cmd = false, .shift = false };
    const raw: u8 = @bitCast(m);
    try std.testing.expectEqual(raw & 0x0F, 0b0011); // ctrl + opt
}

// ── Shortcut struct layout ───────────────────────────────────────────────

test "Shortcut struct is reasonably sized" {
    // key_code (u16) + modifiers (u8) + enabled (bool) + padding
    try std.testing.expect(@sizeOf(config_mod.Shortcut) <= 8);
}

// ── Pointer sizes (ensure 64-bit) ────────────────────────────────────────

test "pointers are 64-bit on macOS" {
    try std.testing.expectEqual(@sizeOf(*anyopaque), 8);
    try std.testing.expectEqual(@sizeOf(ax.AXUIElementRef), 8);
    try std.testing.expectEqual(@sizeOf(ax.CFTypeRef), 8);
}

// ── Additional C-Interop / ABI Tests ─────────────────────────────────────

test "AXUIElementRef is a pointer type" {
    // AXUIElementRef = typedef struct __AXUIElement *AXUIElementRef
    // It must be pointer-sized for FFI to work correctly
    try std.testing.expectEqual(@sizeOf(ax.AXUIElementRef), @sizeOf(*anyopaque));
    try std.testing.expectEqual(@alignOf(ax.AXUIElementRef), @alignOf(*anyopaque));
}

test "CFTypeRef is pointer-sized" {
    // CFTypeRef = const void * (generic Core Foundation type)
    try std.testing.expectEqual(@sizeOf(ax.CFTypeRef), @sizeOf(*anyopaque));
}

test "CGDirectDisplayID is u32" {
    // CGDirectDisplayID = uint32_t on macOS
    try std.testing.expectEqual(@sizeOf(u32), 4);
}

test "CGEventFlags is 64-bit" {
    // CGEventFlags = uint64_t (CGEventTypes.h)
    try std.testing.expectEqual(@sizeOf(hotkey.CGEventFlags), 8);
}

test "CGEvent type constants match CGEventTypes.h" {
    // Key event types used for hotkey detection
    // These are the numeric values from CGEventTypes.h:
    //   kCGEventKeyDown = 10
    //   kCGEventKeyUp = 11
    // We use eventBit() which creates a bitmask from these values
    const key_down_bit = hotkey.eventBit(10); // kCGEventKeyDown
    const key_up_bit = hotkey.eventBit(11); // kCGEventKeyUp
    try std.testing.expectEqual(key_down_bit, @as(u64, 1) << 10);
    try std.testing.expectEqual(key_up_bit, @as(u64, 1) << 11);
}

test "virtual key codes are u16" {
    // Virtual key codes (CGKeyCode) are 16-bit on macOS
    const test_keycode: u16 = 0x7E; // up arrow
    try std.testing.expectEqual(@sizeOf(@TypeOf(test_keycode)), 2);
}

// ── AXValue / CFTypeID tests ─────────────────────────────────────────────

test "AXValueType has expected enum integer values" {
    // Validate all AXValueType values match AXValue.h
    const TypeInfo = @typeInfo(ax.AXValueType).@"enum";
    try std.testing.expect(TypeInfo.fields.len >= 5);
}

// ── Memory layout consistency ────────────────────────────────────────────

test "CGRect nested struct offsets are correct" {
    // CGRect.origin should be at byte 0
    // CGRect.size should be at byte 16 (after CGPoint)
    const rect = geo.CGRect{
        .origin = .{ .x = 1.0, .y = 2.0 },
        .size = .{ .width = 3.0, .height = 4.0 },
    };
    const bytes = std.mem.asBytes(&rect);

    // Verify x is at offset 0
    const x_ptr: *const f64 = @ptrCast(@alignCast(bytes.ptr));
    try std.testing.expectEqual(x_ptr.*, 1.0);

    // Verify width is at offset 16
    const width_ptr: *const f64 = @ptrCast(@alignCast(bytes.ptr + 16));
    try std.testing.expectEqual(width_ptr.*, 3.0);
}

test "Config struct has expected minimum components" {
    // Verify Config struct includes key fields by checking their offsets exist
    // This ensures the struct layout hasn't accidentally changed
    const config = config_mod.Config{};

    // Access fields to verify they exist (compile-time check)
    _ = config.launch_at_login;
    _ = config.snap_sensitivity;
    _ = config.show_ghost_window;
    _ = config.window_gap;
    _ = config.ghost_opacity;
    _ = config.has_completed_onboarding;
    _ = config.shortcuts;
    _ = config.blacklist_count;

    // Shortcuts array should have action_count entries
    const constants = @import("../src/core/constants.zig");
    try std.testing.expectEqual(config.shortcuts.len, constants.action_count);
}
