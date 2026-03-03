//! Test entry point – lives at the project root so the Zig module path
//! covers both tests/ and src/, allowing @import("../src/...").
//!
//! Test modules:
//!   - test_layout: Layout geometry and resolution
//!   - test_geometry: Rect/Point math utilities
//!   - test_config: Config struct defaults and blacklist
//!   - test_zone: Trigger zone detection
//!   - test_hotkey: Keyboard shortcut matching
//!   - test_abi: C/ABI compatibility validation
//!   - test_config_persistence: JSON serialization round-trips
//!   - test_memory: Memory leak detection
//!   - test_snap: Snap action dispatch and enum coverage
//!   - test_settings: Settings window and shortcut recorder logic
comptime {
    // Core unit tests
    _ = @import("tests/test_layout.zig");
    _ = @import("tests/test_geometry.zig");
    _ = @import("tests/test_config.zig");
    _ = @import("tests/test_zone.zig");
    _ = @import("tests/test_hotkey.zig");

    // Extended test coverage
    _ = @import("tests/test_abi.zig");
    _ = @import("tests/test_config_persistence.zig");
    _ = @import("tests/test_memory.zig");

    // Phase 6: Snap action and dispatch tests
    _ = @import("tests/test_snap.zig");

    // Phase 4: Settings window and UI logic tests
    _ = @import("tests/test_settings.zig");
}
