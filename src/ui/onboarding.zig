//! Three-step onboarding modal (560×400, non-resizable).
//!
//! Step 1 – Welcome:    app hero text + "Continue →" button.
//! Step 2 – Permission: AX permission guide + "Open System Settings" button.
//!                      NSTimer polls AXIsProcessTrusted every 1 s;
//!                      advances automatically once granted.
//! Step 3 – Shortcuts:  Pick Compact / Custom shortcut preset + "Get Started".
//!
//! After "Get Started" the window sets has_completed_onboarding=true,
//! saves config, and hides itself.

const std = @import("std");
const objc = @import("objc");
const bridge = @import("../objc/bridge.zig");
const log = @import("../core/log.zig");
const state = @import("../core/state.zig");
const config_mod = @import("../core/config.zig");
const perm = @import("../platform/permission.zig");

// ── Geometry ──────────────────────────────────────────────────────────────

const WIN_W: f64 = 560;
const WIN_H: f64 = 400;

// ── Module-level globals ──────────────────────────────────────────────────

var g_window: ?objc.Object = null;
var g_steps: [3]?objc.Object = .{null} ** 3;
var g_current_step: usize = 0;
var g_poll_timer: ?objc.Object = null;
var g_permit_status: ?objc.Object = null; // label showing "Waiting…" or "✓ Granted"
var g_classes_reg = false;

// ── Public struct ─────────────────────────────────────────────────────────

pub const OnboardingWindow = struct {
    initialized: bool = false,

    /// Build the onboarding window.  Call once on main thread after
    /// NSApplication is initialised.
    pub fn init() OnboardingWindow {
        registerClasses();
        buildWindow();
        log.info("onboarding: initialised", .{});
        return .{ .initialized = true };
    }

    /// Show the onboarding window from step 1.
    pub fn show(self: *OnboardingWindow) void {
        if (!self.initialized) return;
        showStep(0);
        if (g_window) |win| {
            win.msgSend(void, objc.sel("makeKeyAndOrderFront:"), .{win});
            win.msgSend(void, objc.sel("center"), .{});
        }
    }

    /// Close the onboarding window (after completion or manual dismiss).
    pub fn close(self: *OnboardingWindow) void {
        if (!self.initialized) return;
        stopPollTimer();
        if (g_window) |win| win.msgSend(void, objc.sel("orderOut:"), .{win});
    }
};

// ── Window construction ────────────────────────────────────────────────────

fn buildWindow() void {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSWindow = bridge.getClass("NSWindow");
    // Titled (1) + Closable (2) – no resize
    const style: c_ulong = 1 | 2;
    const win_rect = cgRect(0, 0, WIN_W, WIN_H);

    const win = NSWindow.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithContentRect:styleMask:backing:defer:"), .{ win_rect, style, @as(c_ulong, 2), false });
    win.msgSend(void, objc.sel("setTitle:"), .{bridge.nsString("Welcome to SnapPoint")});
    win.msgSend(void, objc.sel("setReleasedWhenClosed:"), .{false});
    win.msgSend(void, objc.sel("center"), .{});

    // Window delegate so close button hides instead of destroying
    const WinDelCls = bridge.getClass("SnapOnboardingDelegate");
    const win_del = WinDelCls.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("init"), .{});
    _ = win_del.msgSend(objc.Object, objc.sel("retain"), .{});
    win.msgSend(void, objc.sel("setDelegate:"), .{win_del});

    _ = win.msgSend(objc.Object, objc.sel("retain"), .{});
    g_window = win;

    const cv = win.msgSend(objc.Object, objc.sel("contentView"), .{});
    const page_frame = cgRect(0, 0, WIN_W, WIN_H);

    g_steps[0] = buildStep1(cv, page_frame);
    g_steps[1] = buildStep2(cv, page_frame);
    g_steps[2] = buildStep3(cv, page_frame);

    // Start from step 0 hidden; show() will unhide and re-center
    for (g_steps) |maybe_pg| {
        if (maybe_pg) |pg| {
            pg.msgSend(void, objc.sel("setHidden:"), .{true});
        }
    }
}

// ── Step 1: Welcome ───────────────────────────────────────────────────────

fn buildStep1(parent: objc.Object, frame: CGRect) objc.Object {
    const NSView = bridge.getClass("NSView");
    const NSButton = bridge.getClass("NSButton");

    const pg = NSView.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{frame});
    _ = pg.msgSend(objc.Object, objc.sel("retain"), .{});
    parent.msgSend(void, objc.sel("addSubview:"), .{pg});

    // Large title
    _ = addLabel(pg, "Welcome to SnapPoint", 40, WIN_H - 100, 480, 40, 28.0, true);

    // Description
    _ = addLabel(pg, "Snap any window to a perfect layout with a single keyboard shortcut.", 40, WIN_H - 160, 480, 50, 14.0, false);

    _ = addLabel(pg, "Let\u{2019}s get you set up in two quick steps.", 40, WIN_H - 210, 480, 30, 14.0, false);

    // Continue button
    const ActCls = bridge.getClass("SnapOnboardingActionTarget");
    const act = ActCls.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("init"), .{});
    _ = act.msgSend(objc.Object, objc.sel("retain"), .{});

    const btn = NSButton.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{cgRect(WIN_W - 200, 30, 160, 36)});
    btn.msgSend(void, objc.sel("setTitle:"), .{bridge.nsString("Continue \u{2192}")});
    btn.msgSend(void, objc.sel("setBezelStyle:"), .{@as(c_ulong, 1)});
    btn.msgSend(void, objc.sel("setTag:"), .{@as(c_long, 0)}); // step 0 → advance
    btn.msgSend(void, objc.sel("setTarget:"), .{act});
    btn.msgSend(void, objc.sel("setAction:"), .{objc.sel("advance:")});

    btn.msgSend(void, objc.sel("setKeyEquivalent:"), .{bridge.nsString("\r")});
    pg.msgSend(void, objc.sel("addSubview:"), .{btn});

    return pg;
}

// ── Step 2: Accessibility Permission ─────────────────────────────────────

fn buildStep2(parent: objc.Object, frame: CGRect) objc.Object {
    const NSView = bridge.getClass("NSView");
    const NSButton = bridge.getClass("NSButton");

    const pg = NSView.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{frame});
    _ = pg.msgSend(objc.Object, objc.sel("retain"), .{});
    parent.msgSend(void, objc.sel("addSubview:"), .{pg});

    _ = addLabel(pg, "Accessibility Permission", 40, WIN_H - 80, 480, 36, 22.0, true);

    _ = addLabel(pg, "SnapPoint needs Accessibility access to move and\n" ++
        "resize windows on your behalf.", 40, WIN_H - 150, 480, 50, 14.0, false);

    _ = addLabel(pg, "1.  Click \u{201C}Open System Settings\u{201D} below.\n" ++
        "2.  Find SnapPoint in the list and toggle it on.\n" ++
        "3.  Return here \u{2014} we\u{2019}ll detect it automatically.", 40, WIN_H - 250, 480, 80, 13.0, false);

    // Status label ("Waiting for permission…" / "✓ Granted")
    const ActCls = bridge.getClass("SnapOnboardingActionTarget");
    const act = ActCls.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("init"), .{});
    _ = act.msgSend(objc.Object, objc.sel("retain"), .{});

    const status_lbl = addLabel(pg, "Waiting for permission\u{2026}", 40, WIN_H - 300, 380, 22, 12.0, false);
    _ = status_lbl.msgSend(objc.Object, objc.sel("retain"), .{});
    g_permit_status = status_lbl;
    const NSColor = bridge.getClass("NSColor");
    const gray = NSColor.msgSend(objc.Object, objc.sel("secondaryLabelColor"), .{});
    status_lbl.msgSend(void, objc.sel("setTextColor:"), .{gray});

    // Open System Settings button
    const settings_btn = NSButton.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{cgRect(40, 30, 200, 36)});
    settings_btn.msgSend(void, objc.sel("setTitle:"), .{bridge.nsString("Open System Settings")});
    settings_btn.msgSend(void, objc.sel("setBezelStyle:"), .{@as(c_ulong, 1)});
    settings_btn.msgSend(void, objc.sel("setTag:"), .{@as(c_long, 10)}); // open settings
    settings_btn.msgSend(void, objc.sel("setTarget:"), .{act});
    settings_btn.msgSend(void, objc.sel("setAction:"), .{objc.sel("advance:")});
    pg.msgSend(void, objc.sel("addSubview:"), .{settings_btn});

    // "I've Enabled It" button (manual advance)
    const done_btn = NSButton.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{cgRect(WIN_W - 200, 30, 160, 36)});
    done_btn.msgSend(void, objc.sel("setTitle:"), .{bridge.nsString("I\u{2019}ve Enabled It")});
    done_btn.msgSend(void, objc.sel("setBezelStyle:"), .{@as(c_ulong, 1)});
    done_btn.msgSend(void, objc.sel("setTag:"), .{@as(c_long, 2)}); // advance to step 2
    done_btn.msgSend(void, objc.sel("setTarget:"), .{act});
    done_btn.msgSend(void, objc.sel("setAction:"), .{objc.sel("advance:")});
    pg.msgSend(void, objc.sel("addSubview:"), .{done_btn});

    return pg;
}

// ── Step 3: Shortcut Preset ───────────────────────────────────────────────

fn buildStep3(parent: objc.Object, frame: CGRect) objc.Object {
    const NSView = bridge.getClass("NSView");
    const NSButton = bridge.getClass("NSButton");

    const pg = NSView.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{frame});
    _ = pg.msgSend(objc.Object, objc.sel("retain"), .{});
    parent.msgSend(void, objc.sel("addSubview:"), .{pg});

    _ = addLabel(pg, "Choose Your Shortcut Style", 40, WIN_H - 80, 480, 36, 22.0, true);
    _ = addLabel(pg, "Both styles use ⌃⌥ as the modifier base.", 40, WIN_H - 130, 480, 28, 14.0, false);

    // Compact radio
    const ActCls = bridge.getClass("SnapOnboardingActionTarget");
    const act = ActCls.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("init"), .{});
    _ = act.msgSend(objc.Object, objc.sel("retain"), .{});

    const radio1 = makeRadio(pg, "Compact (recommended)", 40, WIN_H - 190, 350, 1, act);
    _ = radio1;
    const radio2 = makeRadio(pg, "Custom \u{2014} start with no shortcuts", 40, WIN_H - 230, 350, 2, act);
    _ = radio2;

    _ = addLabel(pg, "Compact:  ⌃⌥←  ⌃⌥→  ⌃⌥↑  ⌃⌥↓  and more\n" ++
        "Custom:   All shortcuts empty (configure in Settings)", 60, WIN_H - 300, 440, 60, 12.0, false);

    // Get Started button
    const gs_btn = NSButton.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{cgRect(WIN_W - 200, 30, 160, 36)});
    gs_btn.msgSend(void, objc.sel("setTitle:"), .{bridge.nsString("Get Started \u{2713}")});
    gs_btn.msgSend(void, objc.sel("setBezelStyle:"), .{@as(c_ulong, 1)});
    gs_btn.msgSend(void, objc.sel("setTag:"), .{@as(c_long, 99)}); // finish
    gs_btn.msgSend(void, objc.sel("setTarget:"), .{act});
    gs_btn.msgSend(void, objc.sel("setAction:"), .{objc.sel("advance:")});
    gs_btn.msgSend(void, objc.sel("setKeyEquivalent:"), .{bridge.nsString("\r")});
    pg.msgSend(void, objc.sel("addSubview:"), .{gs_btn});

    return pg;
}

fn makeRadio(
    parent: objc.Object,
    title: [:0]const u8,
    x: f64,
    y: f64,
    w: f64,
    tag: c_long,
    target: objc.Object,
) objc.Object {
    const NSButton = bridge.getClass("NSButton");
    const btn = NSButton.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{cgRect(x, y, w, 24)});
    btn.msgSend(void, objc.sel("setButtonType:"), .{@as(c_ulong, 4)}); // NSButtonTypeRadio
    btn.msgSend(void, objc.sel("setTitle:"), .{bridge.nsString(title)});
    btn.msgSend(void, objc.sel("setTag:"), .{tag});
    btn.msgSend(void, objc.sel("setTarget:"), .{target});
    btn.msgSend(void, objc.sel("setAction:"), .{objc.sel("selectPreset:")});
    if (tag == 1) // "Compact" selected by default
        btn.msgSend(void, objc.sel("setState:"), .{@as(c_long, 1)});
    parent.msgSend(void, objc.sel("addSubview:"), .{btn});
    return btn;
}

// Shortcut preset to apply on "Get Started"
var g_chosen_preset: c_long = 1; // 1=Compact, 2=Custom

// ── Step display ──────────────────────────────────────────────────────────

fn showStep(step: usize) void {
    g_current_step = step;
    for (g_steps, 0..) |maybe_pg, i| {
        if (maybe_pg) |pg| pg.msgSend(void, objc.sel("setHidden:"), .{i != step});
    }

    if (step == 1) {
        // Start permission polling
        startPollTimer();
        updatePermitStatus();
    } else {
        stopPollTimer();
    }

    if (g_window) |win| {
        const step_titles = [3][:0]const u8{
            "Welcome to SnapPoint",
            "Accessibility Permission",
            "Almost Done!",
        };
        win.msgSend(void, objc.sel("setTitle:"), .{bridge.nsString(step_titles[step])});
    }
}

fn updatePermitStatus() void {
    if (g_permit_status == null) return;
    const granted = perm.isGranted();
    const NSColor = bridge.getClass("NSColor");
    if (granted) {
        g_permit_status.?.msgSend(void, objc.sel("setStringValue:"), .{bridge.nsString("\u{2713} Accessibility granted \u{2014} you are good to go!")});
        const green = NSColor.msgSend(objc.Object, objc.sel("systemGreenColor"), .{});
        g_permit_status.?.msgSend(void, objc.sel("setTextColor:"), .{green});
    } else {
        g_permit_status.?.msgSend(void, objc.sel("setStringValue:"), .{bridge.nsString("Waiting for permission\u{2026}")});
        const secondary = NSColor.msgSend(objc.Object, objc.sel("secondaryLabelColor"), .{});
        g_permit_status.?.msgSend(void, objc.sel("setTextColor:"), .{secondary});
    }
}

// ── Poll timer ────────────────────────────────────────────────────────────

fn startPollTimer() void {
    if (g_poll_timer != null) return;

    const NSTimer = bridge.getClass("NSTimer");
    const ActCls = bridge.getClass("SnapPermissionPoller");
    const poller = ActCls.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("init"), .{});
    _ = poller.msgSend(objc.Object, objc.sel("retain"), .{});

    const timer = NSTimer.msgSend(objc.Object, objc.sel("scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"), .{
        @as(f64, 1.0),
        poller,
        objc.sel("checkPermission:"),
        @as(?*anyopaque, null),
        true,
    });
    _ = timer.msgSend(objc.Object, objc.sel("retain"), .{});
    g_poll_timer = timer;
    log.info("onboarding: permission poll timer started", .{});
}

fn stopPollTimer() void {
    if (g_poll_timer) |t| {
        t.msgSend(void, objc.sel("invalidate"), .{});
        t.msgSend(void, objc.sel("release"), .{});
        g_poll_timer = null;
        log.info("onboarding: permission poll timer stopped", .{});
    }
}

// ── Finish onboarding ─────────────────────────────────────────────────────

fn finishOnboarding() void {
    // Apply chosen shortcut preset
    if (g_chosen_preset == 2) {
        // Custom: disable all shortcuts
        for (&state.g.config.shortcuts) |*sc| sc.enabled = false;
    }
    // Preset 1 = defaults, already loaded

    state.g.config.has_completed_onboarding = true;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    config_mod.save(&state.g.config, gpa.allocator()) catch |e| {
        log.warn("onboarding: config save failed: {any}", .{e});
    };

    stopPollTimer();
    if (g_window) |win| win.msgSend(void, objc.sel("orderOut:"), .{win});
    log.info("onboarding: completed", .{});
}

// ── ObjC class registration ───────────────────────────────────────────────

fn registerClasses() void {
    if (g_classes_reg) return;
    g_classes_reg = true;
    registerWindowDelegate();
    registerActionTarget();
    registerPoller();
}

fn registerWindowDelegate() void {
    const NSObject = objc.getClass("NSObject") orelse return;
    const cls = objc.allocateClassPair(NSObject, "SnapOnboardingDelegate") orelse return;
    _ = cls.addMethod("windowShouldClose:", winShouldClose);
    objc.registerClassPair(cls);
}

fn registerActionTarget() void {
    const NSObject = objc.getClass("NSObject") orelse return;
    const cls = objc.allocateClassPair(NSObject, "SnapOnboardingActionTarget") orelse return;
    _ = cls.addMethod("advance:", actAdvance);
    _ = cls.addMethod("selectPreset:", actSelectPreset);
    objc.registerClassPair(cls);
}

fn registerPoller() void {
    const NSObject = objc.getClass("NSObject") orelse return;
    const cls = objc.allocateClassPair(NSObject, "SnapPermissionPoller") orelse return;
    _ = cls.addMethod("checkPermission:", pollerCheck);
    objc.registerClassPair(cls);
}

// ── ObjC implementations ──────────────────────────────────────────────────

fn winShouldClose(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    _win: objc.c.id,
) callconv(.c) bool {
    _ = _self;
    _ = _cmd;
    const win = objc.Object{ .value = _win };
    win.msgSend(void, objc.sel("orderOut:"), .{win});
    return false;
}

fn actAdvance(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    sender: objc.c.id,
) callconv(.c) void {
    _ = _self;
    _ = _cmd;
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const btn = objc.Object{ .value = sender };
    const tag = btn.msgSend(c_long, objc.sel("tag"), .{});

    switch (tag) {
        0 => showStep(1), // Welcome → Permission
        10 => { // Open System Settings (stay on step 2)
            perm.openSystemSettings();
        },
        2 => { // "I've Enabled It" → advance to step 3
            if (perm.isGranted()) showStep(2) else updatePermitStatus(); // show "still waiting" feedback
        },
        99 => finishOnboarding(), // "Get Started"
        else => {},
    }
}

fn actSelectPreset(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    sender: objc.c.id,
) callconv(.c) void {
    _ = _self;
    _ = _cmd;
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();
    const btn = objc.Object{ .value = sender };
    g_chosen_preset = btn.msgSend(c_long, objc.sel("tag"), .{});
}

fn pollerCheck(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    _timer: objc.c.id,
) callconv(.c) void {
    _ = _self;
    _ = _cmd;
    _ = _timer;
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    updatePermitStatus();

    if (perm.isGranted() and g_current_step == 1) {
        log.info("onboarding: permission granted – advancing to step 3", .{});
        stopPollTimer();
        showStep(2);
    }
}

// ── View helpers ──────────────────────────────────────────────────────────

fn addLabel(
    parent: objc.Object,
    text: []const u8,
    x: f64,
    y: f64,
    w: f64,
    h: f64,
    font_size: f64,
    bold: bool,
) objc.Object {
    const NSTextField = bridge.getClass("NSTextField");
    const lbl = NSTextField.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{cgRect(x, y, w, h)});
    lbl.msgSend(void, objc.sel("setStringValue:"), .{bridge.nsString(text)});
    lbl.msgSend(void, objc.sel("setEditable:"), .{false});
    lbl.msgSend(void, objc.sel("setBordered:"), .{false});
    lbl.msgSend(void, objc.sel("setDrawsBackground:"), .{false});
    lbl.msgSend(void, objc.sel("setUsesSingleLineMode:"), .{false});

    const NSFont = bridge.getClass("NSFont");
    const font = if (bold)
        NSFont.msgSend(objc.Object, objc.sel("boldSystemFontOfSize:"), .{font_size})
    else
        NSFont.msgSend(objc.Object, objc.sel("systemFontOfSize:"), .{font_size});
    lbl.msgSend(void, objc.sel("setFont:"), .{font});

    parent.msgSend(void, objc.sel("addSubview:"), .{lbl});
    return lbl;
}

// ── Geometry helpers ──────────────────────────────────────────────────────

const CGPoint = extern struct { x: f64, y: f64 };
const CGSize = extern struct { width: f64, height: f64 };
const CGRect = extern struct { origin: CGPoint, size: CGSize };

fn cgRect(x: f64, y: f64, w: f64, h: f64) CGRect {
    return .{ .origin = .{ .x = x, .y = y }, .size = .{ .width = w, .height = h } };
}
