//! Window frame restoration – Phase 2 implementation.
//! Tracks pre-snap window dimensions keyed by a window identifier
//! so SnapPoint can restore the original size when the user drags away.

const std = @import("std");
const geo = @import("../util/geometry.zig");
const log = @import("../core/log.zig");

const MAX_ENTRIES = 64;

const Entry = struct {
    key:            [128]u8,  // "bundleID:windowID" null-terminated
    key_len:        usize,
    original_frame: geo.Rect,
    layout_index:   usize,
    timestamp_s:    i64,      // unix seconds
};

pub const RestoreStore = struct {
    entries: [MAX_ENTRIES]Entry = undefined,
    count:   usize              = 0,

    pub fn store(
        self:          *RestoreStore,
        key:           []const u8,
        frame:         geo.Rect,
        layout_index:  usize,
    ) void {
        // Overwrite existing entry for same key if present
        for (self.entries[0..self.count]) |*e| {
            if (std.mem.eql(u8, e.key[0..e.key_len], key)) {
                e.original_frame = frame;
                e.layout_index   = layout_index;
                e.timestamp_s    = std.time.timestamp();
                return;
            }
        }
        // Add new entry
        if (self.count >= MAX_ENTRIES) {
            // Evict the oldest entry
            var oldest_idx: usize = 0;
            var oldest_ts: i64 = self.entries[0].timestamp_s;
            for (self.entries[0..self.count], 0..) |e, i| {
                if (e.timestamp_s < oldest_ts) {
                    oldest_ts  = e.timestamp_s;
                    oldest_idx = i;
                }
            }
            self.entries[oldest_idx] = self.entries[self.count - 1];
            self.count -= 1;
        }
        var entry = Entry{
            .key            = undefined,
            .key_len        = @min(key.len, 127),
            .original_frame = frame,
            .layout_index   = layout_index,
            .timestamp_s    = std.time.timestamp(),
        };
        @memset(&entry.key, 0);
        @memcpy(entry.key[0..entry.key_len], key[0..entry.key_len]);
        self.entries[self.count] = entry;
        self.count += 1;
    }

    pub fn get(self: *RestoreStore, key: []const u8) ?geo.Rect {
        for (self.entries[0..self.count]) |*e| {
            if (std.mem.eql(u8, e.key[0..e.key_len], key)) {
                return e.original_frame;
            }
        }
        return null;
    }

    pub fn remove(self: *RestoreStore, key: []const u8) void {
        for (self.entries[0..self.count], 0..) |*e, i| {
            if (std.mem.eql(u8, e.key[0..e.key_len], key)) {
                self.entries[i] = self.entries[self.count - 1];
                self.count -= 1;
                return;
            }
        }
    }

    /// Remove entries older than 24 hours.
    pub fn pruneStale(self: *RestoreStore) void {
        const cutoff = std.time.timestamp() - 86400;
        var i: usize = 0;
        while (i < self.count) {
            if (self.entries[i].timestamp_s < cutoff) {
                self.entries[i] = self.entries[self.count - 1];
                self.count -= 1;
            } else {
                i += 1;
            }
        }
    }
};
