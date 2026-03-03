//! Config persistence unit tests – JSON serialization/deserialization round-trips.
//! Validates that config values survive write → read cycles without loss.

const std = @import("std");
const config = @import("../src/core/config.zig");
const constants = @import("../src/core/constants.zig");

// ── JSON serialization round-trip ────────────────────────────────────────

test "writeJson produces valid JSON" {
    var c = config.Config{};
    c.snap_sensitivity = 25;
    c.window_gap = 15;
    c.ghost_opacity = 0.75;
    c.has_completed_onboarding = true;

    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try config.writeJson(&c, fbs.writer());
    const json = fbs.getWritten();

    // Verify it can be parsed back
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        json,
        .{},
    );
    defer parsed.deinit();

    // Verify key fields are present
    const obj = parsed.value.object;
    try std.testing.expect(obj.contains("snap_sensitivity"));
    try std.testing.expect(obj.contains("window_gap"));
    try std.testing.expect(obj.contains("ghost_opacity"));
    try std.testing.expect(obj.contains("shortcuts"));
    try std.testing.expect(obj.contains("blacklist"));
}

test "config JSON round-trip preserves general fields" {
    var original = config.Config{};
    original.launch_at_login = true;
    original.snap_sensitivity = 25;
    original.show_ghost_window = false;
    original.window_gap = 15;
    original.ghost_opacity = 0.85;
    original.has_completed_onboarding = true;
    original.config_version = 2;

    // Serialize
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try config.writeJson(&original, fbs.writer());
    const json = fbs.getWritten();

    // Parse back
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        json,
        .{},
    );
    defer parsed.deinit();

    // Verify numeric values
    const obj = parsed.value.object;
    try std.testing.expectEqual(obj.get("launch_at_login").?.bool, true);
    try std.testing.expectEqual(obj.get("snap_sensitivity").?.integer, 25);
    try std.testing.expectEqual(obj.get("show_ghost_window").?.bool, false);
    try std.testing.expectEqual(obj.get("window_gap").?.integer, 15);
    try std.testing.expectEqual(obj.get("has_completed_onboarding").?.bool, true);
    try std.testing.expectEqual(obj.get("config_version").?.integer, 2);

    // Float comparison
    const opacity = switch (obj.get("ghost_opacity").?) {
        .float => |f| f,
        .integer => |i| @as(f64, @floatFromInt(i)),
        else => 0.0,
    };
    try std.testing.expectApproxEqAbs(opacity, 0.85, 0.001);
}

test "config JSON round-trip preserves shortcuts array" {
    var original = config.Config{};
    // Modify a few shortcuts
    original.shortcuts[0].key_code = 99;
    original.shortcuts[0].modifiers = .{ .ctrl = true, .cmd = true };
    original.shortcuts[0].enabled = false;

    original.shortcuts[5].key_code = 42;
    original.shortcuts[5].modifiers = .{ .opt = true, .shift = true };

    // Serialize
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try config.writeJson(&original, fbs.writer());
    const json = fbs.getWritten();

    // Parse and verify shortcuts array
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        json,
        .{},
    );
    defer parsed.deinit();

    const shortcuts = parsed.value.object.get("shortcuts").?.array;
    try std.testing.expectEqual(shortcuts.items.len, constants.action_count);

    // Check first shortcut
    const sc0 = shortcuts.items[0].object;
    try std.testing.expectEqual(sc0.get("key_code").?.integer, 99);
    try std.testing.expectEqual(sc0.get("enabled").?.bool, false);

    // Check sixth shortcut
    const sc5 = shortcuts.items[5].object;
    try std.testing.expectEqual(sc5.get("key_code").?.integer, 42);
}

test "config JSON round-trip preserves blacklist" {
    var original = config.Config{};
    _ = original.addToBlacklist("com.apple.finder");
    _ = original.addToBlacklist("com.example.app");
    _ = original.addToBlacklist("org.test.bundle");

    // Serialize
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try config.writeJson(&original, fbs.writer());
    const json = fbs.getWritten();

    // Parse and verify blacklist
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        json,
        .{},
    );
    defer parsed.deinit();

    const blacklist = parsed.value.object.get("blacklist").?.array;
    try std.testing.expectEqual(blacklist.items.len, 3);
    try std.testing.expectEqualStrings(blacklist.items[0].string, "com.apple.finder");
    try std.testing.expectEqualStrings(blacklist.items[1].string, "com.example.app");
    try std.testing.expectEqualStrings(blacklist.items[2].string, "org.test.bundle");
}

test "empty blacklist serializes to empty array" {
    const c = config.Config{};

    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try config.writeJson(&c, fbs.writer());
    const json = fbs.getWritten();

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        json,
        .{},
    );
    defer parsed.deinit();

    const blacklist = parsed.value.object.get("blacklist").?.array;
    try std.testing.expectEqual(blacklist.items.len, 0);
}

// ── Default values ───────────────────────────────────────────────────────

test "default config serializes with expected defaults" {
    const c = config.Config{};

    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try config.writeJson(&c, fbs.writer());
    const json = fbs.getWritten();

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        json,
        .{},
    );
    defer parsed.deinit();

    const obj = parsed.value.object;
    try std.testing.expectEqual(obj.get("launch_at_login").?.bool, false);
    try std.testing.expectEqual(obj.get("snap_sensitivity").?.integer, constants.default_snap_sensitivity);
    try std.testing.expectEqual(obj.get("show_ghost_window").?.bool, true);
    try std.testing.expectEqual(obj.get("window_gap").?.integer, constants.default_window_gap);
    try std.testing.expectEqual(obj.get("has_completed_onboarding").?.bool, false);
    try std.testing.expectEqual(obj.get("config_version").?.integer, 1);
}

// ── Edge cases ───────────────────────────────────────────────────────────

test "blacklist with special characters in bundle ID" {
    var c = config.Config{};
    _ = c.addToBlacklist("com.app-with-dash");
    _ = c.addToBlacklist("com.app_with_underscore");
    _ = c.addToBlacklist("com.123numeric");

    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try config.writeJson(&c, fbs.writer());
    const json = fbs.getWritten();

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        json,
        .{},
    );
    defer parsed.deinit();

    const blacklist = parsed.value.object.get("blacklist").?.array;
    try std.testing.expectEqual(blacklist.items.len, 3);
    try std.testing.expectEqualStrings(blacklist.items[0].string, "com.app-with-dash");
    try std.testing.expectEqualStrings(blacklist.items[1].string, "com.app_with_underscore");
    try std.testing.expectEqualStrings(blacklist.items[2].string, "com.123numeric");
}

test "maximum sensitivity value" {
    var c = config.Config{};
    c.snap_sensitivity = 50;

    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try config.writeJson(&c, fbs.writer());
    const json = fbs.getWritten();

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        json,
        .{},
    );
    defer parsed.deinit();

    try std.testing.expectEqual(parsed.value.object.get("snap_sensitivity").?.integer, 50);
}

test "maximum window gap value" {
    var c = config.Config{};
    c.window_gap = 50;

    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try config.writeJson(&c, fbs.writer());
    const json = fbs.getWritten();

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        json,
        .{},
    );
    defer parsed.deinit();

    try std.testing.expectEqual(parsed.value.object.get("window_gap").?.integer, 50);
}

test "ghost opacity boundary values" {
    var c = config.Config{};

    // Test minimum
    c.ghost_opacity = 0.1;
    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try config.writeJson(&c, fbs.writer());

    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        fbs.getWritten(),
        .{},
    );
    var opacity = switch (parsed.value.object.get("ghost_opacity").?) {
        .float => |f| f,
        .integer => |i| @as(f64, @floatFromInt(i)),
        else => 0.0,
    };
    try std.testing.expectApproxEqAbs(opacity, 0.1, 0.001);
    parsed.deinit();

    // Test maximum
    c.ghost_opacity = 1.0;
    fbs = std.io.fixedBufferStream(&buf);
    try config.writeJson(&c, fbs.writer());

    parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        fbs.getWritten(),
        .{},
    );
    opacity = switch (parsed.value.object.get("ghost_opacity").?) {
        .float => |f| f,
        .integer => |i| @as(f64, @floatFromInt(i)),
        else => 0.0,
    };
    try std.testing.expectApproxEqAbs(opacity, 1.0, 0.001);
    parsed.deinit();
}

test "all 27 shortcuts serialized" {
    const c = config.Config{};

    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try config.writeJson(&c, fbs.writer());
    const json = fbs.getWritten();

    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        json,
        .{},
    );
    defer parsed.deinit();

    const shortcuts = parsed.value.object.get("shortcuts").?.array;
    try std.testing.expectEqual(shortcuts.items.len, 27);

    // Verify each shortcut has required fields
    for (shortcuts.items) |item| {
        try std.testing.expect(item.object.contains("key_code"));
        try std.testing.expect(item.object.contains("modifiers"));
        try std.testing.expect(item.object.contains("enabled"));
    }
}
