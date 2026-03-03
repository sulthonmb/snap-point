//! SnapPoint update checker.
//!
//! On "Check for Updates…" click, asynchronously fetches the latest GitHub
//! release via the REST API and compares its tag with the compiled-in version.
//!
//!   • If up-to-date  → NSAlert "You're running the latest version."
//!   • If outdated    → opens the release page in the default browser.
//!
//! Uses a custom NSURLSessionDataDelegate ObjC class ("SnapUpdateChecker")
//! to avoid requiring ObjC blocks (which Zig cannot express natively).
//! The delegate is always dispatched on the main queue for safe UI access.

const std = @import("std");
const objc = @import("objc");
const bridge = @import("../objc/bridge.zig");
const log = @import("../core/log.zig");
const constants = @import("../core/constants.zig");

// ── URLs ──────────────────────────────────────────────────────────────────

const RELEASES_API =
    "https://api.github.com/repos/sulthonmb/snap-point/releases/latest";
const RELEASES_PAGE =
    "https://github.com/sulthonmb/snap-point/releases";
const USER_AGENT = "SnapPoint/" ++ constants.version.string;

// ── Module-level receive buffer ───────────────────────────────────────────
// A static 64 KB buffer is more than enough for the GitHub API response.

var g_checker_registered = false;
var g_response_buf: [65536]u8 = undefined;
var g_response_len: usize = 0;

// ── Public API ────────────────────────────────────────────────────────────

/// Kick off an asynchronous update check.
/// Must be called on the main thread (UI interaction → menu action).
pub fn checkForUpdates() void {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    registerCheckerClass();
    g_response_len = 0; // reset receive buffer for a fresh request

    // ── Build the NSURLRequest ─────────────────────────────────────────
    const NSURL = bridge.getClass("NSURL");
    const NSMutableURLRequest = bridge.getClass("NSMutableURLRequest");

    const url = NSURL.msgSend(
        objc.Object,
        objc.sel("URLWithString:"),
        .{bridge.nsString(RELEASES_API)},
    );
    if (url.value == null) {
        log.err("updater: could not create NSURL for API endpoint", .{});
        return;
    }

    const req = NSMutableURLRequest.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("initWithURL:"), .{url});

    // GitHub API requires a User-Agent header.
    req.msgSend(void, objc.sel("setValue:forHTTPHeaderField:"), .{
        bridge.nsString(USER_AGENT),
        bridge.nsString("User-Agent"),
    });

    // ── Create NSURLSession with our delegate on the main queue ────────
    const NSURLSession = bridge.getClass("NSURLSession");
    const NSURLSessionConfiguration = bridge.getClass("NSURLSessionConfiguration");
    const NSOperationQueue = bridge.getClass("NSOperationQueue");

    const cfg = NSURLSessionConfiguration.msgSend(
        objc.Object,
        objc.sel("defaultSessionConfiguration"),
        .{},
    );
    const main_q = NSOperationQueue.msgSend(objc.Object, objc.sel("mainQueue"), .{});

    const CheckerClass = bridge.getClass("SnapUpdateChecker");
    const delegate = CheckerClass.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("init"), .{});

    const session = NSURLSession.msgSend(
        objc.Object,
        objc.sel("sessionWithConfiguration:delegate:delegateQueue:"),
        .{ cfg, delegate, main_q },
    );

    // ── Create and resume the data task ───────────────────────────────
    const task = session.msgSend(
        objc.Object,
        objc.sel("dataTaskWithRequest:"),
        .{req},
    );
    task.msgSend(void, objc.sel("resume"), .{});

    log.info("updater: checking for updates…", .{});
}

// ── ObjC class registration ───────────────────────────────────────────────

fn registerCheckerClass() void {
    if (g_checker_registered) return;
    g_checker_registered = true;

    const NSObject = objc.getClass("NSObject") orelse
        @panic("NSObject not found");

    const cls = objc.allocateClassPair(NSObject, "SnapUpdateChecker") orelse {
        // Class already registered on a second call path – that's fine.
        return;
    };

    // - (void)URLSession:dataTask:didReceiveData:
    _ = cls.addMethod("URLSession:dataTask:didReceiveData:", didReceiveData);

    // - (void)URLSession:task:didCompleteWithError:
    _ = cls.addMethod("URLSession:task:didCompleteWithError:", didComplete);

    objc.registerClassPair(cls);
}

// ── NSURLSessionDataDelegate callbacks ────────────────────────────────────

/// Accumulates received bytes into the module-level buffer.
fn didReceiveData(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    _session: objc.c.id,
    _task: objc.c.id,
    data: objc.c.id,
) callconv(.c) void {
    _ = _self;
    _ = _cmd;
    _ = _session;
    _ = _task;

    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const d = objc.Object{ .value = data };
    const bytes = d.msgSend(?[*]const u8, objc.sel("bytes"), .{});
    const len = d.msgSend(usize, objc.sel("length"), .{});
    if (bytes == null or len == 0) return;

    const remaining = g_response_buf.len - g_response_len;
    const copy_len = @min(len, remaining);
    @memcpy(g_response_buf[g_response_len..][0..copy_len], bytes.?[0..copy_len]);
    g_response_len += copy_len;
}

/// Called when the task finishes (success or error).
/// Parses the response and shows appropriate UI on the main thread.
fn didComplete(
    _self: objc.c.id,
    _cmd: objc.c.SEL,
    _session: objc.c.id,
    _task: objc.c.id,
    error_obj: objc.c.id,
) callconv(.c) void {
    _ = _self;
    _ = _cmd;
    _ = _session;
    _ = _task;

    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    // Network or transport error
    if (error_obj != null) {
        log.warn("updater: network error during update check", .{});
        showAlert(
            "Update Check Failed",
            "Could not connect to the update server. Check your internet connection and try again.",
        );
        return;
    }

    const json = g_response_buf[0..g_response_len];
    if (json.len == 0) {
        log.warn("updater: empty response from server", .{});
        showAlert("Update Check Failed", "The server returned an empty response.");
        return;
    }

    // Extract "tag_name" from the GitHub releases JSON.
    // GitHub returns: { "tag_name": "v1.2.3", ... }
    const tag_name = extractTagName(json) orelse {
        log.warn("updater: could not parse tag_name in response (len={d})", .{json.len});
        showAlert("Update Check Failed", "Could not parse the server response.");
        return;
    };

    // Strip leading 'v' (GitHub convention: "v1.0.0" → compare "1.0.0").
    const remote_version = if (tag_name.len > 0 and tag_name[0] == 'v')
        tag_name[1..]
    else
        tag_name;

    log.info("updater: latest={s} current={s}", .{ remote_version, constants.version.string });

    if (std.mem.eql(u8, remote_version, constants.version.string)) {
        showAlert(
            "SnapPoint is Up-to-Date",
            "You're running the latest version (" ++ constants.version.string ++ ").",
        );
    } else {
        // Open the release-specific page so the user can download the update.
        var page_buf: [512]u8 = undefined;
        const page_url = std.fmt.bufPrintZ(
            &page_buf,
            "{s}/tag/{s}",
            .{ RELEASES_PAGE, tag_name },
        ) catch RELEASES_PAGE;

        const NSURL = bridge.getClass("NSURL");
        const NSWorkspace = bridge.getClass("NSWorkspace");

        const url = NSURL.msgSend(
            objc.Object,
            objc.sel("URLWithString:"),
            .{bridge.nsString(page_url)},
        );
        const ws = NSWorkspace.msgSend(objc.Object, objc.sel("sharedWorkspace"), .{});
        _ = ws.msgSend(bool, objc.sel("openURL:"), .{url});

        log.info("updater: opened browser for release {s}", .{tag_name});
    }
}

// ── JSON helpers ──────────────────────────────────────────────────────────

/// Extract the value of "tag_name" from a GitHub releases JSON payload.
/// Handles both `"tag_name":"v1.0.0"` and `"tag_name": "v1.0.0"`.
fn extractTagName(json: []const u8) ?[]const u8 {
    // Try compact form first, then spaced form.
    const patterns = [_][]const u8{
        "\"tag_name\":\"",
        "\"tag_name\": \"",
    };
    for (patterns) |pattern| {
        if (std.mem.indexOf(u8, json, pattern)) |start| {
            const val_start = start + pattern.len;
            if (std.mem.indexOfScalarPos(u8, json, val_start, '"')) |val_end| {
                return json[val_start..val_end];
            }
        }
    }
    return null;
}

// ── UI helpers ────────────────────────────────────────────────────────────

/// Present a modal NSAlert with `title` and `message`.  Must be called on
/// the main thread (delegate queue is set to [NSOperationQueue mainQueue]).
fn showAlert(title: []const u8, message: []const u8) void {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSAlert = bridge.getClass("NSAlert");
    const alert = NSAlert.msgSend(objc.Object, objc.sel("alloc"), .{})
        .msgSend(objc.Object, objc.sel("init"), .{});
    alert.msgSend(void, objc.sel("setMessageText:"), .{bridge.nsString(title)});
    alert.msgSend(void, objc.sel("setInformativeText:"), .{bridge.nsString(message)});
    // NSAlertStyleInformational = 1
    alert.msgSend(void, objc.sel("setAlertStyle:"), .{@as(c_ulong, 1)});
    _ = alert.msgSend(c_long, objc.sel("runModal"), .{});
}
