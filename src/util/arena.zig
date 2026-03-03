//! Thin wrappers around std.heap.ArenaAllocator.
//! SnapPoint uses two arena lifetimes:
//!   GlobalArena   – process lifetime (config, display list)
//!   RequestArena  – per-snap-event (freed after window is moved)

const std = @import("std");

/// An arena that wraps `std.heap.page_allocator` and lives until `deinit`.
pub const Arena = struct {
    inner: std.heap.ArenaAllocator,

    pub fn init() Arena {
        return .{ .inner = std.heap.ArenaAllocator.init(std.heap.page_allocator) };
    }

    pub fn allocator(self: *Arena) std.mem.Allocator {
        return self.inner.allocator();
    }

    /// Free all memory allocated from this arena, returning backing memory
    /// to the OS. The arena can be reused after this call.
    pub fn reset(self: *Arena) void {
        _ = self.inner.reset(.free_all);
    }

    /// Permanently destroy the arena.
    pub fn deinit(self: *Arena) void {
        self.inner.deinit();
    }
};

/// Convenience: run a scoped function with a fresh arena, then free it.
pub fn withArena(comptime T: type, func: fn (std.mem.Allocator) anyerror!T) !T {
    var arena = Arena.init();
    defer arena.deinit();
    return func(arena.allocator());
}
