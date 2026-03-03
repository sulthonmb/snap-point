//! Shortcut recorder: formats shortcuts for display and captures new ones.
//!
//! A lightweight NSPanel ("SnapShortcutCaptureView" ObjC class) floats
//! above the settings window, shows "Press shortcut…", and captures the
//! next key+modifier combo. ESC cancels; any key WITH at least one
//! modifier (⌃/⌥/⌘/⇧) sets the shortcut for the action being edited.
//!
//! Usage:
//!   ShortcutCapturePanel.show(parent_window, action_idx);
//! After capture the panel closes itself and the settings window
//! subscribes to "SnapShortcutChanged" to reload its table.

const std = @import("std");
const objc = @import("objc");
const bridge = @import("../objc/bridge.zig");
const log = @import("../core/log.zig");
const state = @import("../core/state.zig");
const config_mod = @import("../core/config.zig");

// ── Key name table ────────────────────────────────────────────────────────

/// Human-readable name for a virtual key code.
/// Arrow / special keys get Unicode symbols; letters stay as-is.
pub fn keyName(code: u16) []const u8 {
    return switch (code) {
        0 => "A",
        1 => "S",
        2 => "D",
        3 => "F",
        4 => "H",
        5 => "G",
        6 => "Z",
        7 => "X",
        8 => "C",
        9 => "V",
        11 => "B",
        12 => "Q",
        13 => "W",
        14 => "E",
        15 => "R",
        16 => "Y",
        17 => "T",
        18 => "1",
        19 => "2",
        20 => "3",
        21 => "4",
        23 => "5",
        22 => "6",
        26 => "7",
        28 => "8",
        25 => "9",
        29 => "0",
        27 => "-",
        24 => "=",
        33 => "[",
        30 => "]",
        42 => "\\",
        41 => ";",
        39 => "'",
        43 => ",",
        47 => ".",
        44 => "/",
        32 => "U",
        34 => "I",
        31 => "O",
        35 => "P",
        37 => "L",
        40 => "K",
        38 => "J",
        45 => "N",
        46 => "M",
        36 => "↩",
        53 => "⎋",
        48 => "⇥",
        49 => "Space",
        51 => "⌫",
        117 => "⌦",
        123 => "←",
        124 => "→",
        125 => "↓",
        126 => "↑",
        115 => "Home",
        119 => "End",
        116 => "PgUp",
        121 => "PgDn",
        122 => "F1",
        120 => "F2",
        99 => "F3",
        118 => "F4",
        96 => "F5",
        97 => "F6",
        98 => "F7",
        100 => "F8",
        101 => "F9",
        109 => "F10",
        103 => "F11",
        111 => "F12",
        else => "?",
    };
}

/// Format a shortcut into a short symbol string like "⌃⌥←".
/// Writes into `buf` (at least 64 bytes recommended) and returns a slice.
pub fn formatShortcut(
    key_code: u16,
    modifiers: config_mod.Modifiers,
    buf: []u8,
) []const u8 {
    var idx: usize = 0;

    // Modifier symbols in standard mac order: ⌃ ⌥ ⇧ ⌘
    const symbols = [4][]const u8{ "⌃", "⌥", "⇧", "⌘" }; // UTF-8 3-byte each
    const flags = [4]bool{ modifiers.ctrl, modifiers.opt, modifiers.shift, modifiers.cmd };

    for (symbols, flags) |sym, flag| {
        if (!flag) continue;
        if (idx + sym.len >= buf.len) break;
        @memcpy(buf[idx .. idx + sym.len], sym);
        idx += sym.len;
    }

    const key_str = keyName(key_code);
    if (idx + key_str.len < buf.len) {
        @memcpy(buf[idx .. idx + key_str.len], key_str);
        idx += key_str.len;
    }

    if (idx == 0) {
        const none = "None";
        @memcpy(buf[0..none.len], none);
        return buf[0..none.len];
    }
    return buf[0..idx];
}

// ── Global recording state ────────────────────────────────────────────────

/// Action index currently being recorded (-1 = not recording).
pub var g_recording_action: i32 = -1;
/// Panel NSWindow while recording; null otherwise.
var g_capture_window: ?objc.Object = null;
/// Label inside the panel for displaying status.
var g_capture_label: ?objc.Object = null;

var g_classes_registered = false;

// ── ObjC class registration ───────────────────────────────────────────────

/// Register "SnapShortcutCaptureView" (NSView subclass) once.
pub fn registerClasses() void {
    if (g_classes_registered) return;
    g_classes_registered = true;

    const NSView = objc.getClass("NSView") orelse
        @panic("NSView not found");

    const cls = objc.allocateClassPair(NSView, "SnapShortcutCaptureView") orelse return;
    _ = cls.addMethod("acceptsFirstResponder", captureAcceptsFirstResponder);
    _ = cls.addMethod("keyDown:", captureKeyDown);
    _ = cls.addMethod("drawRect:", captureDrawRect);
    objc.registerClassPair(cls);
}

// ── Panel show / hide ─────────────────────────────────────────────────────

/// Show the capture panel relative to `parent_window`, recording for `action_idx`.
pub fn show(parent_window: objc.Object, action_idx: i32) void {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    registerClasses();
    g_recording_action = action_idx;

    // ── Create content view ──────────────────────────────────────────
    const CaptureViewClass = bridge.getClass("SnapShortcutCaptureView");
    const panel_size = geo_CGRect(.{ .x = 0, .y = 0 }, .{ .width = 340, .height = 130 });
    const content_view = CaptureViewClass.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{panel_size});
    content_view.msgSend(void, objc.sel("setWantsLayer:"), .{true});

    // Dark rounded layer
    const layer = content_view.msgSend(objc.Object, objc.sel("layer"), .{});
    if (layer.value != null) {
        // Background color: NSColor.controlBackgroundColor (adapts to dark/light)
        const NSColor = bridge.getClass("NSColor");
        const bg = NSColor.msgSend(objc.Object, objc.sel("windowBackgroundColor"), .{});
        const cg_color = bg.msgSend(objc.Object, objc.sel("CGColor"), .{});
        layer.msgSend(void, objc.sel("setBackgroundColor:"), .{cg_color});
        layer.msgSend(void, objc.sel("setCornerRadius:"), .{@as(f64, 12.0)});
        layer.msgSend(void, objc.sel("setMasksToBounds:"), .{true});
    }

    // ── Title label ──────────────────────────────────────────────────
    const NSTextField = bridge.getClass("NSTextField");
    const lbl = NSTextField.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{geo_CGRect(.{ .x = 20, .y = 40 }, .{ .width = 300, .height = 50 })});
    lbl.msgSend(void, objc.sel("setStringValue:"), .{bridge.nsString("Press shortcut\u{2026}")});
    lbl.msgSend(void, objc.sel("setEditable:"), .{false});
    lbl.msgSend(void, objc.sel("setBordered:"), .{false});
    lbl.msgSend(void, objc.sel("setDrawsBackground:"), .{false});
    lbl.msgSend(void, objc.sel("setAlignment:"), .{@as(c_ulong, 1)}); // NSTextAlignmentCenter=1
    setFontSize(lbl, 18.0);
    content_view.msgSend(void, objc.sel("addSubview:"), .{lbl});

    // ── Small hint ───────────────────────────────────────────────────
    const hint_lbl = NSTextField.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{geo_CGRect(.{ .x = 20, .y = 16 }, .{ .width = 300, .height = 20 })});
    hint_lbl.msgSend(void, objc.sel("setStringValue:"), .{bridge.nsString("ESC to cancel  \u{2014}  at least one modifier required")});
    hint_lbl.msgSend(void, objc.sel("setEditable:"), .{false});
    hint_lbl.msgSend(void, objc.sel("setBordered:"), .{false});
    hint_lbl.msgSend(void, objc.sel("setDrawsBackground:"), .{false});
    hint_lbl.msgSend(void, objc.sel("setAlignment:"), .{@as(c_ulong, 1)});
    setFontSize(hint_lbl, 11.0);
    const NSColor2 = bridge.getClass("NSColor");
    const gray = NSColor2.msgSend(objc.Object, objc.sel("secondaryLabelColor"), .{});
    hint_lbl.msgSend(void, objc.sel("setTextColor:"), .{gray});
    content_view.msgSend(void, objc.sel("addSubview:"), .{hint_lbl});

    g_capture_label = lbl;

    // ── NSPanel ──────────────────────────────────────────────────────
    const NSPanel = bridge.getClass("NSPanel");
    // NSWindowStyleMaskTitled=1 | HUDWindow=8192 | NonactivatingPanel=128
    const style_mask: c_ulong = 1 | 128;
    const win = NSPanel.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(
        objc.Object,
        objc.sel("initWithContentRect:styleMask:backing:defer:"),
        .{ panel_size, style_mask, @as(c_ulong, 2), false },
    );
    win.msgSend(void, objc.sel("setContentView:"), .{content_view});
    win.msgSend(void, objc.sel("setOpaque:"), .{false});
    win.msgSend(void, objc.sel("setHasShadow:"), .{true});
    win.msgSend(void, objc.sel("setReleasedWhenClosed:"), .{false});
    win.msgSend(void, objc.sel("setLevel:"), .{@as(c_int, 3)}); // NSModalPanelWindowLevel

    _ = win.msgSend(objc.Object, objc.sel("retain"), .{});
    g_capture_window = win;

    // Center relative to parent
    const parent_frame = parent_window.msgSend(geo_CGRectType, objc.sel("frame"), .{});
    const px = parent_frame.origin.x + (parent_frame.size.width - 340.0) / 2.0;
    const py = parent_frame.origin.y + (parent_frame.size.height - 130.0) / 2.0;
    win.msgSend(void, objc.sel("setFrameOrigin:"), .{CGPoint{ .x = px, .y = py }});

    // Make first responder to capture key events
    win.msgSend(void, objc.sel("setInitialFirstResponder:"), .{content_view});

    // Show and make key
    parent_window.msgSend(void, objc.sel("beginSheet:completionHandler:"), .{ win, @as(?*anyopaque, null) });

    // Fallback: orderFront if sheet failed
    win.msgSend(void, objc.sel("makeKeyAndOrderFront:"), .{win});
    _ = win.msgSend(bool, objc.sel("makeFirstResponder:"), .{content_view});
}

/// Close the capture panel without saving.
pub fn close() void {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    g_recording_action = -1;
    if (g_capture_window) |win| {
        win.msgSend(void, objc.sel("orderOut:"), .{win});
        win.msgSend(void, objc.sel("release"), .{});
        g_capture_window = null;
    }
    g_capture_label = null;
}

// ── ObjC method implementations ───────────────────────────────────────────

fn captureAcceptsFirstResponder(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
) callconv(.c) bool {
    _ = _self;
    _ = _cmd;
    return true;
}

fn captureKeyDown(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    event: objc.c.id,
) callconv(.c) void {
    _ = _self;
    _ = _cmd;

    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const ev = objc.Object{ .value = event };

    // key code & flags
    const key_code: u16 = @intCast(ev.msgSend(c_ushort, objc.sel("keyCode"), .{}));
    const flags: c_ulong = ev.msgSend(c_ulong, objc.sel("modifierFlags"), .{});

    // ESC → cancel
    if (key_code == 53) {
        log.debug("shortcut_recorder: capture cancelled", .{});
        close();
        // Post notification so settings window can clear 'recording' highlight
        postShortcutChangedNotification(-1);
        return;
    }

    // Extract modifiers from NSEventModifierFlags
    const ctrl = (flags & 0x040000) != 0;
    const opt = (flags & 0x080000) != 0;
    const cmd = (flags & 0x100000) != 0;
    const shift = (flags & 0x020000) != 0;
    const has_modifier = ctrl or opt or cmd or shift;

    if (!has_modifier) {
        // Require at least one modifier; flash the hint label
        if (g_capture_label) |lbl| {
            const NSColor = bridge.getClass("NSColor");
            const red = NSColor.msgSend(objc.Object, objc.sel("systemRedColor"), .{});
            lbl.msgSend(void, objc.sel("setStringValue:"), .{bridge.nsString("Modifier required (⌃, ⌥, ⌘, ⇧)")});
            lbl.msgSend(void, objc.sel("setTextColor:"), .{red});
        }
        return;
    }

    // Save the new shortcut
    const idx = g_recording_action;
    if (idx >= 0 and idx < @as(i32, @import("../core/constants.zig").action_count)) {
        const ui: usize = @intCast(idx);
        state.g.config.shortcuts[ui] = .{
            .key_code = key_code,
            .modifiers = .{ .ctrl = ctrl, .opt = opt, .cmd = cmd, .shift = shift },
            .enabled = true,
        };
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        config_mod.save(&state.g.config, gpa.allocator()) catch |e| {
            log.warn("shortcut_recorder: save failed: {any}", .{e});
        };
        log.info("shortcut_recorder: set action {} → key {} flags 0x{X}", .{ idx, key_code, flags });
    }

    close();
    postShortcutChangedNotification(idx);
}

fn captureDrawRect(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    _rect: objc.c.id,
) callconv(.c) void {
    _ = _self;
    _ = _cmd;
    _ = _rect;
    // Drawing is handled by the layer; nothing extra needed.
}

// ── Notification helper ───────────────────────────────────────────────────

fn postShortcutChangedNotification(action_idx: i32) void {
    const nc = bridge.getClass("NSNotificationCenter")
        .msgSend(objc.Object, objc.sel("defaultCenter"), .{});
    var buf: [64]u8 = undefined;
    const name = std.fmt.bufPrintZ(&buf, "SnapShortcutChanged", .{}) catch "SnapShortcutChanged";
    _ = action_idx;
    nc.msgSend(
        void,
        objc.sel("postNotificationName:object:"),
        .{ bridge.nsString(name), @as(objc.Object, .{ .value = null }) },
    );
}

fn setFontSize(view: objc.Object, size: f64) void {
    const NSFont = bridge.getClass("NSFont");
    const font = NSFont.msgSend(objc.Object, objc.sel("systemFontOfSize:"), .{size});
    view.msgSend(void, objc.sel("setFont:"), .{font});
}

// ── Tiny geometry helpers (avoid importing util/geometry to keep deps minimal) ──

const CGPoint = extern struct { x: f64, y: f64 };
const CGSize = extern struct { width: f64, height: f64 };
const geo_CGRectType = extern struct { origin: CGPoint, size: CGSize };

fn geo_CGRect(origin: CGPoint, size: CGSize) geo_CGRectType {
    return .{ .origin = origin, .size = size };
}
