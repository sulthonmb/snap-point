//! Application lifecycle: NSApplication bootstrap and run loop.

const objc   = @import("objc");
const log    = @import("log.zig");
const bridge = @import("../objc/bridge.zig");

const ActivationPolicy = enum(c_long) {
    regular    = 0,
    accessory  = 1,  // menu-bar only – no Dock icon
    prohibited = 2,
};

/// Initialise NSApplication as an agent app.
/// Must be called on the main thread inside an AutoreleasePool.
pub fn init() !void {
    log.info("app: NSApplication.sharedApplication", .{});
    const app = bridge.sharedApplication();
    const ok  = app.msgSend(
        bool,
        objc.sel("setActivationPolicy:"),
        .{@as(c_long, @intFromEnum(ActivationPolicy.accessory))},
    );
    if (!ok) log.warn("app: setActivationPolicy returned NO", .{});
    log.info("app: init complete", .{});
}

/// Block on the NSApplication run loop until the app quits.
pub fn run() void {
    log.info("app: entering NSRunLoop", .{});
    _ = bridge.sharedApplication().msgSend(void, objc.sel("run"), .{});
}

/// Request a clean shutdown from any thread.
pub fn quit() void {
    log.info("app: terminate requested", .{});
    const app = bridge.sharedApplication();
    _ = app.msgSend(void, objc.sel("terminate:"), .{app});
}
