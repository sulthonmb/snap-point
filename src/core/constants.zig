//! App-wide compile-time constants.

pub const app_name   = "SnapPoint";
pub const bundle_id  = "com.snappoint.app";

pub const version = struct {
    pub const major: u8  = 1;
    pub const minor: u8  = 0;
    pub const patch: u8  = 0;
    pub const string     = "1.0.0";
};

pub const config_dir              = "SnapPoint";
pub const min_window_size: f64    = 100.0;
pub const default_snap_sensitivity: u8  = 10;
pub const default_ghost_opacity: f32    = 0.3;
pub const default_window_gap: u8        = 0;
pub const permission_poll_ms: u64       = 1_000;
pub const layout_count: usize           = 25;
pub const action_count: usize           = 27; // 25 layouts + 2 multi-monitor
