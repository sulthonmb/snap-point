//! Global AppState singleton.
//! The CGEventTap callback is a plain C function pointer – it cannot
//! capture Zig closures.  All mutable state lives here so the callback
//! can access it through the module.

const std = @import("std");
const config_mod = @import("config.zig");
const constants = @import("constants.zig");
const display_mod = @import("../platform/display.zig");
const hotkey_mod = @import("../platform/hotkey.zig");
const restore_mod = @import("../engine/restore.zig");
const zone_mod = @import("../engine/zone.zig");
const geo = @import("../util/geometry.zig");

// Import UI modules (Phase 3). We only need the types here.
const ghost_mod = @import("../ui/ghost_window.zig");
const status_mod = @import("../ui/status_bar.zig");
// Phase 4 UI modules
const settings_mod = @import("../ui/settings_window.zig");
const onboarding_mod = @import("../ui/onboarding.zig");

// ── Drag tracking ─────────────────────────────────────────────────────────

pub const DragState = struct {
    active: bool = false,
    start: geo.Point = .{},
    threshold_passed: bool = false,
    did_restore: bool = false,
    zone: zone_mod.ZoneType = .none,
};

// ── AppState ──────────────────────────────────────────────────────────────

pub const AppState = struct {
    config: config_mod.Config,
    display_mgr: display_mod.DisplayManager,
    hotkey_mgr: hotkey_mod.HotkeyManager,
    restore_store: restore_mod.RestoreStore,
    drag: DragState,
};

/// The one-and-only AppState instance (read/written on main thread).
pub var g: AppState = undefined;

/// Ghost window instance.  Initialised in main() after NSApplication.init.
/// Optional so it gracefully degrades if ObjC init fails.
pub var g_ghost: ?ghost_mod.GhostWindow = null;

/// Status bar instance.  Initialised in main() after NSApplication.init.
pub var g_status_bar: ?status_mod.StatusBar = null;

/// Settings window (Phase 4).  Initialised lazily on first open.
pub var g_settings: ?settings_mod.SettingsWindow = null;

/// Onboarding window (Phase 4).  Shown on first launch.
pub var g_onboarding: ?onboarding_mod.OnboardingWindow = null;

/// Initialise `g` from loaded config and displays.
pub fn init(
    config: config_mod.Config,
    display_mgr: display_mod.DisplayManager,
) void {
    g = AppState{
        .config = config,
        .display_mgr = display_mgr,
        .hotkey_mgr = hotkey_mod.HotkeyManager.init(&config),
        .restore_store = .{},
        .drag = .{},
    };
    // Re-point hotkey_mgr at g.config so future reloads work correctly.
    g.hotkey_mgr = hotkey_mod.HotkeyManager.init(&g.config);
}
