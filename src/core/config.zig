//! Application configuration: in-memory struct, JSON load/save.
//! Stored at ~/Library/Application Support/SnapPoint/config.json.

const std = @import("std");
const builtin = @import("builtin");
const constants = @import("constants.zig");
const log = @import("log.zig");

// ── Shortcut ─────────────────────────────────────────────────────────────

/// Modifier bitmask (packed so it fits in a u8).
pub const Modifiers = packed struct(u8) {
    ctrl: bool = false,
    opt: bool = false,
    cmd: bool = false,
    shift: bool = false,
    _pad: u4 = 0,
};

pub const Shortcut = struct {
    key_code: u16 = 0,
    modifiers: Modifiers = .{},
    enabled: bool = true,
};

// ── Default shortcuts ─────────────────────────────────────────────────────
// Virtual key codes from the macOS HIToolbox (Carbon) header.
// Arrow keys: left=123, right=124, down=125, up=126
// Letter keys: a=0  s=1  d=2  e=14  f=3  g=5  t=17  u=32  i=34  j=38  k=40
// 1-6: 18-23    Return=36

const VK = struct {
    const left: u16 = 123;
    const right: u16 = 124;
    const down: u16 = 125;
    const up: u16 = 126;
    const u: u16 = 32;
    const i: u16 = 34;
    const j: u16 = 38;
    const k: u16 = 40;
    const d: u16 = 2;
    const f: u16 = 3;
    const g: u16 = 5;
    const e: u16 = 14;
    const t: u16 = 17;
    const k1: u16 = 18;
    const k2: u16 = 19;
    const k3: u16 = 20;
    const k4: u16 = 21;
    const k5: u16 = 23;
    const k6: u16 = 22;
    const ret: u16 = 36;
};

const ctrl_opt = Modifiers{ .ctrl = true, .opt = true };
const ctrl_opt_shift = Modifiers{ .ctrl = true, .opt = true, .shift = true };
const ctrl_opt_cmd = Modifiers{ .ctrl = true, .opt = true, .cmd = true };

pub const default_shortcuts: [constants.action_count]Shortcut = .{
    // 25 layout actions (index 0-24 maps to layout index)
    .{ .key_code = VK.left, .modifiers = ctrl_opt, .enabled = true }, // Left Half
    .{ .key_code = VK.right, .modifiers = ctrl_opt, .enabled = true }, // Right Half
    .{ .key_code = VK.up, .modifiers = ctrl_opt, .enabled = true }, // Top Half
    .{ .key_code = VK.down, .modifiers = ctrl_opt, .enabled = true }, // Bottom Half
    .{ .key_code = VK.u, .modifiers = ctrl_opt, .enabled = true }, // Top-Left Quarter
    .{ .key_code = VK.i, .modifiers = ctrl_opt, .enabled = true }, // Top-Right Quarter
    .{ .key_code = VK.j, .modifiers = ctrl_opt, .enabled = true }, // Bottom-Left Quarter
    .{ .key_code = VK.k, .modifiers = ctrl_opt, .enabled = true }, // Bottom-Right Quarter
    .{ .key_code = VK.d, .modifiers = ctrl_opt, .enabled = true }, // First Third
    .{ .key_code = VK.f, .modifiers = ctrl_opt, .enabled = true }, // Center Third
    .{ .key_code = VK.g, .modifiers = ctrl_opt, .enabled = true }, // Last Third
    .{ .key_code = VK.up, .modifiers = ctrl_opt_shift, .enabled = true }, // Top Third
    .{ .key_code = VK.right, .modifiers = ctrl_opt_shift, .enabled = true }, // Middle Third
    .{ .key_code = VK.down, .modifiers = ctrl_opt_shift, .enabled = true }, // Bottom Third
    .{ .key_code = VK.e, .modifiers = ctrl_opt, .enabled = true }, // Left Two-Thirds
    .{ .key_code = VK.t, .modifiers = ctrl_opt, .enabled = true }, // Right Two-Thirds
    .{ .key_code = VK.u, .modifiers = ctrl_opt_shift, .enabled = true }, // Top Two-Thirds
    .{ .key_code = VK.j, .modifiers = ctrl_opt_shift, .enabled = true }, // Bottom Two-Thirds
    .{ .key_code = VK.k1, .modifiers = ctrl_opt_shift, .enabled = true }, // Top-Left Sixth
    .{ .key_code = VK.k2, .modifiers = ctrl_opt_shift, .enabled = true }, // Top-Center Sixth
    .{ .key_code = VK.k3, .modifiers = ctrl_opt_shift, .enabled = true }, // Top-Right Sixth
    .{ .key_code = VK.k4, .modifiers = ctrl_opt_shift, .enabled = true }, // Bottom-Left Sixth
    .{ .key_code = VK.k5, .modifiers = ctrl_opt_shift, .enabled = true }, // Bottom-Center Sixth
    .{ .key_code = VK.k6, .modifiers = ctrl_opt_shift, .enabled = true }, // Bottom-Right Sixth
    .{ .key_code = VK.ret, .modifiers = ctrl_opt, .enabled = true }, // Almost Maximize
    // 2 multi-monitor actions (index 25-26)
    .{ .key_code = VK.right, .modifiers = ctrl_opt_cmd, .enabled = true }, // Throw Next Display
    .{ .key_code = VK.left, .modifiers = ctrl_opt_cmd, .enabled = true }, // Throw Prev Display
};

// ── Config struct ─────────────────────────────────────────────────────────

pub const Config = struct {
    // General
    launch_at_login: bool = false,
    snap_sensitivity: u8 = constants.default_snap_sensitivity,
    show_ghost_window: bool = true,

    // Visuals
    window_gap: u8 = constants.default_window_gap,
    ghost_opacity: f32 = constants.default_ghost_opacity,

    // Internal
    has_completed_onboarding: bool = false,
    config_version: u8 = 1,

    // Shortcuts: stored as a fixed array (not in JSON Phase 1 – loaded from defaults)
    shortcuts: [constants.action_count]Shortcut = default_shortcuts,

    // Blacklist: bundle identifiers to skip during snap
    // Stored as newline-separated string in the JSON for simplicity.
    // Phase 4 will refine this.
    blacklist_count: usize = 0,
    blacklist: [64][256]u8 = undefined,

    /// Check whether `bundle_id` is blacklisted.
    pub fn isBlacklisted(self: *const Config, bundle_id: []const u8) bool {
        for (self.blacklist[0..self.blacklist_count]) |*entry| {
            const entry_str = std.mem.sliceTo(entry, 0);
            if (std.mem.eql(u8, entry_str, bundle_id)) return true;
        }
        return false;
    }

    /// Add a bundle ID to the blacklist.  Returns false if blacklist is full.
    pub fn addToBlacklist(self: *Config, bundle_id: []const u8) bool {
        if (self.blacklist_count >= 64) return false;
        const idx = self.blacklist_count;
        @memset(&self.blacklist[idx], 0);
        const copy_len = @min(bundle_id.len, 255);
        @memcpy(self.blacklist[idx][0..copy_len], bundle_id[0..copy_len]);
        self.blacklist_count += 1;
        return true;
    }

    /// Remove the blacklist entry at `index`.  No-op if out of range.
    pub fn removeFromBlacklist(self: *Config, index: usize) void {
        if (index >= self.blacklist_count) return;
        var i = index;
        while (i + 1 < self.blacklist_count) : (i += 1) {
            @memcpy(&self.blacklist[i], &self.blacklist[i + 1]);
        }
        self.blacklist_count -= 1;
    }

    /// Bundle ID at `index` as a Zig slice (into the internal buffer).
    pub fn blacklistEntry(self: *const Config, index: usize) []const u8 {
        if (index >= self.blacklist_count) return "";
        return std.mem.sliceTo(&self.blacklist[index], 0);
    }
};

// ── JSON serialisation (Phase 4: full shortcuts + blacklist) ─────────────

/// Manually write config as pretty-printed JSON into `out`.
pub fn writeJson(c: *const Config, out: anytype) !void {
    try out.writeAll("{\n");
    try out.print("  \"launch_at_login\": {},\n", .{c.launch_at_login});
    try out.print("  \"snap_sensitivity\": {},\n", .{c.snap_sensitivity});
    try out.print("  \"show_ghost_window\": {},\n", .{c.show_ghost_window});
    try out.print("  \"window_gap\": {},\n", .{c.window_gap});
    try out.print("  \"ghost_opacity\": {d},\n", .{c.ghost_opacity});
    try out.print("  \"has_completed_onboarding\": {},\n", .{c.has_completed_onboarding});
    try out.print("  \"config_version\": {},\n", .{c.config_version});

    // shortcuts array
    try out.writeAll("  \"shortcuts\": [\n");
    for (c.shortcuts, 0..) |sc, i| {
        const mods_u8: u8 = @bitCast(sc.modifiers);
        const comma: []const u8 = if (i + 1 < c.shortcuts.len) "," else "";
        try out.print(
            "    {{\"key_code\": {}, \"modifiers\": {}, \"enabled\": {}}}{s}\n",
            .{ sc.key_code, mods_u8, sc.enabled, comma },
        );
    }
    try out.writeAll("  ],\n");

    // blacklist array
    try out.writeAll("  \"blacklist\": [");
    for (c.blacklist[0..c.blacklist_count], 0..) |*entry, i| {
        const s = std.mem.sliceTo(entry, 0);
        if (i > 0) try out.writeAll(", ");
        // JSON-escape the string (no control chars in bundle IDs, so
        // only handle the obligatory quote escaping)
        try out.writeByte('"');
        for (s) |ch| {
            if (ch == '"' or ch == '\\') try out.writeByte('\\');
            try out.writeByte(ch);
        }
        try out.writeByte('"');
    }
    try out.writeAll("]\n");
    try out.writeAll("}\n");
}

/// Parse the JSON value tree (produced by std.json.parseFromSlice) into
/// the Config struct.  Only fields that are present in the JSON are updated.
fn applyJsonValue(c: *Config, root: std.json.Value) void {
    const obj = switch (root) {
        .object => |o| o,
        else => return,
    };

    if (obj.get("launch_at_login")) |v| {
        if (v == .bool) c.launch_at_login = v.bool;
    }
    if (obj.get("snap_sensitivity")) |v| {
        if (v == .integer) c.snap_sensitivity = @intCast(@min(v.integer, 50));
    }
    if (obj.get("show_ghost_window")) |v| {
        if (v == .bool) c.show_ghost_window = v.bool;
    }
    if (obj.get("window_gap")) |v| {
        if (v == .integer) c.window_gap = @intCast(@min(v.integer, 50));
    }
    if (obj.get("ghost_opacity")) |v| switch (v) {
        .float => |f| c.ghost_opacity = @floatCast(f),
        .integer => |i| c.ghost_opacity = @floatCast(@as(f64, @floatFromInt(i))),
        else => {},
    };
    if (obj.get("has_completed_onboarding")) |v| {
        if (v == .bool) c.has_completed_onboarding = v.bool;
    }
    if (obj.get("config_version")) |v| {
        if (v == .integer) c.config_version = @intCast(@min(v.integer, 255));
    }

    // shortcuts
    if (obj.get("shortcuts")) |sv| {
        if (sv == .array) {
            for (sv.array.items, 0..) |item, i| {
                if (i >= constants.action_count) break;
                if (item != .object) continue;
                const so = item.object;
                if (so.get("key_code")) |kv| {
                    if (kv == .integer) c.shortcuts[i].key_code = @intCast(@min(kv.integer, 0xFFFF));
                }
                if (so.get("modifiers")) |mv| {
                    if (mv == .integer) c.shortcuts[i].modifiers = @bitCast(@as(u8, @intCast(@min(mv.integer, 0xFF))));
                }
                if (so.get("enabled")) |ev| {
                    if (ev == .bool) c.shortcuts[i].enabled = ev.bool;
                }
            }
        }
    }

    // blacklist
    if (obj.get("blacklist")) |blv| {
        if (blv == .array) {
            c.blacklist_count = 0;
            for (blv.array.items) |item| {
                if (item != .string) continue;
                _ = c.addToBlacklist(item.string);
            }
        }
    }
}

// ── File paths ────────────────────────────────────────────────────────────

fn configDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = std.posix.getenv("HOME") orelse "/tmp";
    return std.fmt.allocPrint(
        allocator,
        "{s}/Library/Application Support/{s}",
        .{ home, constants.config_dir },
    );
}

fn configPath(allocator: std.mem.Allocator) ![]const u8 {
    const dir = try configDir(allocator);
    defer allocator.free(dir);
    return std.fmt.allocPrint(allocator, "{s}/config.json", .{dir});
}

// ── Load / Save ───────────────────────────────────────────────────────────

/// Load config from disk into `config`.
/// If the file doesn't exist, `config` is left at its default values.
pub fn load(config: *Config, allocator: std.mem.Allocator) !void {
    const path = try configPath(allocator);
    defer allocator.free(path);

    const file = std.fs.openFileAbsolute(path, .{}) catch |e| {
        if (e == error.FileNotFound) {
            log.info("config: no file at {s}; using defaults", .{path});
            return;
        }
        return e;
    };
    defer file.close();

    const data = try file.readToEndAlloc(allocator, 1024 * 64);
    defer allocator.free(data);

    const parsed = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        data,
        .{},
    ) catch |e| {
        log.warn("config: JSON parse error ({any}); using defaults", .{e});
        return;
    };
    defer parsed.deinit();

    applyJsonValue(config, parsed.value);
    log.info("config: loaded from {s}", .{path});
}

/// Atomically write the current config to disk.
pub fn save(config: *const Config, allocator: std.mem.Allocator) !void {
    const dir_path = try configDir(allocator);
    defer allocator.free(dir_path);

    // Ensure directory exists
    std.fs.makeDirAbsolute(dir_path) catch |e| {
        if (e != error.PathAlreadyExists) return e;
    };

    const path = try configPath(allocator);
    defer allocator.free(path);

    // Serialise to JSON into a fixed stack buffer (config JSON < 4 KB)
    var raw_buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&raw_buf);
    try writeJson(config, fbs.writer());
    const json_bytes = fbs.getWritten();

    // Write to a temp file then rename (atomic swap)
    const tmp_path = try std.fmt.allocPrint(allocator, "{s}.tmp", .{path});
    defer allocator.free(tmp_path);

    const tmp = try std.fs.createFileAbsolute(tmp_path, .{});
    try tmp.writeAll(json_bytes);
    tmp.close();

    try std.fs.renameAbsolute(tmp_path, path);
    log.info("config: saved to {s}", .{path});
}
