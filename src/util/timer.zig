//! High-resolution monotonic timer using mach_absolute_time.
//! Used to measure snap latency against the < 16ms budget.

const std = @import("std");

extern fn mach_absolute_time() u64;
extern fn mach_timebase_info(info: *MachTimebaseInfo) i32;

const MachTimebaseInfo = extern struct {
    numer: u32,
    denom: u32,
};

var timebase: MachTimebaseInfo = .{ .numer = 1, .denom = 1 };
var timebase_init = false;

fn ensureTimebase() void {
    if (!timebase_init) {
        _ = mach_timebase_info(&timebase);
        timebase_init = true;
    }
}

/// Read the current monotonic tick counter.
pub fn now() u64 {
    return mach_absolute_time();
}

/// Convert a tick delta to nanoseconds.
pub fn ticksToNanos(ticks: u64) u64 {
    ensureTimebase();
    return ticks * timebase.numer / timebase.denom;
}

/// Convert a tick delta to milliseconds (f64 for sub-ms precision).
pub fn ticksToMillis(ticks: u64) f64 {
    return @as(f64, @floatFromInt(ticksToNanos(ticks))) / 1_000_000.0;
}

/// Measure elapsed milliseconds since `start_tick`.
pub fn elapsedMillis(start_tick: u64) f64 {
    return ticksToMillis(mach_absolute_time() - start_tick);
}
