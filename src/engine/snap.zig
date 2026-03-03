//! Snap execution – Phase 2 implementation.
//! Ties together: focused window lookup → layout resolution → AX frame set.

const std           = @import("std");
const layout_engine = @import("layout.zig");
const zone_engine   = @import("zone.zig");
const accessibility = @import("../platform/accessibility.zig");
const display_mod   = @import("../platform/display.zig");
const config_mod    = @import("../core/config.zig");
const log           = @import("../core/log.zig");
const geo           = @import("../util/geometry.zig");
const timer         = @import("../util/timer.zig");

pub const Action = enum(u8) {
    snap_left_half            = 0,
    snap_right_half           = 1,
    snap_top_half             = 2,
    snap_bottom_half          = 3,
    snap_top_left_quarter     = 4,
    snap_top_right_quarter    = 5,
    snap_bottom_left_quarter  = 6,
    snap_bottom_right_quarter = 7,
    snap_first_third          = 8,
    snap_center_third         = 9,
    snap_last_third           = 10,
    snap_top_third            = 11,
    snap_middle_third         = 12,
    snap_bottom_third         = 13,
    snap_left_two_thirds      = 14,
    snap_right_two_thirds     = 15,
    snap_top_two_thirds       = 16,
    snap_bottom_two_thirds    = 17,
    snap_top_left_sixth       = 18,
    snap_top_center_sixth     = 19,
    snap_top_right_sixth      = 20,
    snap_bottom_left_sixth    = 21,
    snap_bottom_center_sixth  = 22,
    snap_bottom_right_sixth   = 23,
    snap_almost_maximize      = 24,
    throw_to_next_display     = 25,
    throw_to_prev_display     = 26,
};

/// Execute `action` on the frontmost window.
/// `display_mgr` and `config` must be valid and initialised.
pub fn executeSnap(
    action:      Action,
    display_mgr: *display_mod.DisplayManager,
    config:      *config_mod.Config,
) !void {
    const t0 = timer.now();

    // Get focused window
    var wc = try accessibility.WindowController.getFocusedWindow();
    defer wc.deinit();

    // Check blacklist
    var bundle_buf: [256]u8 = undefined;
    const bundle_id = wc.getBundleIdentifier(&bundle_buf);
    if (config.isBlacklisted(bundle_id)) {
        log.debug("snap: skipping blacklisted app {s}", .{bundle_id});
        return;
    }

    // Store original frame for later restore
    wc.storeOriginalFrame();

    // Determine target display and layout index
    const layout_idx: usize = @intFromEnum(action);
    const current_frame = try wc.getFrame();

    const target_display = if (action == .throw_to_next_display)
        display_mgr.nextDisplay(
            (display_mgr.displayForRect(current_frame) orelse
                display_mgr.primaryDisplay() orelse return).display_id
        ) orelse return
    else if (action == .throw_to_prev_display)
        display_mgr.prevDisplay(
            (display_mgr.displayForRect(current_frame) orelse
                display_mgr.primaryDisplay() orelse return).display_id
        ) orelse return
    else
        display_mgr.displayForRect(current_frame) orelse
        display_mgr.primaryDisplay() orelse return;

    // Resolve layout to absolute CG coordinates
    const target_rect = layout_engine.resolve(
        layout_engine.layouts[layout_idx],
        target_display.safe_area,
        config.window_gap,
    );

    // Apply
    try wc.setFrame(target_rect);

    log.info("snap: action={d} elapsed={d:.1}ms", .{
        layout_idx, timer.elapsedMillis(t0),
    });
}
