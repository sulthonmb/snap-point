//! AXUIElement wrapper: read and write window position/size.
//! Uses direct extern declarations against ApplicationServices.framework
//! (linked in build.zig) – no @cImport needed.

const std    = @import("std");
const objc   = @import("objc");
const log    = @import("../core/log.zig");
const bridge = @import("../objc/bridge.zig");
const geo    = @import("../util/geometry.zig");

// ── C ABI types ──────────────────────────────────────────────────────────

pub const AXUIElementRef = *anyopaque;
pub const AXValueRef     = *anyopaque;
pub const CFTypeRef      = *anyopaque;
pub const CFStringRef    = *anyopaque;
pub const CFArrayRef     = *anyopaque;
pub const AXError        = i32;
pub const pid_t          = i32;

// AXValueType enum values (AXValue.h)
pub const AXValueType = enum(u32) {
    illegal             = 0,
    cg_point            = 1,
    cg_size             = 2,
    cg_rect             = 3,
    cg_affine_transform = 4,
    ax_error            = 6,
    _,
};

// AXError codes (AXError.h)
pub const kAXErrorSuccess          : AXError =  0;
pub const kAXErrorFailure          : AXError = -25200;
pub const kAXErrorIllegalArgument  : AXError = -25201;
pub const kAXErrorInvalidUIElement : AXError = -25202;
pub const kAXErrorCannotComplete   : AXError = -25204;
pub const kAXErrorNotImplemented   : AXError = -25205;
pub const kAXErrorAPIDisabled      : AXError = -25211;

// ── Extern declarations ──────────────────────────────────────────────────

extern fn AXIsProcessTrusted() bool;
extern fn AXUIElementCreateSystemWide() AXUIElementRef;
extern fn AXUIElementCreateApplication(pid: pid_t) AXUIElementRef;
extern fn AXUIElementCopyAttributeValue(
    element:   AXUIElementRef,
    attribute: CFStringRef,
    value:     *CFTypeRef,
) AXError;
extern fn AXUIElementSetAttributeValue(
    element:   AXUIElementRef,
    attribute: CFStringRef,
    value:     CFTypeRef,
) AXError;
extern fn AXValueCreate(valueType: AXValueType, valuePtr: *const anyopaque) AXValueRef;
extern fn AXValueGetValue(value: AXValueRef, valueType: AXValueType, valuePtr: *anyopaque) bool;
extern fn CFRelease(cf: CFTypeRef) void;

// ── Attribute name helpers ───────────────────────────────────────────────
// NSString and CFStringRef are toll-free bridged on macOS.

fn attr(name: [:0]const u8) CFStringRef {
    const ns = bridge.nsString(name);
    return @ptrCast(ns.value);
}

// ── AX error handling ────────────────────────────────────────────────────

pub const AXErr = error{
    Failure,
    IllegalArgument,
    InvalidUIElement,
    CannotComplete,
    NotImplemented,
    APIDisabled,
    Unknown,
};

fn checkAXError(code: AXError) AXErr!void {
    return switch (code) {
        kAXErrorSuccess        => {},
        kAXErrorIllegalArgument=> AXErr.IllegalArgument,
        kAXErrorInvalidUIElement => AXErr.InvalidUIElement,
        kAXErrorCannotComplete => AXErr.CannotComplete,
        kAXErrorNotImplemented => AXErr.NotImplemented,
        kAXErrorAPIDisabled    => AXErr.APIDisabled,
        else                   => AXErr.Failure,
    };
}

// ── WindowController ─────────────────────────────────────────────────────

pub const WindowController = struct {
    ax_window: AXUIElementRef,  // focused window element (caller owns ref)
    original_frame: ?geo.Rect,  // stored before first snap (for restore)

    /// Obtain a controller for the frontmost window of the frontmost app.
    /// Returns error.APIDisabled if Accessibility is not granted.
    pub fn getFocusedWindow() !WindowController {
        const pool = objc.AutoreleasePool.init();
        defer pool.deinit();

        const system_wide = AXUIElementCreateSystemWide();
        defer CFRelease(system_wide);

        // Get focused application element
        var app_ref: CFTypeRef = undefined;
        try checkAXError(AXUIElementCopyAttributeValue(
            system_wide,
            attr("AXFocusedApplication"),
            &app_ref,
        ));
        defer CFRelease(app_ref);

        // Get focused window element
        var window_ref: CFTypeRef = undefined;
        const ax_app: AXUIElementRef = @ptrCast(app_ref);
        try checkAXError(AXUIElementCopyAttributeValue(
            ax_app,
            attr("AXFocusedWindow"),
            &window_ref,
        ));
        // Caller takes ownership of window_ref; don't CFRelease here.

        return .{
            .ax_window      = @ptrCast(window_ref),
            .original_frame = null,
        };
    }

    /// Read the current position and size of the window.
    /// Returns coordinates in CG space (top-left origin of primary display).
    pub fn getFrame(self: *WindowController) !geo.Rect {
        const pool = objc.AutoreleasePool.init();
        defer pool.deinit();

        // Read position (CGPoint)
        var pos_ref: CFTypeRef = undefined;
        try checkAXError(AXUIElementCopyAttributeValue(
            self.ax_window,
            attr("AXPosition"),
            &pos_ref,
        ));
        defer CFRelease(pos_ref);

        var cg_point: geo.CGPoint = .{ .x = 0, .y = 0 };
        _ = AXValueGetValue(@ptrCast(pos_ref), .cg_point, &cg_point);

        // Read size (CGSize)
        var size_ref: CFTypeRef = undefined;
        try checkAXError(AXUIElementCopyAttributeValue(
            self.ax_window,
            attr("AXSize"),
            &size_ref,
        ));
        defer CFRelease(size_ref);

        var cg_size: geo.CGSize = .{ .width = 0, .height = 0 };
        _ = AXValueGetValue(@ptrCast(size_ref), .cg_size, &cg_size);

        return geo.Rect{
            .origin = .{ .x = cg_point.x, .y = cg_point.y },
            .size   = .{ .width = cg_size.width, .height = cg_size.height },
        };
    }

    /// Move and resize the window to `rect` (CG coordinates: top-left origin).
    pub fn setFrame(self: *WindowController, rect: geo.Rect) !void {
        const pool = objc.AutoreleasePool.init();
        defer pool.deinit();

        // Set position
        var cg_point = geo.CGPoint{ .x = rect.origin.x, .y = rect.origin.y };
        const pos_val = AXValueCreate(.cg_point, &cg_point);
        defer CFRelease(pos_val);
        try checkAXError(AXUIElementSetAttributeValue(
            self.ax_window,
            attr("AXPosition"),
            pos_val,
        ));

        // Set size
        var cg_size = geo.CGSize{ .width = rect.size.width, .height = rect.size.height };
        const size_val = AXValueCreate(.cg_size, &cg_size);
        defer CFRelease(size_val);
        try checkAXError(AXUIElementSetAttributeValue(
            self.ax_window,
            attr("AXSize"),
            size_val,
        ));

        log.debug("accessibility: setFrame x={d:.1} y={d:.1} w={d:.1} h={d:.1}", .{
            rect.origin.x, rect.origin.y,
            rect.size.width, rect.size.height,
        });
    }

    /// Store a snapshot of the current frame to enable restore-on-unsnap.
    pub fn storeOriginalFrame(self: *WindowController) void {
        self.original_frame = self.getFrame() catch null;
    }

    /// Restore the window to its pre-snap dimensions.
    pub fn restoreOriginalFrame(self: *WindowController) !void {
        if (self.original_frame) |frame| {
            try self.setFrame(frame);
            log.debug("accessibility: restored original frame", .{});
        }
    }

    /// Get the bundle identifier of the application owning this window.
    /// Caller provides `buf` to hold the UTF-8 result.
    pub fn getBundleIdentifier(self: *WindowController, buf: []u8) []const u8 {
        _ = self;
        // TODO Phase 2: properly query AXUIElementGetPid + NSRunningApplication
        // For now return an empty string (no app is blacklisted).
        _ = buf;
        return "";
    }

    /// Release the AXUIElement reference.  Call when done with this controller.
    pub fn deinit(self: *WindowController) void {
        CFRelease(self.ax_window);
    }
};
