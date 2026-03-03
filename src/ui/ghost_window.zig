//! Ghost window: a translucent overlay that previews where a window will snap.
//!
//! Uses a borderless NSWindow with an NSVisualEffectView content view.
//! Level is set above normal windows (status-bar level) so it appears
//! on top of the window being dragged.
//!
//! Coordinate note: show() accepts a rect in CG coordinates and a
//! `primary_height` value so it can convert to NS screen coordinates
//! (bottom-left origin) for NSWindow.setFrame:display:.

const std    = @import("std");
const objc   = @import("objc");
const bridge = @import("../objc/bridge.zig");
const appkit = @import("../objc/appkit.zig");
const geo    = @import("../util/geometry.zig");
const log    = @import("../core/log.zig");

// ── Collection-behaviour flags ──────────────────────────────────────────
// NSWindowCollectionBehaviorCanJoinAllSpaces | Stationary | IgnoresCycle
const kCollectionBehavior: c_ulong = (1 | 16 | 64);

// ── GhostWindow ──────────────────────────────────────────────────────────

pub const GhostWindow = struct {
    window:      objc.Object,   // NSWindow (retained)
    effect_view: objc.Object,   // NSVisualEffectView (retained)
    initialized: bool = false,

    /// Create the ghost window.  Must be called on the main thread.
    pub fn init() GhostWindow {
        const pool = objc.AutoreleasePool.init();
        defer pool.deinit();

        // ── NSVisualEffectView ──────────────────────────────────────
        const VEV = bridge.getClass("NSVisualEffectView");
        const effect_view = VEV
            .msgSend(objc.Object, objc.sel("alloc"), .{})
            .msgSend(objc.Object, objc.sel("initWithFrame:"), .{
                geo.CGRect{ .origin = .{ .x = 0, .y = 0 },
                            .size   = .{ .width = 100, .height = 100 } },
            });

        // Material: HUDWindow = 23
        effect_view.msgSend(void, objc.sel("setMaterial:"), .{@as(c_long, 23)});
        // BlendingMode: behindWindow = 0
        effect_view.msgSend(void, objc.sel("setBlendingMode:"), .{@as(c_long, 0)});
        // State: active = 1
        effect_view.msgSend(void, objc.sel("setState:"), .{@as(c_long, 1)});
        effect_view.msgSend(void, objc.sel("setWantsLayer:"), .{true});

        // ── NSWindow ────────────────────────────────────────────────
        const NSWindow = bridge.getClass("NSWindow");
        const initial_rect = geo.CGRect{
            .origin = .{ .x = 0, .y = 0 },
            .size   = .{ .width = 100, .height = 100 },
        };
        const window = NSWindow
            .msgSend(objc.Object, objc.sel("alloc"), .{})
            .msgSend(
                objc.Object,
                objc.sel("initWithContentRect:styleMask:backing:defer:"),
                .{
                    initial_rect,
                    @as(c_ulong, 0),  // NSWindowStyleMaskBorderless
                    @as(c_ulong, 2),  // NSBackingStoreBuffered
                    false,
                },
            );

        // Transparent, non-opaque background
        const NSColor = bridge.getClass("NSColor");
        const clear = NSColor.msgSend(objc.Object, objc.sel("clearColor"), .{});
        window.msgSend(void, objc.sel("setBackgroundColor:"), .{clear});
        window.msgSend(void, objc.sel("setOpaque:"), .{false});

        // Window level: statusBar (25) so it floats above normal windows
        window.msgSend(void, objc.sel("setLevel:"), .{@as(c_int, 25)});

        // Don't steal mouse events
        window.msgSend(void, objc.sel("setIgnoresMouseEvents:"), .{true});

        // Appear on all spaces
        window.msgSend(void, objc.sel("setCollectionBehavior:"), .{kCollectionBehavior});

        // Rounded corners
        window.msgSend(void, objc.sel("setHasShadow:"), .{false});

        // Corner radius via layer (set after contentView is assigned)
        window.msgSend(void, objc.sel("setContentView:"), .{effect_view});

        // Apply a 12pt corner radius to the content view's layer
        const layer = effect_view.msgSend(objc.Object, objc.sel("layer"), .{});
        if (layer.value != null) {
            layer.msgSend(void, objc.sel("setCornerRadius:"), .{@as(f64, 12.0)});
            layer.msgSend(void, objc.sel("setMasksToBounds:"), .{true});
        }

        // Retain window so it outlives the autorelease pool
        _ = window.msgSend(objc.Object, objc.sel("retain"), .{});
        _ = effect_view.msgSend(objc.Object, objc.sel("retain"), .{});

        log.info("ghost_window: initialised", .{});
        return .{ .window = window, .effect_view = effect_view, .initialized = true };
    }

    /// Show the ghost window at `rect_cg` (CG coordinates).
    /// `primary_height` is the full pixel height of the primary display
    /// needed to convert from CG (top-left) to NS (bottom-left) coords.
    pub fn show(self: *GhostWindow, rect_cg: geo.Rect, primary_height: f64, opacity: f32) void {
        if (!self.initialized) return;

        const pool = objc.AutoreleasePool.init();
        defer pool.deinit();

        // Convert CG → NS screen coordinates
        const ns_rect = geo.cgToNS(rect_cg, primary_height);
        const frame = geo.CGRect{
            .origin = .{ .x = ns_rect.origin.x, .y = ns_rect.origin.y },
            .size   = .{ .width = ns_rect.size.width, .height = ns_rect.size.height },
        };

        self.window.msgSend(void, objc.sel("setFrame:display:"), .{ frame, false });
        self.window.msgSend(void, objc.sel("setAlphaValue:"), .{@as(f64, @floatCast(opacity))});
        self.window.msgSend(void, objc.sel("orderFrontRegardless"), .{});

        log.debug("ghost_window: show x={d:.0} y={d:.0} w={d:.0} h={d:.0}", .{
            ns_rect.origin.x, ns_rect.origin.y,
            ns_rect.size.width, ns_rect.size.height,
        });
    }

    /// Hide the ghost window instantly.
    pub fn hide(self: *GhostWindow) void {
        if (!self.initialized) return;
        const pool = objc.AutoreleasePool.init();
        defer pool.deinit();
        self.window.msgSend(void, objc.sel("orderOut:"), .{self.window});
    }

    /// True if the window is currently on screen.
    pub fn isVisible(self: *GhostWindow) bool {
        if (!self.initialized) return false;
        return self.window.msgSend(bool, objc.sel("isVisible"), .{});
    }

    /// Release ObjC references.
    pub fn deinit(self: *GhostWindow) void {
        if (!self.initialized) return;
        self.window.msgSend(void, objc.sel("release"), .{});
        self.effect_view.msgSend(void, objc.sel("release"), .{});
        self.initialized = false;
    }
};
