//! NSStatusItem menu bar icon + full NSMenu.
//!
//! Architecture:
//!   • A small ObjC class "SnapMenuTarget" is registered once.
//!     Its single method "-performAction:(id)sender" reads the sender's
//!     NSInteger tag and dispatches to the appropriate engine function.
//!   • A second class "SnapMenuDelegate" implements NSMenuDelegate so we
//!     can update the "Ignore [App]" item each time the menu opens.
//!
//! Menu layout:
//!   Left Half … Almost Maximize   (5 top-level items)
//!   ─────────────────────────────
//!   ▸ Quarters   ▸ Thirds   ▸ Two-Thirds   ▸ Sixths
//!   ─────────────────────────────
//!   Move to Next Display
//!   Move to Prev Display
//!   ─────────────────────────────
//!   Ignore "FrontmostApp"
//!   ─────────────────────────────
//!   Settings…   Quit SnapPoint

const std = @import("std");
const objc = @import("objc");
const bridge = @import("../objc/bridge.zig");
const log = @import("../core/log.zig");
const state_mod = @import("../core/state.zig");
const snap_mod = @import("../engine/snap.zig");
const app_mod = @import("../core/app.zig");
const layout_engine = @import("../engine/layout.zig");
const settings_mod = @import("settings_window.zig");
const updater = @import("../platform/updater.zig");

// ── Special menu tags ────────────────────────────────────────────────────
const TAG_IGNORE_APP: c_long = 100;
const TAG_SETTINGS: c_long = 200;
const TAG_CHECK_UPDATES: c_long = 201;
const TAG_QUIT: c_long = 202;

// ── NSEventModifierFlags ─────────────────────────────────────────────────
const NSEventModifierFlagShift: c_ulong = 0x02_0000;
const NSEventModifierFlagControl: c_ulong = 0x04_0000;
const NSEventModifierFlagOption: c_ulong = 0x08_0000;
const NSEventModifierFlagCommand: c_ulong = 0x10_0000;

// ── Arrow key equivalents for NSMenuItem ────────────────────────────────
// These are the Unicode private-use "function key" characters macOS uses.
const KEY_UP: []const u8 = "\u{F700}";
const KEY_DOWN: []const u8 = "\u{F701}";
const KEY_LEFT: []const u8 = "\u{F702}";
const KEY_RIGHT: []const u8 = "\u{F703}";
const KEY_RETURN: []const u8 = "\r";

// ── StatusBar ────────────────────────────────────────────────────────────

pub const StatusBar = struct {
    status_item: objc.Object, // NSStatusItem  (retained)
    menu: objc.Object, // NSMenu        (retained)
    target: objc.Object, // SnapMenuTarget (retained)
    ignore_item: objc.Object, // NSMenuItem for "Ignore [App]" (retained)

    /// Create and install the status bar item.  Call on main thread after
    /// NSApplication is initialised.
    pub fn init() StatusBar {
        const pool = objc.AutoreleasePool.init();
        defer pool.deinit();

        // Register ObjC helper classes (idempotent – checked internally)
        registerMenuTarget();
        registerMenuDelegate();

        // Allocate the target instance that receives menu actions
        const TargetClass = bridge.getClass("SnapMenuTarget");
        const DelegateClass = bridge.getClass("SnapMenuDelegate");
        const target = TargetClass.msgSend(objc.Object, objc.sel("alloc"), .{})
            .msgSend(objc.Object, objc.sel("init"), .{});
        const delegate = DelegateClass.msgSend(objc.Object, objc.sel("alloc"), .{})
            .msgSend(objc.Object, objc.sel("init"), .{});
        _ = target.msgSend(objc.Object, objc.sel("retain"), .{});
        _ = delegate.msgSend(objc.Object, objc.sel("retain"), .{});

        // Build menu
        const NSMenu = bridge.getClass("NSMenu");
        const menu = NSMenu.msgSend(objc.Object, objc.sel("alloc"), .{})
            .msgSend(objc.Object, objc.sel("init"), .{});
        _ = menu.msgSend(objc.Object, objc.sel("retain"), .{});
        menu.msgSend(void, objc.sel("setAutoenablesItems:"), .{false});
        menu.msgSend(void, objc.sel("setDelegate:"), .{delegate});

        const ignore_item = populateMenu(menu, target);
        _ = ignore_item.msgSend(objc.Object, objc.sel("retain"), .{});

        // NSStatusBar.systemStatusBar → statusItemWithLength:(-1)
        const NSStatusBar = bridge.getClass("NSStatusBar");
        const status_bar = NSStatusBar
            .msgSend(objc.Object, objc.sel("systemStatusBar"), .{});
        const status_item = status_bar
            .msgSend(objc.Object, objc.sel("statusItemWithLength:"), .{@as(f64, -1.0)});
        _ = status_item.msgSend(objc.Object, objc.sel("retain"), .{});

        // Set icon using SF Symbols (macOS 13+)
        const button = status_item.msgSend(objc.Object, objc.sel("button"), .{});
        setStatusItemImage(button);

        status_item.msgSend(void, objc.sel("setMenu:"), .{menu});

        log.info("status_bar: installed", .{});
        return .{
            .status_item = status_item,
            .menu = menu,
            .target = target,
            .ignore_item = ignore_item,
        };
    }

    /// Update the "Ignore [App]" menu item title to the current frontmost app.
    /// Called from SnapMenuDelegate.menuWillOpen: and can be called manually.
    pub fn updateIgnoreItem(self: *StatusBar) void {
        const pool = objc.AutoreleasePool.init();
        defer pool.deinit();

        const app_name = frontmostAppName();
        var title_buf: [256]u8 = undefined;
        var buf: [128]u8 = undefined;
        const name_str = bridge.zigString(app_name, &buf);
        const title = std.fmt.bufPrintZ(&title_buf, "Ignore \"{s}\"", .{name_str}) catch "Ignore App";
        self.ignore_item.msgSend(void, objc.sel("setTitle:"), .{bridge.nsString(title)});
    }
};

// ── Menu construction ─────────────────────────────────────────────────────

/// Build all menu items into `menu`.  Returns the "Ignore [App]" item.
fn populateMenu(menu: objc.Object, target: objc.Object) objc.Object {
    const ctrl_opt: c_ulong = NSEventModifierFlagControl | NSEventModifierFlagOption;
    const ctrl_opt_shift: c_ulong = ctrl_opt | NSEventModifierFlagShift;
    const ctrl_opt_cmd: c_ulong = ctrl_opt | NSEventModifierFlagCommand;

    // ── Top-level standard layouts ──────────────────────────────────
    addItem(menu, "Left Half", KEY_LEFT, ctrl_opt, 0, target);
    addItem(menu, "Right Half", KEY_RIGHT, ctrl_opt, 1, target);
    addItem(menu, "Top Half", KEY_UP, ctrl_opt, 2, target);
    addItem(menu, "Bottom Half", KEY_DOWN, ctrl_opt, 3, target);
    addItem(menu, "Almost Maximize", KEY_RETURN, ctrl_opt, 24, target);

    addSeparator(menu);

    // ── Quarters submenu ─────────────────────────────────────────────
    const QM = makeSubmenu("Quarters");
    addItem(QM, "Top-Left", "u", ctrl_opt, 4, target);
    addItem(QM, "Top-Right", "i", ctrl_opt, 5, target);
    addItem(QM, "Bottom-Left", "j", ctrl_opt, 6, target);
    addItem(QM, "Bottom-Right", "k", ctrl_opt, 7, target);
    addSubmenu(menu, "Quarters", QM, target);

    // ── Thirds submenu ───────────────────────────────────────────────
    const TM = makeSubmenu("Thirds");
    addItem(TM, "First Third", "d", ctrl_opt, 8, target);
    addItem(TM, "Center Third", "f", ctrl_opt, 9, target);
    addItem(TM, "Last Third", "g", ctrl_opt, 10, target);
    addItem(TM, "Top Third", KEY_UP, ctrl_opt_shift, 11, target);
    addItem(TM, "Middle Third", KEY_RIGHT, ctrl_opt_shift, 12, target);
    addItem(TM, "Bottom Third", KEY_DOWN, ctrl_opt_shift, 13, target);
    addSubmenu(menu, "Thirds", TM, target);

    // ── Two-Thirds submenu ───────────────────────────────────────────
    const TWM = makeSubmenu("Two-Thirds");
    addItem(TWM, "Left Two-Thirds", "e", ctrl_opt, 14, target);
    addItem(TWM, "Right Two-Thirds", "t", ctrl_opt, 15, target);
    addItem(TWM, "Top Two-Thirds", "u", ctrl_opt_shift, 16, target);
    addItem(TWM, "Bottom Two-Thirds", "j", ctrl_opt_shift, 17, target);
    addSubmenu(menu, "Two-Thirds", TWM, target);

    // ── Sixths submenu ───────────────────────────────────────────────
    const SM = makeSubmenu("Sixths");
    addItem(SM, "Top-Left", "1", ctrl_opt_shift, 18, target);
    addItem(SM, "Top-Center", "2", ctrl_opt_shift, 19, target);
    addItem(SM, "Top-Right", "3", ctrl_opt_shift, 20, target);
    addItem(SM, "Bottom-Left", "4", ctrl_opt_shift, 21, target);
    addItem(SM, "Bottom-Center", "5", ctrl_opt_shift, 22, target);
    addItem(SM, "Bottom-Right", "6", ctrl_opt_shift, 23, target);
    addSubmenu(menu, "Sixths", SM, target);

    addSeparator(menu);

    // ── Multi-monitor ────────────────────────────────────────────────
    addItem(menu, "Move to Next Display", KEY_RIGHT, ctrl_opt_cmd, 25, target);
    addItem(menu, "Move to Prev Display", KEY_LEFT, ctrl_opt_cmd, 26, target);

    addSeparator(menu);

    // ── Ignore frontmost app ─────────────────────────────────────────
    const ignore_item = makeItem("Ignore App", "", 0, TAG_IGNORE_APP, target);
    menu.msgSend(void, objc.sel("addItem:"), .{ignore_item});

    addSeparator(menu);

    // ── Utility items ────────────────────────────────────────────────
    addItem(menu, "Settings\u{2026}", ",", NSEventModifierFlagCommand, TAG_SETTINGS, target);
    addItem(menu, "Check for Updates\u{2026}", "", 0, TAG_CHECK_UPDATES, target);
    addItem(menu, "Quit SnapPoint", "q", NSEventModifierFlagCommand, TAG_QUIT, target);

    return ignore_item;
}

// ── NSMenuItem helpers ────────────────────────────────────────────────────

fn makeItem(
    title: []const u8,
    key_equiv: []const u8,
    mod_mask: c_ulong,
    tag: c_long,
    target: objc.Object,
) objc.Object {
    const NSMenuItem = bridge.getClass("NSMenuItem");
    const item = NSMenuItem
        .msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(
        objc.Object,
        objc.sel("initWithTitle:action:keyEquivalent:"),
        .{
            bridge.nsString(title),
            objc.sel("performAction:"),
            bridge.nsString(key_equiv),
        },
    );
    item.msgSend(void, objc.sel("setKeyEquivalentModifierMask:"), .{mod_mask});
    item.msgSend(void, objc.sel("setTag:"), .{tag});
    item.msgSend(void, objc.sel("setTarget:"), .{target});
    item.msgSend(void, objc.sel("setEnabled:"), .{true});
    return item;
}

fn addItem(
    menu: objc.Object,
    title: []const u8,
    key_equiv: []const u8,
    mod_mask: c_ulong,
    tag: c_long,
    target: objc.Object,
) void {
    const item = makeItem(title, key_equiv, mod_mask, tag, target);
    menu.msgSend(void, objc.sel("addItem:"), .{item});
}

fn addSeparator(menu: objc.Object) void {
    const NSMenuItem = bridge.getClass("NSMenuItem");
    const sep = NSMenuItem.msgSend(objc.Object, objc.sel("separatorItem"), .{});
    menu.msgSend(void, objc.sel("addItem:"), .{sep});
}

fn makeSubmenu(title: []const u8) objc.Object {
    const NSMenu = bridge.getClass("NSMenu");
    const m = NSMenu
        .msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithTitle:"), .{bridge.nsString(title)});
    m.msgSend(void, objc.sel("setAutoenablesItems:"), .{false});
    return m;
}

fn addSubmenu(
    parent: objc.Object,
    title: []const u8,
    submenu: objc.Object,
    target: objc.Object,
) void {
    const NSMenuItem = bridge.getClass("NSMenuItem");
    const container_item = NSMenuItem
        .msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(
        objc.Object,
        objc.sel("initWithTitle:action:keyEquivalent:"),
        .{
            bridge.nsString(title),
            objc.sel(""),
            bridge.nsString(""),
        },
    );
    _ = target; // submenus don't need a direct target
    container_item.msgSend(void, objc.sel("setEnabled:"), .{true});
    container_item.msgSend(void, objc.sel("setSubmenu:"), .{submenu});
    parent.msgSend(void, objc.sel("addItem:"), .{container_item});
}

// ── Status item icon ──────────────────────────────────────────────────────

fn setStatusItemImage(button: objc.Object) void {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSImage = bridge.getClass("NSImage");

    // Try SF Symbols first (macOS 12+)
    const sym_name = bridge.nsString("rectangle.split.2x1");
    const a11y_desc = bridge.nsString("SnapPoint");

    // imageWithSystemSymbolName:accessibilityDescription: is macOS 12+
    // Check availability via respondsToSelector:
    if (NSImage.msgSend(
        bool,
        objc.sel("respondsToSelector:"),
        .{objc.sel("imageWithSystemSymbolName:accessibilityDescription:")},
    )) {
        const img = NSImage.msgSend(
            objc.Object,
            objc.sel("imageWithSystemSymbolName:accessibilityDescription:"),
            .{ sym_name, a11y_desc },
        );
        if (img.value != null) {
            // Set template so macOS tints it for dark/light mode
            img.msgSend(void, objc.sel("setTemplate:"), .{true});
            button.msgSend(void, objc.sel("setImage:"), .{img});
            button.msgSend(void, objc.sel("setToolTip:"), .{bridge.nsString("SnapPoint")});
            return;
        }
    }

    // Fallback: set a title text
    button.msgSend(void, objc.sel("setTitle:"), .{bridge.nsString("⊞")});
}

// ── Frontmost app name ────────────────────────────────────────────────────

/// Return the NSString localizedName of the frontmost application.
fn frontmostAppName() objc.Object {
    const ws = bridge.sharedWorkspace();
    const front_app = ws.msgSend(
        objc.Object,
        objc.sel("frontmostApplication"),
        .{},
    );
    if (front_app.value == null) {
        return bridge.nsString("App");
    }
    return front_app.msgSend(objc.Object, objc.sel("localizedName"), .{});
}

/// Return the NSString bundleIdentifier of the frontmost application.
fn frontmostBundleId() objc.Object {
    const ws = bridge.sharedWorkspace();
    const front_app = ws.msgSend(
        objc.Object,
        objc.sel("frontmostApplication"),
        .{},
    );
    if (front_app.value == null) {
        return bridge.nsString("");
    }
    return front_app.msgSend(objc.Object, objc.sel("bundleIdentifier"), .{});
}

// ── ObjC class registration ───────────────────────────────────────────────

var snap_menu_target_registered = false;
var snap_menu_delegate_registered = false;

/// Register "SnapMenuTarget" with a single method:
///   - (void)performAction:(id)sender
/// The sender is the NSMenuItem whose tag encodes the action index.
fn registerMenuTarget() void {
    if (snap_menu_target_registered) return;
    snap_menu_target_registered = true;

    const NSObject = objc.getClass("NSObject") orelse
        @panic("NSObject class not found");

    const TargetClass = objc.allocateClassPair(NSObject, "SnapMenuTarget") orelse {
        // Class already registered (e.g., if init is called twice)
        return;
    };

    _ = TargetClass.addMethod("performAction:", menuPerformAction);

    objc.registerClassPair(TargetClass);
}

/// Register "SnapMenuDelegate" implementing NSMenuDelegate:
///   - (void)menuWillOpen:(NSMenu *)menu
fn registerMenuDelegate() void {
    if (snap_menu_delegate_registered) return;
    snap_menu_delegate_registered = true;

    const NSObject = objc.getClass("NSObject") orelse
        @panic("NSObject class not found");

    const DelClass = objc.allocateClassPair(NSObject, "SnapMenuDelegate") orelse {
        return;
    };

    _ = DelClass.addMethod("menuWillOpen:", menuWillOpen);

    objc.registerClassPair(DelClass);
}

// ── ObjC method implementations ──────────────────────────────────────────
// Signatures must match exactly: (objc.c.id, objc.c.SEL, ...) callconv(.c)
// addMethod checks param[0] == c.id and param[1] == c.SEL at comptime.

/// ObjC method: -[SnapMenuTarget performAction:(id)sender]
fn menuPerformAction(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    sender: objc.c.id,
) callconv(.c) void {
    _ = _self;
    _ = _cmd;

    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const sender_obj = objc.Object{ .value = sender };
    const tag = sender_obj.msgSend(c_long, "tag", .{});

    if (tag >= 0 and tag <= 26) {
        // Snap or throw action
        const action: snap_mod.Action = @enumFromInt(@as(u8, @intCast(tag)));
        snap_mod.executeSnap(action, &state_mod.g.display_mgr, &state_mod.g.config) catch |e| {
            log.warn("status_bar: snap failed: {any}", .{e});
        };
    } else if (tag == TAG_IGNORE_APP) {
        // Add frontmost app to blacklist
        var buf: [256]u8 = undefined;
        const bundle_ns = frontmostBundleId();
        const bundle_id = bridge.zigString(bundle_ns, &buf);
        if (bundle_id.len > 0) {
            _ = state_mod.g.config.addToBlacklist(bundle_id);
            log.info("status_bar: blacklisted {s}", .{bundle_id});
        }
    } else if (tag == TAG_SETTINGS) {
        // Create settings window on first open, then show it
        if (state_mod.g_settings == null) {
            state_mod.g_settings = settings_mod.SettingsWindow.init();
        }
        if (state_mod.g_settings) |*sw| sw.show();
    } else if (tag == TAG_CHECK_UPDATES) {
        updater.checkForUpdates();
    } else if (tag == TAG_QUIT) {
        app_mod.quit();
    }
}

/// ObjC method: -[SnapMenuDelegate menuWillOpen:(NSMenu *)menu]
fn menuWillOpen(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    _menu: objc.c.id,
) callconv(.c) void {
    _ = _self;
    _ = _cmd;
    _ = _menu;

    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    // Update "Ignore [App]" title
    if (state_mod.g_status_bar) |*sb| {
        sb.updateIgnoreItem();
    }
}
