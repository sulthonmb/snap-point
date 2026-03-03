//! Settings window: NSWindow (800×600) with sidebar nav and four pages.
//!
//! Pages:
//!   0 – General   (launch-at-login, sensitivity, ghost-window toggle)
//!   1 – Keyboard  (27-row shortcut table with recorder buttons)
//!   2 – Visuals   (window gap + ghost opacity sliders)
//!   3 – Blacklist (bundle-ID list + add/remove buttons)
//!
//! All ObjC classes are registered once and reused across show/hide cycles.

const std = @import("std");
const objc = @import("objc");
const bridge = @import("../objc/bridge.zig");
const log = @import("../core/log.zig");
const state = @import("../core/state.zig");
const config_mod = @import("../core/config.zig");
const constants = @import("../core/constants.zig");
const layout_eng = @import("../engine/layout.zig");
const shortcut_rec = @import("shortcut_recorder.zig");

// ── Window / page geometry ────────────────────────────────────────────────

const WIN_W: f64 = 800;
const WIN_H: f64 = 600;
const SIDE_W: f64 = 200;
const CONT_W: f64 = WIN_W - SIDE_W; // 600

// ── Module-level globals (used from ObjC callbacks) ───────────────────────

var g_window: ?objc.Object = null;
var g_sidebar_table: ?objc.Object = null;
var g_keyboard_table: ?objc.Object = null;
var g_blacklist_table: ?objc.Object = null;
var g_action_target: ?objc.Object = null;
var g_pages: [4]?objc.Object = .{null} ** 4;
var g_current_page: usize = 0;

// General page controls
var g_launch_btn: ?objc.Object = null;
var g_sensitivity_pop: ?objc.Object = null;
var g_ghost_btn: ?objc.Object = null;

// Visuals page controls
var g_gap_slider: ?objc.Object = null;
var g_gap_lbl: ?objc.Object = null;
var g_opacity_slider: ?objc.Object = null;
var g_opacity_lbl: ?objc.Object = null;

var g_classes_registered = false;
var g_notification_observer: ?objc.Object = null;

// ── Action names (sidebar + keyboard table) ───────────────────────────────

const sidebar_names = [4][:0]const u8{ "General", "Keyboard", "Visuals", "Blacklist" };

fn actionName(idx: usize) [:0]const u8 {
    if (idx < 25) return layout_eng.layout_names[idx];
    if (idx == 25) return "Throw to Next Display";
    return "Throw to Prev Display";
}

// ── SettingsWindow struct ─────────────────────────────────────────────────

pub const SettingsWindow = struct {
    initialized: bool = false,

    /// Build the window and all its pages.  Call once on main thread.
    pub fn init() SettingsWindow {
        registerClasses();
        buildWindow();
        subscribeToShortcutChanges();
        log.info("settings_window: initialised", .{});
        return .{ .initialized = true };
    }

    /// Show (or bring to front) the settings window.
    pub fn show(self: *SettingsWindow) void {
        if (!self.initialized) return;
        refreshGeneralPage();
        refreshVisualsPage();
        if (g_window) |win| {
            // Accessory-policy apps (LSUIElement) must explicitly activate
            // before a window can become key and visible in front of others.
            const app = bridge.sharedApplication();
            app.msgSend(void, objc.sel("activateIgnoringOtherApps:"), .{true});
            win.msgSend(void, objc.sel("makeKeyAndOrderFront:"), .{@as(?*anyopaque, null)});
        }
    }

    /// Hide the settings window.
    pub fn hide(self: *SettingsWindow) void {
        _ = self;
        if (g_window) |win| win.msgSend(void, objc.sel("orderOut:"), .{win});
    }
};

// ── Window construction ───────────────────────────────────────────────────

fn buildWindow() void {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSWindow = bridge.getClass("NSWindow");

    // Style: titled (1) + closable (2) + miniaturizable (4)
    const style: c_ulong = 1 | 2 | 4;
    const win_rect = cgRect(0, 0, WIN_W, WIN_H);

    const win = NSWindow.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithContentRect:styleMask:backing:defer:"), .{ win_rect, style, @as(c_ulong, 2), false });

    win.msgSend(void, objc.sel("setTitle:"), .{bridge.nsString("SnapPoint Settings")});
    win.msgSend(void, objc.sel("setReleasedWhenClosed:"), .{false});
    win.msgSend(void, objc.sel("center"), .{});

    // Assign a window delegate (for close → hide behaviour)
    const WinDelClass = bridge.getClass("SnapSettingsWindowDelegate");
    const win_del = WinDelClass.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("init"), .{});
    _ = win_del.msgSend(objc.Object, objc.sel("retain"), .{});
    win.msgSend(void, objc.sel("setDelegate:"), .{win_del});

    _ = win.msgSend(objc.Object, objc.sel("retain"), .{});
    g_window = win;

    const content_view = win.msgSend(objc.Object, objc.sel("contentView"), .{});

    // ── Sidebar ──────────────────────────────────────────────────────
    buildSidebar(content_view);

    // ── Divider line ─────────────────────────────────────────────────
    const NSBox = bridge.getClass("NSBox");
    const divider = NSBox.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{cgRect(SIDE_W, 0, 1, WIN_H)});
    divider.msgSend(void, objc.sel("setBoxType:"), .{@as(c_ulong, 2)}); // NSBoxSeparator=2
    content_view.msgSend(void, objc.sel("addSubview:"), .{divider});

    // ── Content container ────────────────────────────────────────────
    buildContentPages(content_view);

    // Select first page
    selectPage(0);
}

// ── Sidebar ───────────────────────────────────────────────────────────────

fn buildSidebar(parent: objc.Object) void {
    const NSScrollView = bridge.getClass("NSScrollView");
    const NSTableView = bridge.getClass("NSTableView");
    const NSTableColumn = bridge.getClass("NSTableColumn");

    const frame = cgRect(0, 0, SIDE_W, WIN_H);

    const col = NSTableColumn.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithIdentifier:"), .{bridge.nsString("sidebar")});
    col.msgSend(void, objc.sel("setWidth:"), .{SIDE_W - 4.0});

    const tv = NSTableView.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{frame});
    tv.msgSend(void, objc.sel("addTableColumn:"), .{col});
    tv.msgSend(void, objc.sel("setHeaderView:"), .{@as(?*anyopaque, null)});
    tv.msgSend(void, objc.sel("setTag:"), .{@as(c_long, 1001)});
    tv.msgSend(void, objc.sel("setRowHeight:"), .{@as(f64, 36)});
    tv.msgSend(void, objc.sel("setAllowsEmptySelection:"), .{false});
    tv.msgSend(void, objc.sel("setUsesAlternatingRowBackgroundColors:"), .{false});
    // NSTableViewStyleSourceList = 5 (macOS 12+)
    if (tv.msgSend(bool, objc.sel("respondsToSelector:"), .{objc.sel("setStyle:")})) {
        tv.msgSend(void, objc.sel("setStyle:"), .{@as(c_long, 5)});
    }

    const SideDelClass = bridge.getClass("SnapSidebarDelegate");
    const side_del = SideDelClass.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("init"), .{});
    _ = side_del.msgSend(objc.Object, objc.sel("retain"), .{});
    tv.msgSend(void, objc.sel("setDelegate:"), .{side_del});
    tv.msgSend(void, objc.sel("setDataSource:"), .{side_del});

    _ = tv.msgSend(objc.Object, objc.sel("retain"), .{});
    g_sidebar_table = tv;

    const sv = NSScrollView.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{frame});
    sv.msgSend(void, objc.sel("setDocumentView:"), .{tv});
    sv.msgSend(void, objc.sel("setHasVerticalScroller:"), .{false});
    parent.msgSend(void, objc.sel("addSubview:"), .{sv});
}

// ── Content pages ─────────────────────────────────────────────────────────

fn buildContentPages(parent: objc.Object) void {
    const frame = cgRect(SIDE_W + 1, 0, CONT_W - 2, WIN_H);
    const NSView = bridge.getClass("NSView");

    // Container that holds all 4 pages stacked; only one visible at a time
    const container = NSView.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{frame});
    _ = container.msgSend(objc.Object, objc.sel("retain"), .{});
    parent.msgSend(void, objc.sel("addSubview:"), .{container});

    // Action target for control actions
    const ActClass = bridge.getClass("SnapSettingsActionTarget");
    const act = ActClass.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("init"), .{});
    _ = act.msgSend(objc.Object, objc.sel("retain"), .{});
    g_action_target = act;

    const page_frame = cgRect(0, 0, CONT_W - 2, WIN_H);

    g_pages[0] = buildGeneralPage(page_frame);
    g_pages[1] = buildKeyboardPage(page_frame);
    g_pages[2] = buildVisualsPage(page_frame);
    g_pages[3] = buildBlacklistPage(page_frame);

    for (g_pages) |maybe_pg| {
        if (maybe_pg) |pg| {
            container.msgSend(void, objc.sel("addSubview:"), .{pg});
        }
    }
}

// ── General page ──────────────────────────────────────────────────────────

fn buildGeneralPage(frame: CGRect) objc.Object {
    const NSView = bridge.getClass("NSView");
    const pg = NSView.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{frame});
    _ = pg.msgSend(objc.Object, objc.sel("retain"), .{});

    const w = frame.size.width;
    _ = w;

    // Row helper: y from top
    const pad_top: f64 = 40;
    const row_h: f64 = 50;

    // Title
    _ = addLabel(pg, "General Settings", 20, WIN_H - 32, 400, 24, 14.0, true);

    // Row 0 – Launch at Login
    _ = addLabel(pg, "Launch at Login", 20, WIN_H - pad_top - row_h * 1, 200, 22, 13.0, false);
    const launch_btn = makeToggle("at_startup", pg);
    launch_btn.msgSend(void, objc.sel("setFrame:"), .{cgRect(220, WIN_H - pad_top - row_h * 1, 50, 22)});
    launch_btn.msgSend(void, objc.sel("setTarget:"), .{g_action_target.?});
    launch_btn.msgSend(void, objc.sel("setAction:"), .{objc.sel("toggleLaunchAtLogin:")});
    _ = launch_btn.msgSend(objc.Object, objc.sel("retain"), .{});
    g_launch_btn = launch_btn;

    // Row 1 – Snap Sensitivity
    _ = addLabel(pg, "Snap Sensitivity", 20, WIN_H - pad_top - row_h * 2, 200, 22, 13.0, false);
    const pop = makeSensitivityPopup(pg);
    pop.msgSend(void, objc.sel("setFrame:"), .{cgRect(220, WIN_H - pad_top - row_h * 2, 120, 24)});
    pop.msgSend(void, objc.sel("setTarget:"), .{g_action_target.?});
    pop.msgSend(void, objc.sel("setAction:"), .{objc.sel("changeSensitivity:")});
    _ = pop.msgSend(objc.Object, objc.sel("retain"), .{});
    g_sensitivity_pop = pop;

    // Row 2 – Show Ghost Window
    _ = addLabel(pg, "Show Ghost Window Preview", 20, WIN_H - pad_top - row_h * 3, 200, 22, 13.0, false);
    const ghost_btn = makeToggle("ghost_toggle", pg);
    ghost_btn.msgSend(void, objc.sel("setFrame:"), .{cgRect(220, WIN_H - pad_top - row_h * 3, 50, 22)});
    ghost_btn.msgSend(void, objc.sel("setTarget:"), .{g_action_target.?});
    ghost_btn.msgSend(void, objc.sel("setAction:"), .{objc.sel("toggleGhostWindow:")});
    _ = ghost_btn.msgSend(objc.Object, objc.sel("retain"), .{});
    g_ghost_btn = ghost_btn;

    return pg;
}

fn refreshGeneralPage() void {
    const c = &state.g.config;
    if (g_launch_btn) |b| b.msgSend(void, objc.sel("setState:"), .{@as(c_long, if (c.launch_at_login) 1 else 0)});
    if (g_ghost_btn) |b| b.msgSend(void, objc.sel("setState:"), .{@as(c_long, if (c.show_ghost_window) 1 else 0)});
    if (g_sensitivity_pop) |p| {
        // index: 5px→0, 10px→1, 15px→2, 20px→3
        const idx: c_long = switch (c.snap_sensitivity) {
            5 => 0,
            15 => 2,
            20 => 3,
            else => 1, // 10 is default
        };
        p.msgSend(void, objc.sel("selectItemAtIndex:"), .{idx});
    }
}

// ── Keyboard page ─────────────────────────────────────────────────────────

fn buildKeyboardPage(frame: CGRect) objc.Object {
    const NSView = bridge.getClass("NSView");
    const NSScrollView = bridge.getClass("NSScrollView");
    const NSTableView = bridge.getClass("NSTableView");
    const NSTableColumn = bridge.getClass("NSTableColumn");

    const pg = NSView.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{frame});
    _ = pg.msgSend(objc.Object, objc.sel("retain"), .{});

    _ = addLabel(pg, "Keyboard Shortcuts", 20, WIN_H - 32, 400, 24, 14.0, true);
    _ = addLabel(pg, "Click a shortcut button to record a new one.", 20, WIN_H - 54, 500, 18, 11.0, false);

    // Two columns: Action (300pt) + Shortcut (240pt)
    const col_action = NSTableColumn.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithIdentifier:"), .{bridge.nsString("action")});
    col_action.msgSend(void, objc.sel("setTitle:"), .{bridge.nsString("Action")});
    col_action.msgSend(void, objc.sel("setWidth:"), .{@as(f64, 300)});

    const col_shortcut = NSTableColumn.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithIdentifier:"), .{bridge.nsString("shortcut")});
    col_shortcut.msgSend(void, objc.sel("setTitle:"), .{bridge.nsString("Shortcut")});
    col_shortcut.msgSend(void, objc.sel("setWidth:"), .{@as(f64, 240)});

    const table_frame = cgRect(0, 0, frame.size.width, frame.size.height);
    const tv = NSTableView.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{table_frame});
    tv.msgSend(void, objc.sel("addTableColumn:"), .{col_action});
    tv.msgSend(void, objc.sel("addTableColumn:"), .{col_shortcut});
    tv.msgSend(void, objc.sel("setTag:"), .{@as(c_long, 1002)});
    tv.msgSend(void, objc.sel("setRowHeight:"), .{@as(f64, 28)});
    tv.msgSend(void, objc.sel("setUsesAlternatingRowBackgroundColors:"), .{true});

    const DelClass = bridge.getClass("SnapKeyboardDelegate");
    const del = DelClass.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("init"), .{});
    _ = del.msgSend(objc.Object, objc.sel("retain"), .{});
    tv.msgSend(void, objc.sel("setDelegate:"), .{del});
    tv.msgSend(void, objc.sel("setDataSource:"), .{del});

    _ = tv.msgSend(objc.Object, objc.sel("retain"), .{});
    g_keyboard_table = tv;

    const sv = NSScrollView.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{cgRect(0, 44, frame.size.width, WIN_H - 104)});
    sv.msgSend(void, objc.sel("setDocumentView:"), .{tv});
    sv.msgSend(void, objc.sel("setHasVerticalScroller:"), .{true});
    sv.msgSend(void, objc.sel("setAutohidesScrollers:"), .{true});
    pg.msgSend(void, objc.sel("addSubview:"), .{sv});

    // Reset Defaults button (per TRD 9.2 Keyboard Page)
    const NSButton = bridge.getClass("NSButton");
    const reset_btn = NSButton.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{cgRect(20, 10, 130, 28)});
    reset_btn.msgSend(void, objc.sel("setTitle:"), .{bridge.nsString("Reset Defaults")});
    reset_btn.msgSend(void, objc.sel("setBezelStyle:"), .{@as(c_ulong, 1)}); // NSBezelStyleRounded
    reset_btn.msgSend(void, objc.sel("setTarget:"), .{g_action_target.?});
    reset_btn.msgSend(void, objc.sel("setAction:"), .{objc.sel("resetShortcutDefaults:")});
    pg.msgSend(void, objc.sel("addSubview:"), .{reset_btn});

    return pg;
}

// ── Visuals page ──────────────────────────────────────────────────────────

fn buildVisualsPage(frame: CGRect) objc.Object {
    const NSView = bridge.getClass("NSView");
    const pg = NSView.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{frame});
    _ = pg.msgSend(objc.Object, objc.sel("retain"), .{});

    const pad_top: f64 = 40;
    const row_h: f64 = 60;

    _ = addLabel(pg, "Visuals", 20, WIN_H - 32, 400, 24, 14.0, true);

    // Row 0 – Window Gap
    _ = addLabel(pg, "Window Gap (px)", 20, WIN_H - pad_top - row_h * 1 + 20, 200, 18, 13.0, false);
    const gap_slider = makeSlider(0, 50, pg);
    gap_slider.msgSend(void, objc.sel("setFrame:"), .{cgRect(20, WIN_H - pad_top - row_h * 1, 380, 24)});
    gap_slider.msgSend(void, objc.sel("setTarget:"), .{g_action_target.?});
    gap_slider.msgSend(void, objc.sel("setAction:"), .{objc.sel("changeWindowGap:")});
    _ = gap_slider.msgSend(objc.Object, objc.sel("retain"), .{});
    g_gap_slider = gap_slider;

    const gap_lbl = addLabel(pg, "0 px", 410, WIN_H - pad_top - row_h * 1, 80, 22, 13.0, false);
    _ = gap_lbl.msgSend(objc.Object, objc.sel("retain"), .{});
    g_gap_lbl = gap_lbl;

    // Row 1 – Ghost Opacity
    _ = addLabel(pg, "Ghost Window Opacity", 20, WIN_H - pad_top - row_h * 2 + 20, 200, 18, 13.0, false);
    const opacity_slider = makeSlider(0, 100, pg); // 0-100 maps to 0.0-1.0
    opacity_slider.msgSend(void, objc.sel("setFrame:"), .{cgRect(20, WIN_H - pad_top - row_h * 2, 380, 24)});
    opacity_slider.msgSend(void, objc.sel("setTarget:"), .{g_action_target.?});
    opacity_slider.msgSend(void, objc.sel("setAction:"), .{objc.sel("changeGhostOpacity:")});
    _ = opacity_slider.msgSend(objc.Object, objc.sel("retain"), .{});
    g_opacity_slider = opacity_slider;

    const opacity_lbl = addLabel(pg, "30%", 410, WIN_H - pad_top - row_h * 2, 80, 22, 13.0, false);
    _ = opacity_lbl.msgSend(objc.Object, objc.sel("retain"), .{});
    g_opacity_lbl = opacity_lbl;

    return pg;
}

fn refreshVisualsPage() void {
    const c = &state.g.config;
    if (g_gap_slider) |s| s.msgSend(void, objc.sel("setDoubleValue:"), .{@as(f64, @floatFromInt(c.window_gap))});
    if (g_gap_lbl) |l| {
        var buf: [32]u8 = undefined;
        const txt = std.fmt.bufPrintZ(&buf, "{d} px", .{c.window_gap}) catch "0 px";
        l.msgSend(void, objc.sel("setStringValue:"), .{bridge.nsString(txt)});
    }
    if (g_opacity_slider) |s| s.msgSend(void, objc.sel("setDoubleValue:"), .{@as(f64, c.ghost_opacity * 100.0)});
    if (g_opacity_lbl) |l| {
        var buf: [32]u8 = undefined;
        const pct: u32 = @intFromFloat(c.ghost_opacity * 100.0);
        const txt = std.fmt.bufPrintZ(&buf, "{d}%", .{pct}) catch "30%";
        l.msgSend(void, objc.sel("setStringValue:"), .{bridge.nsString(txt)});
    }
}

// ── Blacklist page ────────────────────────────────────────────────────────

fn buildBlacklistPage(frame: CGRect) objc.Object {
    const NSView = bridge.getClass("NSView");
    const NSScrollView = bridge.getClass("NSScrollView");
    const NSTableView = bridge.getClass("NSTableView");
    const NSTableColumn = bridge.getClass("NSTableColumn");
    const NSButton = bridge.getClass("NSButton");

    const pg2 = NSView.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{frame});
    _ = pg2.msgSend(objc.Object, objc.sel("retain"), .{});

    _ = addLabel(pg2, "App Blacklist", 20, WIN_H - 32, 400, 24, 14.0, true);
    _ = addLabel(pg2, "Apps listed here will not have their windows snapped.", 20, WIN_H - 54, 500, 18, 11.0, false);

    const col = NSTableColumn.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithIdentifier:"), .{bridge.nsString("bundle_id")});
    col.msgSend(void, objc.sel("setTitle:"), .{bridge.nsString("Bundle Identifier")});
    col.msgSend(void, objc.sel("setWidth:"), .{frame.size.width - 20.0});

    const tv = NSTableView.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{cgRect(0, 0, frame.size.width, WIN_H - 110)});
    tv.msgSend(void, objc.sel("addTableColumn:"), .{col});
    tv.msgSend(void, objc.sel("setTag:"), .{@as(c_long, 1003)});
    tv.msgSend(void, objc.sel("setRowHeight:"), .{@as(f64, 24)});

    const BlClass = bridge.getClass("SnapBlacklistDelegate");
    const bl_del = BlClass.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("init"), .{});
    _ = bl_del.msgSend(objc.Object, objc.sel("retain"), .{});
    tv.msgSend(void, objc.sel("setDelegate:"), .{bl_del});
    tv.msgSend(void, objc.sel("setDataSource:"), .{bl_del});

    _ = tv.msgSend(objc.Object, objc.sel("retain"), .{});
    g_blacklist_table = tv;

    const sv = NSScrollView.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{cgRect(0, 44, frame.size.width, WIN_H - 110)});
    sv.msgSend(void, objc.sel("setDocumentView:"), .{tv});
    sv.msgSend(void, objc.sel("setHasVerticalScroller:"), .{true});
    sv.msgSend(void, objc.sel("setAutohidesScrollers:"), .{true});
    pg2.msgSend(void, objc.sel("addSubview:"), .{sv});

    // Add (+) button
    const add_btn = NSButton.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{cgRect(20, 10, 80, 28)});
    add_btn.msgSend(void, objc.sel("setTitle:"), .{bridge.nsString("+ Add App")});
    add_btn.msgSend(void, objc.sel("setBezelStyle:"), .{@as(c_ulong, 1)}); // NSBezelStyleRounded
    add_btn.msgSend(void, objc.sel("setTarget:"), .{g_action_target.?});
    add_btn.msgSend(void, objc.sel("setAction:"), .{objc.sel("addBlacklistApp:")});
    pg2.msgSend(void, objc.sel("addSubview:"), .{add_btn});

    // Remove (-) button
    const rem_btn = NSButton.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{cgRect(110, 10, 100, 28)});
    rem_btn.msgSend(void, objc.sel("setTitle:"), .{bridge.nsString("- Remove")});
    rem_btn.msgSend(void, objc.sel("setBezelStyle:"), .{@as(c_ulong, 1)});
    rem_btn.msgSend(void, objc.sel("setTarget:"), .{g_action_target.?});
    rem_btn.msgSend(void, objc.sel("setAction:"), .{objc.sel("removeBlacklistApp:")});
    pg2.msgSend(void, objc.sel("addSubview:"), .{rem_btn});

    return pg2;
}

// ── Page selection ────────────────────────────────────────────────────────

fn selectPage(idx: usize) void {
    g_current_page = idx;
    for (g_pages, 0..) |maybe_pg, i| {
        if (maybe_pg) |pg| {
            pg.msgSend(void, objc.sel("setHidden:"), .{i != idx});
        }
    }
    // Select the correct sidebar row
    if (g_sidebar_table) |t| {
        const NSIndexSet = bridge.getClass("NSIndexSet");
        const sel_set = NSIndexSet.msgSend(objc.Object, objc.sel("alloc"), .{})
            .msgSend(objc.Object, objc.sel("initWithIndex:"), .{@as(c_ulong, idx)});
        t.msgSend(void, objc.sel("selectRowIndexes:byExtendingSelection:"), .{ sel_set, false });
    }
}

// ── Notification subscription ─────────────────────────────────────────────

fn subscribeToShortcutChanges() void {
    // Register SnapSettingsNotifyTarget class
    registerNotifyClass();

    const NotifyClass = bridge.getClass("SnapSettingsNotifyTarget");
    const observer = NotifyClass.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("init"), .{});
    _ = observer.msgSend(objc.Object, objc.sel("retain"), .{});
    g_notification_observer = observer;

    const nc = bridge.getClass("NSNotificationCenter")
        .msgSend(objc.Object, objc.sel("defaultCenter"), .{});
    nc.msgSend(void, objc.sel("addObserver:selector:name:object:"), .{
        observer,
        objc.sel("shortcutChanged:"),
        bridge.nsString("SnapShortcutChanged"),
        @as(objc.Object, .{ .value = null }),
    });
}

// ── View helpers ──────────────────────────────────────────────────────────

// Returns the label for chaining / storing
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

    const NSFont = bridge.getClass("NSFont");
    const font = if (bold)
        NSFont.msgSend(objc.Object, objc.sel("boldSystemFontOfSize:"), .{font_size})
    else
        NSFont.msgSend(objc.Object, objc.sel("systemFontOfSize:"), .{font_size});
    lbl.msgSend(void, objc.sel("setFont:"), .{font});

    parent.msgSend(void, objc.sel("addSubview:"), .{lbl});
    return lbl;
}

fn makeToggle(title: [:0]const u8, parent: objc.Object) objc.Object {
    _ = title;
    const NSButton = bridge.getClass("NSButton");
    const btn = NSButton.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{cgRect(0, 0, 50, 22)});
    btn.msgSend(void, objc.sel("setButtonType:"), .{@as(c_ulong, 6)}); // NSButtonTypeToggle = 6
    btn.msgSend(void, objc.sel("setTitle:"), .{bridge.nsString("")});
    btn.msgSend(void, objc.sel("setBezelStyle:"), .{@as(c_ulong, 12)}); // NSBezelStyleDisclosure-like

    // Fallback: NSButton checkbox/switch style (works on all macOS versions)
    btn.msgSend(void, objc.sel("setButtonType:"), .{@as(c_ulong, 3)}); // NSButtonTypeSwitch = 3
    btn.msgSend(void, objc.sel("setTitle:"), .{bridge.nsString("On")});
    parent.msgSend(void, objc.sel("addSubview:"), .{btn});
    return btn;
}

fn makeSensitivityPopup(parent: objc.Object) objc.Object {
    const NSPopUpButton = bridge.getClass("NSPopUpButton");
    const pop = NSPopUpButton.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:pullsDown:"), .{ cgRect(0, 0, 120, 24), false });
    _ = pop.msgSend(bool, objc.sel("addItemWithTitle:"), .{bridge.nsString("5 px")});
    _ = pop.msgSend(bool, objc.sel("addItemWithTitle:"), .{bridge.nsString("10 px")});
    _ = pop.msgSend(bool, objc.sel("addItemWithTitle:"), .{bridge.nsString("15 px")});
    _ = pop.msgSend(bool, objc.sel("addItemWithTitle:"), .{bridge.nsString("20 px")});
    parent.msgSend(void, objc.sel("addSubview:"), .{pop});
    return pop;
}

fn makeSlider(min_val: f64, max_val: f64, parent: objc.Object) objc.Object {
    const NSSlider = bridge.getClass("NSSlider");
    const sl = NSSlider.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{cgRect(0, 0, 380, 24)});
    sl.msgSend(void, objc.sel("setMinValue:"), .{min_val});
    sl.msgSend(void, objc.sel("setMaxValue:"), .{max_val});
    sl.msgSend(void, objc.sel("setNumberOfTickMarks:"), .{@as(c_long, 0)});
    parent.msgSend(void, objc.sel("addSubview:"), .{sl});
    return sl;
}

// ── Immediate save helper ─────────────────────────────────────────────────

fn saveConfig() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    config_mod.save(&state.g.config, gpa.allocator()) catch |e| {
        log.warn("settings: save failed: {any}", .{e});
    };
}

// ── ObjC class registration ───────────────────────────────────────────────

fn registerClasses() void {
    if (g_classes_registered) return;
    g_classes_registered = true;

    registerWindowDelegate();
    registerSidebarDelegate();
    registerKeyboardDelegate();
    registerBlacklistDelegate();
    registerActionTarget();
    registerNotifyClass();
}

fn registerWindowDelegate() void {
    const NSObject = objc.getClass("NSObject") orelse return;
    const cls = objc.allocateClassPair(NSObject, "SnapSettingsWindowDelegate") orelse return;
    _ = cls.addMethod("windowShouldClose:", winShouldClose);
    objc.registerClassPair(cls);
}

fn registerSidebarDelegate() void {
    const NSObject = objc.getClass("NSObject") orelse return;
    const cls = objc.allocateClassPair(NSObject, "SnapSidebarDelegate") orelse return;
    _ = cls.addMethod("numberOfRowsInTableView:", sidebarNumRows);
    _ = cls.addMethod("tableView:viewForTableColumn:row:", sidebarViewForRow);
    _ = cls.addMethod("tableViewSelectionDidChange:", sidebarSelectionChanged);
    objc.registerClassPair(cls);
}

fn registerKeyboardDelegate() void {
    const NSObject = objc.getClass("NSObject") orelse return;
    const cls = objc.allocateClassPair(NSObject, "SnapKeyboardDelegate") orelse return;
    _ = cls.addMethod("numberOfRowsInTableView:", keyboardNumRows);
    _ = cls.addMethod("tableView:viewForTableColumn:row:", keyboardViewForRow);
    objc.registerClassPair(cls);
}

fn registerBlacklistDelegate() void {
    const NSObject = objc.getClass("NSObject") orelse return;
    const cls = objc.allocateClassPair(NSObject, "SnapBlacklistDelegate") orelse return;
    _ = cls.addMethod("numberOfRowsInTableView:", blacklistNumRows);
    _ = cls.addMethod("tableView:viewForTableColumn:row:", blacklistViewForRow);
    objc.registerClassPair(cls);
}

fn registerActionTarget() void {
    const NSObject = objc.getClass("NSObject") orelse return;
    const cls = objc.allocateClassPair(NSObject, "SnapSettingsActionTarget") orelse return;
    _ = cls.addMethod("toggleLaunchAtLogin:", actToggleLaunch);
    _ = cls.addMethod("changeSensitivity:", actChangeSensitivity);
    _ = cls.addMethod("toggleGhostWindow:", actToggleGhost);
    _ = cls.addMethod("changeWindowGap:", actChangeGap);
    _ = cls.addMethod("changeGhostOpacity:", actChangeOpacity);
    _ = cls.addMethod("addBlacklistApp:", actAddBlacklist);
    _ = cls.addMethod("removeBlacklistApp:", actRemoveBlacklist);
    _ = cls.addMethod("clickShortcutRecord:", actClickShortcutRecord);
    _ = cls.addMethod("resetShortcutDefaults:", actResetShortcutDefaults);
    objc.registerClassPair(cls);
}

fn registerNotifyClass() void {
    if (objc.getClass("SnapSettingsNotifyTarget") != null) return;
    const NSObject = objc.getClass("NSObject") orelse return;
    const cls = objc.allocateClassPair(NSObject, "SnapSettingsNotifyTarget") orelse return;
    _ = cls.addMethod("shortcutChanged:", notifyShortcutChanged);
    objc.registerClassPair(cls);
}

// ── Window delegate methods ───────────────────────────────────────────────

fn winShouldClose(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    _win: objc.c.id,
) callconv(.c) bool {
    _ = _self;
    _ = _cmd;
    // Hide instead of close
    const win = objc.Object{ .value = _win };
    win.msgSend(void, objc.sel("orderOut:"), .{win});
    return false;
}

// ── Sidebar delegate methods ──────────────────────────────────────────────

fn sidebarNumRows(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    _tv: objc.c.id,
) callconv(.c) c_long {
    _ = _self;
    _ = _cmd;
    _ = _tv;
    return 4;
}

fn sidebarViewForRow(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    _tv: objc.c.id,
    _col: objc.c.id,
    row: c_long,
) callconv(.c) objc.c.id {
    _ = _self;
    _ = _cmd;
    _ = _tv;
    _ = _col;
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    if (row < 0 or row >= 4) return null;
    const idx: usize = @intCast(row);

    const NSTextField = bridge.getClass("NSTextField");
    const tf = NSTextField.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{cgRect(8, 4, SIDE_W - 16, 26)});
    tf.msgSend(void, objc.sel("setStringValue:"), .{bridge.nsString(sidebar_names[idx])});
    tf.msgSend(void, objc.sel("setEditable:"), .{false});
    tf.msgSend(void, objc.sel("setBordered:"), .{false});
    tf.msgSend(void, objc.sel("setDrawsBackground:"), .{false});

    const NSFont = bridge.getClass("NSFont");
    const font = NSFont.msgSend(objc.Object, objc.sel("systemFontOfSize:"), .{@as(f64, 13.0)});
    tf.msgSend(void, objc.sel("setFont:"), .{font});

    return tf.value;
}

fn sidebarSelectionChanged(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    notif: objc.c.id,
) callconv(.c) void {
    _ = _self;
    _ = _cmd;
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const n = objc.Object{ .value = notif };
    const tv = n.msgSend(objc.Object, objc.sel("object"), .{});
    const sel_row = tv.msgSend(c_long, objc.sel("selectedRow"), .{});
    if (sel_row < 0) return;

    const new_page: usize = @intCast(sel_row);
    selectPage(new_page);

    if (new_page == 0) refreshGeneralPage();
    if (new_page == 2) refreshVisualsPage();
}

// ── Keyboard delegate methods ─────────────────────────────────────────────

fn keyboardNumRows(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    _tv: objc.c.id,
) callconv(.c) c_long {
    _ = _self;
    _ = _cmd;
    _ = _tv;
    return @intCast(constants.action_count);
}

fn keyboardViewForRow(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    _tv: objc.c.id,
    _col: objc.c.id,
    row: c_long,
) callconv(.c) objc.c.id {
    _ = _self;
    _ = _cmd;
    _ = _tv;
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    if (row < 0 or row >= @as(c_long, constants.action_count)) return null;
    const idx: usize = @intCast(row);

    const col_obj = objc.Object{ .value = _col };
    const col_id_ns = col_obj.msgSend(objc.Object, objc.sel("identifier"), .{});
    var col_buf: [64]u8 = undefined;
    const col_id = bridge.zigString(col_id_ns, &col_buf);

    const NSTextField = bridge.getClass("NSTextField");
    const NSButton = bridge.getClass("NSButton");

    if (std.mem.eql(u8, col_id, "action")) {
        const tf = NSTextField.msgSend(objc.Object, objc.sel("alloc"), .{})
            .msgSend(objc.Object, objc.sel("initWithFrame:"), .{cgRect(4, 2, 296, 24)});
        tf.msgSend(void, objc.sel("setStringValue:"), .{bridge.nsString(actionName(idx))});
        tf.msgSend(void, objc.sel("setEditable:"), .{false});
        tf.msgSend(void, objc.sel("setBordered:"), .{false});
        tf.msgSend(void, objc.sel("setDrawsBackground:"), .{false});
        return tf.value;
    }

    // "shortcut" column: NSButton showing current shortcut
    const sc = state.g.config.shortcuts[idx];
    var fmt_buf: [64]u8 = undefined;
    const fmt = shortcut_rec.formatShortcut(sc.key_code, sc.modifiers, &fmt_buf);

    const btn = NSButton.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{cgRect(4, 2, 232, 24)});
    btn.msgSend(void, objc.sel("setTitle:"), .{bridge.nsString(fmt)});
    btn.msgSend(void, objc.sel("setTag:"), .{@as(c_long, @intCast(idx))});
    btn.msgSend(void, objc.sel("setBezelStyle:"), .{@as(c_ulong, 1)});
    btn.msgSend(void, objc.sel("setTarget:"), .{g_action_target.?});
    btn.msgSend(void, objc.sel("setAction:"), .{objc.sel("clickShortcutRecord:")});
    return btn.value;
}

// ── Blacklist delegate methods ────────────────────────────────────────────

fn blacklistNumRows(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    _tv: objc.c.id,
) callconv(.c) c_long {
    _ = _self;
    _ = _cmd;
    _ = _tv;
    return @intCast(state.g.config.blacklist_count);
}

fn blacklistViewForRow(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    _tv: objc.c.id,
    _col: objc.c.id,
    row: c_long,
) callconv(.c) objc.c.id {
    _ = _self;
    _ = _cmd;
    _ = _tv;
    _ = _col;
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    if (row < 0) return null;
    const idx: usize = @intCast(row);
    const entry = state.g.config.blacklistEntry(idx);

    const NSTextField = bridge.getClass("NSTextField");
    const tf = NSTextField.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithFrame:"), .{cgRect(4, 2, 550, 20)});
    tf.msgSend(void, objc.sel("setStringValue:"), .{bridge.nsString(entry)});
    tf.msgSend(void, objc.sel("setEditable:"), .{false});
    tf.msgSend(void, objc.sel("setBordered:"), .{false});
    tf.msgSend(void, objc.sel("setDrawsBackground:"), .{false});
    return tf.value;
}

// ── Notification observer ─────────────────────────────────────────────────

fn notifyShortcutChanged(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    _notif: objc.c.id,
) callconv(.c) void {
    _ = _self;
    _ = _cmd;
    _ = _notif;
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();
    // Reload keyboard table to show new shortcut text
    if (g_keyboard_table) |t| t.msgSend(void, objc.sel("reloadData"), .{});
}

// ── Action target methods ─────────────────────────────────────────────────

fn actToggleLaunch(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    sender: objc.c.id,
) callconv(.c) void {
    _ = _self;
    _ = _cmd;
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();
    const s = objc.Object{ .value = sender };
    const st = s.msgSend(c_long, objc.sel("state"), .{});
    state.g.config.launch_at_login = (st == 1);
    configureLaunchAtLogin(state.g.config.launch_at_login);
    saveConfig();
}

fn actChangeSensitivity(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    sender: objc.c.id,
) callconv(.c) void {
    _ = _self;
    _ = _cmd;
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();
    const s = objc.Object{ .value = sender };
    const idx = s.msgSend(c_long, objc.sel("indexOfSelectedItem"), .{});
    state.g.config.snap_sensitivity = switch (idx) {
        0 => 5,
        2 => 15,
        3 => 20,
        else => 10,
    };
    saveConfig();
}

fn actToggleGhost(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    sender: objc.c.id,
) callconv(.c) void {
    _ = _self;
    _ = _cmd;
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();
    const s = objc.Object{ .value = sender };
    const st = s.msgSend(c_long, objc.sel("state"), .{});
    state.g.config.show_ghost_window = (st == 1);
    saveConfig();
}

fn actChangeGap(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    sender: objc.c.id,
) callconv(.c) void {
    _ = _self;
    _ = _cmd;
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();
    const s = objc.Object{ .value = sender };
    const val = s.msgSend(f64, objc.sel("doubleValue"), .{});
    state.g.config.window_gap = @intFromFloat(@round(val));
    // Update label
    if (g_gap_lbl) |l| {
        var buf: [32]u8 = undefined;
        const txt = std.fmt.bufPrintZ(&buf, "{d} px", .{state.g.config.window_gap}) catch "0 px";
        l.msgSend(void, objc.sel("setStringValue:"), .{bridge.nsString(txt)});
    }
    saveConfig();
}

fn actChangeOpacity(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    sender: objc.c.id,
) callconv(.c) void {
    _ = _self;
    _ = _cmd;
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();
    const s = objc.Object{ .value = sender };
    const val = s.msgSend(f64, objc.sel("doubleValue"), .{});
    state.g.config.ghost_opacity = @floatCast(val / 100.0);
    state.g.config.ghost_opacity = @max(0.1, @min(1.0, state.g.config.ghost_opacity));
    // Update label
    if (g_opacity_lbl) |l| {
        var buf: [32]u8 = undefined;
        const pct: u32 = @intFromFloat(state.g.config.ghost_opacity * 100.0);
        const txt = std.fmt.bufPrintZ(&buf, "{d}%", .{pct}) catch "30%";
        l.msgSend(void, objc.sel("setStringValue:"), .{bridge.nsString(txt)});
    }
    saveConfig();
}

fn actAddBlacklist(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    _sender: objc.c.id,
) callconv(.c) void {
    _ = _self;
    _ = _cmd;
    _ = _sender;
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    // Use NSOpenPanel to pick an .app bundle
    const NSOpenPanel = bridge.getClass("NSOpenPanel");
    const panel = NSOpenPanel.msgSend(objc.Object, objc.sel("openPanel"), .{});
    panel.msgSend(void, objc.sel("setAllowsMultipleSelection:"), .{false});
    panel.msgSend(void, objc.sel("setCanChooseDirectories:"), .{false});
    panel.msgSend(void, objc.sel("setCanChooseFiles:"), .{true});

    // Set allowed content types to apps (macOS 12+) or fallback to allowedFileTypes
    const NSURL = bridge.getClass("NSURL");
    const apps_url = NSURL.msgSend(objc.Object, objc.sel("fileURLWithPath:"), .{bridge.nsString("/Applications")});
    panel.msgSend(void, objc.sel("setDirectoryURL:"), .{apps_url});

    // allowedFileTypes = @[@"app"]  (deprecated but works on all macOS 13)
    const NSArray = bridge.getClass("NSArray");
    const types_arr = NSArray.msgSend(objc.Object, objc.sel("arrayWithObject:"), .{bridge.nsString("app")});
    panel.msgSend(void, objc.sel("setAllowedFileTypes:"), .{types_arr});

    // runModal returns NSModalResponseOK = 1
    const result = panel.msgSend(c_long, objc.sel("runModal"), .{});
    if (result != 1) return;

    const urls = panel.msgSend(objc.Object, objc.sel("URLs"), .{});
    const first = urls.msgSend(objc.Object, objc.sel("firstObject"), .{});
    if (first.value == null) return;

    const NSBundle = bridge.getClass("NSBundle");
    const bundle = NSBundle.msgSend(objc.Object, objc.sel("bundleWithURL:"), .{first});
    if (bundle.value == null) return;

    const bid_ns = bundle.msgSend(objc.Object, objc.sel("bundleIdentifier"), .{});
    if (bid_ns.value == null) return;

    var bid_buf: [256]u8 = undefined;
    const bid = bridge.zigString(bid_ns, &bid_buf);
    if (bid.len == 0) return;

    if (!state.g.config.isBlacklisted(bid)) {
        _ = state.g.config.addToBlacklist(bid);
        saveConfig();
    }

    if (g_blacklist_table) |t| t.msgSend(void, objc.sel("reloadData"), .{});
}

fn actRemoveBlacklist(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    _sender: objc.c.id,
) callconv(.c) void {
    _ = _self;
    _ = _cmd;
    _ = _sender;
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    if (g_blacklist_table) |t| {
        const sel_row = t.msgSend(c_long, objc.sel("selectedRow"), .{});
        if (sel_row < 0) return;
        state.g.config.removeFromBlacklist(@intCast(sel_row));
        saveConfig();
        t.msgSend(void, objc.sel("reloadData"), .{});
    }
}

fn actClickShortcutRecord(
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
    if (tag < 0 or tag >= @as(c_long, constants.action_count)) return;

    if (g_window) |win| {
        shortcut_rec.show(win, @intCast(tag));
    }
}

fn actResetShortcutDefaults(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    _sender: objc.c.id,
) callconv(.c) void {
    _ = _self;
    _ = _cmd;
    _ = _sender;
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    // Restore all shortcuts to defaults
    state.g.config.shortcuts = config_mod.default_shortcuts;
    saveConfig();

    // Reload the keyboard table to reflect the reset
    if (g_keyboard_table) |t| t.msgSend(void, objc.sel("reloadData"), .{});

    log.info("settings: reset shortcuts to defaults", .{});
}

// ── Launch at login (SMAppService, macOS 13+) ─────────────────────────────

extern "c" fn SMAppServiceMainApp() ?*anyopaque;
extern "c" fn SMAppServiceRegister(svc: *anyopaque) c_int;
extern "c" fn SMAppServiceUnregister(svc: *anyopaque) c_int;

fn configureLaunchAtLogin(enable: bool) void {
    // Try SMAppService if available (macOS 13+)
    const NSBundle = bridge.getClass("NSBundle");
    const main_bundle = NSBundle.msgSend(objc.Object, objc.sel("mainBundle"), .{});
    _ = main_bundle;

    // Use ObjC-based SMAppService
    if (objc.getClass("SMAppService")) |cls| {
        const svc = cls.msgSend(objc.Object, objc.sel("mainAppService"), .{});
        if (enable) {
            _ = svc.msgSend(bool, objc.sel("registerAndReturnError:"), .{@as(?*anyopaque, null)});
        } else {
            _ = svc.msgSend(bool, objc.sel("unregisterAndReturnError:"), .{@as(?*anyopaque, null)});
        }
    } else {
        log.warn("settings: SMAppService unavailable – launch at login not set", .{});
    }
}

// ── Geometry helpers ──────────────────────────────────────────────────────

const CGPoint = extern struct { x: f64, y: f64 };
const CGSize = extern struct { width: f64, height: f64 };
const CGRect = extern struct { origin: CGPoint, size: CGSize };

fn cgRect(x: f64, y: f64, w: f64, h: f64) CGRect {
    return .{ .origin = .{ .x = x, .y = y }, .size = .{ .width = w, .height = h } };
}
