# Technical Requirements Document: SnapPoint

**Project Name:** SnapPoint
**Platform:** macOS 13.0+ (Ventura through Tahoe)
**Language:** Zig 0.13+
**License:** MIT
**Document Version:** 1.0
**Date:** March 2, 2026

---

## Table of Contents

1. [Overview & Goals](#1-overview--goals)
2. [System Architecture](#2-system-architecture)
3. [Project Structure](#3-project-structure)
4. [Build System & Toolchain](#4-build-system--toolchain)
5. [Core Modules](#5-core-modules)
6. [macOS Framework Integration](#6-macos-framework-integration)
7. [Layout Engine](#7-layout-engine)
8. [Event System](#8-event-system)
9. [User Interface Implementation](#9-user-interface-implementation)
10. [Persistence & Configuration](#10-persistence--configuration)
11. [Multi-Monitor Support](#11-multi-monitor-support)
12. [Security & Permissions](#12-security--permissions)
13. [Testing Strategy](#13-testing-strategy)
14. [Build, Packaging & Distribution](#14-build-packaging--distribution)
15. [Performance Budgets](#15-performance-budgets)
16. [Phased Implementation Plan](#16-phased-implementation-plan)
17. [Risk Register](#17-risk-register)
18. [Appendices](#18-appendices)

---

## 1. Overview & Goals

### 1.1 Purpose

This TRD translates the SnapPoint PRD into an actionable technical blueprint. It defines the module boundaries, data structures, API surfaces, and integration patterns required to build a production-quality macOS window manager in Zig.

### 1.2 Technical Goals

| Goal | Target | Measurement |
|---|---|---|
| Snap latency (hotkey → window moved) | < 16ms (single frame) | Instruments profiling |
| Memory footprint (idle) | < 5 MB RSS | Activity Monitor |
| Binary size (stripped) | < 100 KB | `ls -lh` on final artifact |
| CPU usage (idle) | < 0.1% | Activity Monitor over 60s |
| Startup time | < 200ms to menu bar icon | `mach_absolute_time` delta |
| Crash rate | 0 (no undefined behavior) | Address/UB sanitizers in CI |

### 1.3 Non-Goals (v1.0)

- Scripting engine or plugin API
- Custom user-defined layouts beyond the 25 presets
- Apple Silicon-only (must support Intel via universal binary)
- Integration with Stage Manager

---

## 2. System Architecture

### 2.1 High-Level Architecture Diagram

```
┌──────────────────────────────────────────────────────┐
│                    SnapPoint Process                  │
│                                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────────┐ │
│  │  Event Loop  │  │   Layout    │  │   Window     │ │
│  │  (CGEventTap │──│   Engine    │──│   Controller │ │
│  │   + RunLoop) │  │  (comptime) │  │  (AXUIElement│ │
│  └──────┬───────┘  └─────────────┘  └──────┬───────┘ │
│         │                                   │         │
│  ┌──────┴───────┐  ┌─────────────┐  ┌──────┴───────┐ │
│  │  HotKey      │  │   Config    │  │   Display    │ │
│  │  Manager     │  │   Store     │  │   Manager    │ │
│  │  (Zeys VKCs) │  │  (JSON/plist│  │  (CGDisplay) │ │
│  └──────────────┘  └─────────────┘  └──────────────┘ │
│                                                      │
│  ┌─────────────────────────────────────────────────┐  │
│  │              UI Layer (ObjC Interop)             │  │
│  │  ┌───────────┐ ┌────────────┐ ┌──────────────┐  │  │
│  │  │ StatusBar │ │  Settings  │ │ Ghost Window │  │  │
│  │  │ (NSStatus │ │  (NSWindow │ │ (NSWindow +  │  │  │
│  │  │  Item)    │ │  + Sidebar)│ │  VisualFX)   │  │  │
│  │  └───────────┘ └────────────┘ └──────────────┘  │  │
│  └─────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
         │                    │
         ▼                    ▼
┌─────────────────┐  ┌────────────────┐
│ Quartz Event    │  │ Accessibility  │
│ Services        │  │ API            │
│ (CGEventTap)    │  │ (AXUIElement)  │
└─────────────────┘  └────────────────┘
```

### 2.2 Threading Model

| Thread | Responsibility | Mechanism |
|---|---|---|
| **Main Thread** | UI rendering, `NSApplication` run loop, Accessibility API calls | `CFRunLoop` / `NSRunLoop` |
| **Event Tap Thread** | Global mouse/keyboard interception | `CGEventTap` + dedicated `CFRunLoopSource` |

All cross-thread communication uses `dispatch_async` onto the main queue to ensure AXUIElement calls happen on the main thread (Apple requirement).

### 2.3 Memory Architecture

- **Global Arena:** Long-lived allocations (config, display topology, layout table). Lives for the process lifetime.
- **Request Arena:** Per-snap-event allocations. Created when a snap is triggered, freed after the window is moved. Typical lifespan: < 16ms.
- **System Allocator Fallback:** Only for ObjC interop objects that must live beyond arena scope (e.g., `NSWindow` instances).

```zig
const GlobalAllocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const RequestAllocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
```

---

## 3. Project Structure

```
snap-point/
├── build.zig                    # Zig build system configuration
├── build.zig.zon                # Package manifest (dependencies)
├── LICENSE                      # MIT license
├── README.md
├── Product Requirements Document - SnapPoint.md
├── Technical Requirements Document - SnapPoint.md
│
├── src/
│   ├── main.zig                 # Entry point, NSApplication bootstrap
│   │
│   ├── core/
│   │   ├── app.zig              # Application lifecycle (init, run, deinit)
│   │   ├── config.zig           # Configuration loading/saving/defaults
│   │   ├── constants.zig        # App-wide constants and feature flags
│   │   └── log.zig              # Structured logging (os_log wrapper)
│   │
│   ├── engine/
│   │   ├── layout.zig           # 25 layout definitions (comptime geometry)
│   │   ├── snap.zig             # Snap decision engine (edge/corner detection)
│   │   ├── zone.zig             # Trigger zone calculations
│   │   └── restore.zig          # Pre-snap dimension storage & restoration
│   │
│   ├── platform/
│   │   ├── accessibility.zig    # AXUIElement wrapper (get/set window attrs)
│   │   ├── display.zig          # CGDisplay enumeration & safe area queries
│   │   ├── event_tap.zig        # CGEventTap setup, callback, run loop
│   │   ├── hotkey.zig           # Global hotkey registration & dispatch
│   │   ├── pasteboard.zig       # (reserved for future clipboard integration)
│   │   └── permission.zig       # AXIsProcessTrusted checks & prompts
│   │
│   ├── ui/
│   │   ├── status_bar.zig       # NSStatusItem + menu construction
│   │   ├── settings_window.zig  # Settings window (sidebar + content)
│   │   ├── ghost_window.zig     # Snap preview overlay
│   │   ├── onboarding.zig       # Three-step onboarding modal
│   │   └── shortcut_recorder.zig # Keyboard shortcut capture widget
│   │
│   ├── objc/
│   │   ├── bridge.zig           # zig-objc runtime helpers
│   │   ├── appkit.zig           # AppKit class/selector declarations
│   │   ├── foundation.zig       # Foundation class/selector declarations
│   │   └── quartz.zig           # Quartz/CoreGraphics declarations
│   │
│   └── util/
│       ├── arena.zig            # Arena allocator helpers
│       ├── geometry.zig         # Rect, Point, Size math utilities
│       └── timer.zig            # High-resolution timing (mach_absolute_time)
│
├── resources/
│   ├── Info.plist               # Application metadata & entitlements
│   ├── Entitlements.plist       # com.apple.security.accessibility
│   ├── SnapPoint.icns           # App icon (1024x1024 → all sizes)
│   ├── Assets.xcassets/         # SF Symbols references, menu bar icons
│   └── defaults.json            # Default configuration values
│
├── scripts/
│   ├── build-release.sh         # Production build, strip, sign, notarize
│   ├── create-dmg.sh            # DMG packaging with background image
│   └── run-tests.sh             # Test runner with sanitizers enabled
│
└── tests/
    ├── test_layout.zig          # Layout geometry unit tests
    ├── test_zone.zig            # Trigger zone calculation tests
    ├── test_config.zig          # Config serialization round-trip tests
    ├── test_geometry.zig        # Math utility tests
    └── test_snap.zig            # Snap engine integration tests
```

---

## 4. Build System & Toolchain

### 4.1 Dependencies

| Dependency | Version | Purpose | Integration |
|---|---|---|---|
| **Zig** | 0.13+ | Compiler, build system, test runner | System install / `zigup` |
| **zig-objc** | latest | Objective-C runtime interop | `build.zig.zon` package |
| **Zeys** | latest | Virtual key code definitions for macOS | `build.zig.zon` package |
| **macOS SDK** | 13.0+ | System frameworks (AppKit, Accessibility, Quartz) | Xcode CLT |

### 4.2 build.zig Configuration

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .os_tag = .macos,
            .cpu_arch = null, // universal binary: .aarch64 + .x86_64
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "SnapPoint",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link system frameworks
    exe.linkFramework("AppKit");
    exe.linkFramework("ApplicationServices"); // Accessibility
    exe.linkFramework("CoreGraphics");
    exe.linkFramework("Carbon");             // hotkey APIs

    // Add zig-objc dependency
    const objc_dep = b.dependency("zig-objc", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("objc", objc_dep.module("objc"));

    b.installArtifact(exe);

    // Test step
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
```

### 4.3 build.zig.zon

```zig
.{
    .name = "snap-point",
    .version = "1.0.0",
    .dependencies = .{
        .@"zig-objc" = .{
            .url = "https://github.com/hexops/zig-objc/archive/refs/heads/main.tar.gz",
            // .hash will be populated on first fetch
        },
    },
    .paths = .{
        "src",
        "build.zig",
        "build.zig.zon",
        "resources",
    },
}
```

### 4.4 Build Targets

| Command | Description |
|---|---|
| `zig build` | Debug build (safety checks enabled) |
| `zig build -Doptimize=ReleaseFast` | Release build (max performance) |
| `zig build -Doptimize=ReleaseSmall` | Release build (min binary size) |
| `zig build test` | Run all unit tests |
| `./scripts/build-release.sh` | Full pipeline: build → strip → sign → notarize → DMG |

---

## 5. Core Modules

### 5.1 Application Lifecycle (`core/app.zig`)

The application bootstrap follows this sequence:

```
main() → App.init() → NSApplication.sharedApplication()
                     → Check permissions (AXIsProcessTrusted)
                     → If untrusted → show Onboarding
                     → Load config from disk
                     → Initialize Display Manager
                     → Install CGEventTap
                     → Register global hotkeys
                     → Create NSStatusItem
                     → NSApplication.run()  ← blocks on main run loop
```

**Shutdown sequence:**

```
Quit action → Save config → Remove CGEventTap → Release AX refs → exit(0)
```

### 5.2 Configuration (`core/config.zig`)

Configuration is stored as a JSON file at `~/Library/Application Support/SnapPoint/config.json`.

#### Config Schema

```zig
pub const Config = struct {
    // General
    launch_at_login: bool = false,
    snap_sensitivity: u8 = 10,          // pixels from edge to trigger (1-50)
    show_ghost_window: bool = true,

    // Visuals
    window_gap: u8 = 0,                 // pixels between snapped windows (0-50)
    ghost_opacity: f32 = 0.3,           // ghost window opacity (0.1-1.0)

    // Keyboard Shortcuts (25 actions + 2 multi-monitor)
    shortcuts: [27]Shortcut = default_shortcuts,

    // Blacklist
    blacklisted_apps: []const u8 = &.{}, // bundle identifiers

    // Internal
    has_completed_onboarding: bool = false,
    config_version: u8 = 1,
};

pub const Shortcut = struct {
    key_code: u16,          // virtual key code (Zeys)
    modifiers: Modifiers,   // bitmask: Ctrl, Opt, Cmd, Shift
    enabled: bool = true,
};

pub const Modifiers = packed struct {
    ctrl: bool = false,
    opt: bool = false,
    cmd: bool = false,
    shift: bool = false,
};
```

#### Persistence

```
Load: App start → read file → JSON parse → validate → populate Config struct
Save: On any settings change → serialize Config → atomic write (write tmp + rename)
```

Atomic writes prevent corruption on crash. Use `std.fs.Dir.atomicFile()` when available, or manual tmp+rename pattern.

### 5.3 Logging (`core/log.zig`)

Wraps `os_log` via ObjC interop for integration with macOS Console.app.

| Level | Usage |
|---|---|
| `debug` | Per-event details (cursor position, zone match) — disabled in release |
| `info` | Lifecycle events (start, stop, config load) |
| `error` | Permission failures, AX errors, unexpected states |
| `fault` | Unrecoverable errors before crash |

---

## 6. macOS Framework Integration

### 6.1 Objective-C Bridge (`objc/bridge.zig`)

The `zig-objc` library provides raw `objc_msgSend` wrappers. The bridge module builds type-safe abstractions:

```zig
// Example: Creating an NSWindow
const NSWindow = objc.getClass("NSWindow");
const window = NSWindow.msgSend(
    objc.Object,
    objc.sel("initWithContentRect:styleMask:backing:defer:"),
    .{ rect, style_mask, backing, @as(objc.c.BOOL, 0) },
);
```

**Key patterns:**
- All ObjC objects are wrapped in `objc.Object` (opaque pointer)
- Selectors are resolved at comptime via `objc.sel()`
- `autorelease` pools are created per-event to manage temporary ObjC objects
- `@autoreleasepool` equivalent: create/drain `NSAutoreleasePool` manually

### 6.2 Accessibility API (`platform/accessibility.zig`)

#### Core Operations

```zig
pub const WindowController = struct {
    ax_app: AXUIElementRef,     // per-application element
    ax_window: AXUIElementRef,  // focused window element

    /// Get the frontmost window of the frontmost application
    pub fn getFocusedWindow() !WindowController { ... }

    /// Read current window position and size
    pub fn getFrame(self: *WindowController) !Rect { ... }

    /// Move and resize window to target rect
    pub fn setFrame(self: *WindowController, rect: Rect) !void {
        // 1. Set position (kAXPositionAttribute)
        var position = AXValueCreate(.cgPoint, &rect.origin);
        AXUIElementSetAttributeValue(self.ax_window, kAXPositionAttribute, position);

        // 2. Set size (kAXSizeAttribute)
        var size = AXValueCreate(.cgSize, &rect.size);
        AXUIElementSetAttributeValue(self.ax_window, kAXSizeAttribute, size);
    }

    /// Store original frame for restore-on-unsnap
    pub fn storeOriginalFrame(self: *WindowController) void { ... }

    /// Restore window to pre-snap dimensions
    pub fn restoreOriginalFrame(self: *WindowController) !void { ... }
};
```

#### AXUIElement Error Handling

| AX Error Code | Meaning | Recovery |
|---|---|---|
| `kAXErrorSuccess` | Operation succeeded | — |
| `kAXErrorAPIDisabled` | Accessibility not enabled | Show onboarding step 2 |
| `kAXErrorNotImplemented` | App doesn't support AX | Skip (add to blacklist suggestion) |
| `kAXErrorCannotComplete` | Transient failure | Retry once after 50ms |
| `kAXErrorIllegalArgument` | Invalid attribute/value | Log error, skip action |

### 6.3 Display Management (`platform/display.zig`)

```zig
pub const DisplayInfo = struct {
    display_id: CGDirectDisplayID,
    frame: Rect,              // full display bounds
    safe_area: Rect,          // usable area (minus menu bar, Dock)
    scale_factor: f64,        // Retina scale (1.0 or 2.0)
    is_primary: bool,
};

pub const DisplayManager = struct {
    displays: []DisplayInfo,

    /// Enumerate all active displays
    pub fn refresh() !void {
        // CGGetActiveDisplayList → iterate → CGDisplayBounds
        // Subtract menu bar height (NSScreen.visibleFrame)
        // Detect Dock position and size
    }

    /// Find which display contains the given point
    pub fn displayForPoint(point: Point) ?*DisplayInfo { ... }

    /// Get the "next" display for multi-monitor throw
    pub fn nextDisplay(current: CGDirectDisplayID) ?*DisplayInfo { ... }

    /// Listen for display configuration changes
    pub fn registerDisplayChangeCallback() void {
        CGDisplayRegisterReconfigurationCallback(callback, null);
    }
};
```

**Display change handling:** When a display is added, removed, or rearranged, the `DisplayManager` rebuilds its display list and recalculates all trigger zones.

---

## 7. Layout Engine

### 7.1 Layout Definitions (`engine/layout.zig`)

All 25 layouts are defined as comptime geometry specifications. Each layout maps to a fractional rectangle relative to the safe area of a display.

```zig
pub const LayoutRegion = struct {
    x_num: u8,    // numerator for x origin fraction
    x_den: u8,    // denominator for x origin fraction
    y_num: u8,    // numerator for y origin fraction
    y_den: u8,    // denominator for y origin fraction
    w_num: u8,    // numerator for width fraction
    w_den: u8,    // denominator for width fraction
    h_num: u8,    // numerator for height fraction
    h_den: u8,    // denominator for height fraction
};

pub const layouts = comptime blk: {
    var l: [25]LayoutRegion = undefined;

    // === Standard (1-8) ===
    l[0]  = .{ .x_num = 0, .x_den = 1, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 2, .h_num = 1, .h_den = 1 }; // Left Half
    l[1]  = .{ .x_num = 1, .x_den = 2, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 2, .h_num = 1, .h_den = 1 }; // Right Half
    l[2]  = .{ .x_num = 0, .x_den = 1, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 1, .h_num = 1, .h_den = 2 }; // Top Half
    l[3]  = .{ .x_num = 0, .x_den = 1, .y_num = 1, .y_den = 2, .w_num = 1, .w_den = 1, .h_num = 1, .h_den = 2 }; // Bottom Half
    l[4]  = .{ .x_num = 0, .x_den = 1, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 2, .h_num = 1, .h_den = 2 }; // Top-Left
    l[5]  = .{ .x_num = 1, .x_den = 2, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 2, .h_num = 1, .h_den = 2 }; // Top-Right
    l[6]  = .{ .x_num = 0, .x_den = 1, .y_num = 1, .y_den = 2, .w_num = 1, .w_den = 2, .h_num = 1, .h_den = 2 }; // Bottom-Left
    l[7]  = .{ .x_num = 1, .x_den = 2, .y_num = 1, .y_den = 2, .w_num = 1, .w_den = 2, .h_num = 1, .h_den = 2 }; // Bottom-Right

    // === Vertical Thirds (9-11) ===
    l[8]  = .{ .x_num = 0, .x_den = 1, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 3, .h_num = 1, .h_den = 1 }; // First Third
    l[9]  = .{ .x_num = 1, .x_den = 3, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 3, .h_num = 1, .h_den = 1 }; // Center Third
    l[10] = .{ .x_num = 2, .x_den = 3, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 3, .h_num = 1, .h_den = 1 }; // Last Third

    // === Horizontal/Portrait Thirds (12-14) ===
    l[11] = .{ .x_num = 0, .x_den = 1, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 1, .h_num = 1, .h_den = 3 }; // Top Third
    l[12] = .{ .x_num = 0, .x_den = 1, .y_num = 1, .y_den = 3, .w_num = 1, .w_den = 1, .h_num = 1, .h_den = 3 }; // Middle Third
    l[13] = .{ .x_num = 0, .x_den = 1, .y_num = 2, .y_den = 3, .w_num = 1, .w_den = 1, .h_num = 1, .h_den = 3 }; // Bottom Third

    // === Two-Thirds (15-18) ===
    l[14] = .{ .x_num = 0, .x_den = 1, .y_num = 0, .y_den = 1, .w_num = 2, .w_den = 3, .h_num = 1, .h_den = 1 }; // Left Two-Thirds
    l[15] = .{ .x_num = 1, .x_den = 3, .y_num = 0, .y_den = 1, .w_num = 2, .w_den = 3, .h_num = 1, .h_den = 1 }; // Right Two-Thirds
    l[16] = .{ .x_num = 0, .x_den = 1, .y_num = 0, .y_den = 1, .w_num = 1, .w_den = 1, .h_num = 2, .h_den = 3 }; // Top Two-Thirds
    l[17] = .{ .x_num = 0, .x_den = 1, .y_num = 1, .y_den = 3, .w_num = 1, .w_den = 1, .h_num = 2, .h_den = 3 }; // Bottom Two-Thirds

    // === Sixths (19-24) ===
    l[18] = .{ .x_num = 0, .x_den = 3, .y_num = 0, .y_den = 2, .w_num = 1, .w_den = 3, .h_num = 1, .h_den = 2 }; // Top-Left Sixth
    l[19] = .{ .x_num = 1, .x_den = 3, .y_num = 0, .y_den = 2, .w_num = 1, .w_den = 3, .h_num = 1, .h_den = 2 }; // Top-Center Sixth
    l[20] = .{ .x_num = 2, .x_den = 3, .y_num = 0, .y_den = 2, .w_num = 1, .w_den = 3, .h_num = 1, .h_den = 2 }; // Top-Right Sixth
    l[21] = .{ .x_num = 0, .x_den = 3, .y_num = 1, .y_den = 2, .w_num = 1, .w_den = 3, .h_num = 1, .h_den = 2 }; // Bottom-Left Sixth
    l[22] = .{ .x_num = 1, .x_den = 3, .y_num = 1, .y_den = 2, .w_num = 1, .w_den = 3, .h_num = 1, .h_den = 2 }; // Bottom-Center Sixth
    l[23] = .{ .x_num = 2, .x_den = 3, .y_num = 1, .y_den = 2, .w_num = 1, .w_den = 3, .h_num = 1, .h_den = 2 }; // Bottom-Right Sixth

    // === Focus (25) ===
    // Almost Maximize: 95% screen with centered 2.5% margin on each side
    l[24] = .{ .x_num = 1, .x_den = 40, .y_num = 1, .y_den = 40, .w_num = 19, .w_den = 20, .h_num = 19, .h_den = 20 }; // Almost Maximize

    break :blk l;
};
```

### 7.2 Layout Resolution

```zig
/// Resolve a LayoutRegion to absolute pixel coordinates on a given display
pub fn resolve(layout: LayoutRegion, safe_area: Rect, gap: u8) Rect {
    const gap_f = @as(f64, @floatFromInt(gap));

    const x = safe_area.origin.x + (safe_area.size.width * @as(f64, @floatFromInt(layout.x_num)) / @as(f64, @floatFromInt(layout.x_den))) + gap_f;
    const y = safe_area.origin.y + (safe_area.size.height * @as(f64, @floatFromInt(layout.y_num)) / @as(f64, @floatFromInt(layout.y_den))) + gap_f;
    const w = (safe_area.size.width * @as(f64, @floatFromInt(layout.w_num)) / @as(f64, @floatFromInt(layout.w_den))) - (gap_f * 2);
    const h = (safe_area.size.height * @as(f64, @floatFromInt(layout.h_num)) / @as(f64, @floatFromInt(layout.h_den))) - (gap_f * 2);

    return .{
        .origin = .{ .x = x, .y = y },
        .size = .{ .width = @max(w, 100), .height = @max(h, 100) },
    };
}
```

### 7.3 Layout Naming Table

Used for UI display and hotkey configuration:

```zig
pub const layout_names = [25][]const u8{
    "Left Half",           "Right Half",          "Top Half",            "Bottom Half",
    "Top-Left Quarter",    "Top-Right Quarter",   "Bottom-Left Quarter", "Bottom-Right Quarter",
    "First Third",         "Center Third",        "Last Third",
    "Top Third",           "Middle Third",        "Bottom Third",
    "Left Two-Thirds",     "Right Two-Thirds",    "Top Two-Thirds",     "Bottom Two-Thirds",
    "Top-Left Sixth",      "Top-Center Sixth",    "Top-Right Sixth",
    "Bottom-Left Sixth",   "Bottom-Center Sixth", "Bottom-Right Sixth",
    "Almost Maximize",
};
```

---

## 8. Event System

### 8.1 CGEventTap (`platform/event_tap.zig`)

The event tap is the primary input mechanism. It intercepts mouse and keyboard events at the system level.

```zig
pub fn installEventTap() !void {
    const event_mask = (1 << CGEventType.mouseMoved) |
                       (1 << CGEventType.leftMouseDragged) |
                       (1 << CGEventType.leftMouseUp) |
                       (1 << CGEventType.leftMouseDown);

    const tap = CGEventTapCreate(
        .cghidEventTap,           // tap location
        .headInsertEventTap,      // insert at head
        .defaultTap,              // active filter
        event_mask,
        eventCallback,            // callback function
        null,                     // user info
    );

    const run_loop_source = CFMachPortCreateRunLoopSource(null, tap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), run_loop_source, kCFRunLoopCommonModes);
    CGEventTapEnable(tap, true);
}
```

### 8.2 Event Callback Pipeline

```
CGEventTap callback
    │
    ├─ Mouse Drag Started?
    │   └─ Is dragging a window title bar?
    │       └─ Yes → Enter SNAP_TRACKING mode
    │
    ├─ Mouse Moved (during SNAP_TRACKING)?
    │   ├─ Calculate cursor position relative to all displays
    │   ├─ Evaluate trigger zones (edges, corners)
    │   ├─ If zone matched → Show ghost window at resolved layout rect
    │   └─ If no zone → Hide ghost window
    │
    ├─ Mouse Up (during SNAP_TRACKING)?
    │   ├─ If ghost window visible → Execute snap (move+resize window)
    │   ├─ Clear ghost window
    │   └─ Exit SNAP_TRACKING mode
    │
    └─ Pass event through (return event unchanged)
```

### 8.3 Trigger Zone Detection (`engine/zone.zig`)

```zig
pub const ZoneType = enum {
    none,
    left_half,
    right_half,
    top_maximize,
    bottom_first_third,
    bottom_center_third,
    bottom_last_third,
    top_left_quarter,
    top_right_quarter,
    bottom_left_quarter,
    bottom_right_quarter,
};

pub fn detectZone(cursor: Point, display: *DisplayInfo, sensitivity: u8) ZoneType {
    const s = @as(f64, @floatFromInt(sensitivity));
    const sa = display.safe_area;

    // Edge detection (priority: corners > edges > center)
    const at_left   = cursor.x - sa.origin.x < s;
    const at_right  = (sa.origin.x + sa.size.width) - cursor.x < s;
    const at_top    = cursor.y - sa.origin.y < s;
    const at_bottom = (sa.origin.y + sa.size.height) - cursor.y < s;

    // Corner zones (25% quadrants)
    if (at_top and at_left)     return .top_left_quarter;
    if (at_top and at_right)    return .top_right_quarter;
    if (at_bottom and at_left)  return .bottom_left_quarter;
    if (at_bottom and at_right) return .bottom_right_quarter;

    // Edge zones
    if (at_top)    return .top_maximize;
    if (at_left)   return .left_half;
    if (at_right)  return .right_half;

    // Bottom edge: split into thirds based on horizontal cursor position
    if (at_bottom) {
        const relative_x = (cursor.x - sa.origin.x) / sa.size.width;
        if (relative_x < 0.333) return .bottom_first_third;
        if (relative_x < 0.667) return .bottom_center_third;
        return .bottom_last_third;
    }

    return .none;
}
```

### 8.4 Global Hotkey System (`platform/hotkey.zig`)

Hotkeys are registered globally using `CGEventTap` key-down interception (not Carbon `RegisterEventHotKey` which is deprecated).

```zig
pub const HotkeyManager = struct {
    bindings: [27]Shortcut,   // 25 layouts + 2 multi-monitor actions

    pub fn init(config: *Config) HotkeyManager { ... }

    /// Called from event tap callback on key-down events
    pub fn handleKeyEvent(self: *HotkeyManager, key_code: u16, flags: CGEventFlags) ?Action {
        for (self.bindings, 0..) |binding, i| {
            if (!binding.enabled) continue;
            if (binding.key_code == key_code and modifiersMatch(binding.modifiers, flags)) {
                return @enumFromInt(i);
            }
        }
        return null;
    }
};

pub const Action = enum(u8) {
    // Layouts 0-24 map directly to layout indices
    snap_left_half = 0,
    snap_right_half = 1,
    // ... all 25 layouts ...
    snap_almost_maximize = 24,
    // Multi-monitor actions
    throw_to_next_display = 25,
    throw_to_prev_display = 26,
};
```

### 8.5 Snap Execution Flow (`engine/snap.zig`)

```zig
pub fn executeSnap(action: Action, config: *Config) !void {
    // 1. Create request-scoped arena
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // 2. Get focused window
    var wc = try WindowController.getFocusedWindow();

    // 3. Check blacklist
    const bundle_id = try wc.getBundleIdentifier();
    if (config.isBlacklisted(bundle_id)) return;

    // 4. Store original frame (for unsnap restore)
    wc.storeOriginalFrame();

    // 5. Determine target display
    const display = if (action == .throw_to_next_display or action == .throw_to_prev_display)
        DisplayManager.nextDisplay(wc.getCurrentDisplay())
    else
        DisplayManager.displayForWindow(wc);

    // 6. Resolve layout to absolute coordinates
    const layout_idx = @intFromEnum(action);
    const target_rect = layout.resolve(
        layout.layouts[layout_idx],
        display.safe_area,
        config.window_gap,
    );

    // 7. Apply
    try wc.setFrame(target_rect);
}
```

---

## 9. User Interface Implementation

### 9.1 Status Bar Menu (`ui/status_bar.zig`)

The menu bar icon and dropdown are built using `NSStatusItem` and `NSMenu`.

```
┌───────────────────────────────┐
│  ◧ Left Half          ⌃⌥←   │
│  ◨ Right Half         ⌃⌥→   │
│  ⬒ Top Half           ⌃⌥↑   │
│  ⬓ Bottom Half        ⌃⌥↓   │
│  ◰ Fullscreen         ⌃⌥↩   │
│───────────────────────────────│
│  ▸ Thirds                    │
│  ▸ Two-Thirds                │
│  ▸ Sixths                    │
│───────────────────────────────│
│  ↗ Move to Next Display ⌃⌥⌘→│
│  ☐ Ignore "Terminal"         │
│───────────────────────────────│
│  ⚙ Settings...         ⌘,   │
│  ↻ Check for Updates...      │
│  ✕ Quit SnapPoint       ⌘Q  │
└───────────────────────────────┘
```

**Implementation details:**
- `NSStatusItem` with `NSImage` using SF Symbols (`rectangle.split.2x1`)
- Each `NSMenuItem` has a target/action pair pointing to ObjC selector wrappers
- Submenus for Thirds, Two-Thirds, Sixths use `NSMenu` nesting
- "Ignore [App]" dynamically reads the frontmost app name via `NSWorkspace.shared.frontmostApplication`
- SF Symbols 7 requires macOS 15+; fallback to SF Symbols 5 (macOS 14) or bundled PNGs (macOS 13)

### 9.2 Settings Window (`ui/settings_window.zig`)

An `NSWindow` (800pt × 600pt) with sidebar navigation.

#### Architecture

```
NSWindow (800 x 600, titled, closable, NOT resizable)
├── NSSplitView (vertical divider)
│   ├── NSOutlineView / NSTableView (sidebar, 200pt)
│   │   ├── "General"
│   │   ├── "Keyboard"
│   │   ├── "Visuals"
│   │   └── "Blacklist"
│   └── NSView (content area, 600pt)
│       └── [Swapped based on sidebar selection]
```

#### Settings Pages

**General Page:**
| Control | Type | Binding |
|---|---|---|
| Launch at Login | `NSSwitch` (glass prominent) | `config.launch_at_login` |
| Snap Sensitivity | `NSPopUpButton` (5/10/15/20 px) | `config.snap_sensitivity` |
| Show Ghost Window | `NSSwitch` | `config.show_ghost_window` |

**Keyboard Page:**
| Control | Type | Notes |
|---|---|---|
| Layout list | `NSTableView` | 27 rows (25 layouts + 2 throw actions) |
| Shortcut column | `ShortcutRecorderView` | Custom view capturing key events |
| Reset Defaults | `NSButton` | Restores `default_shortcuts` |

**Visuals Page:**
| Control | Type | Range |
|---|---|---|
| Window Gaps | `NSSlider` + value label | 0–50 px, integer step |
| Ghost Opacity | `NSSlider` + value label | 0.1–1.0, 0.05 step |

**Blacklist Page:**
| Control | Type | Notes |
|---|---|---|
| App list | `NSTableView` | Shows app name + bundle ID |
| Add button | `NSButton` (+) | Opens `NSOpenPanel` filtered to `.app` |
| Remove button | `NSButton` (−) | Removes selected row |

### 9.3 Ghost Window (`ui/ghost_window.zig`)

```zig
pub const GhostWindow = struct {
    window: objc.Object,        // NSWindow
    effect_view: objc.Object,   // NSVisualEffectView

    pub fn init() GhostWindow {
        // Create borderless, transparent NSWindow
        // Level: .statusBar (above normal windows)
        // ignoresMouseEvents = true
        // backgroundColor = .clear
        // opaque = false
        //
        // Add NSVisualEffectView as content view
        // Material: .hudWindow (closest to "Lensing" refraction)
        // BlendingMode: .behindWindow
        // State: .active
    }

    pub fn show(self: *GhostWindow, rect: Rect, opacity: f32) void {
        // setFrame, setAlphaValue, orderFront
        // Animate in with 150ms fade (CABasicAnimation)
    }

    pub fn hide(self: *GhostWindow) void {
        // orderOut (instant) or animate out with 100ms fade
    }
};
```

### 9.4 Onboarding Flow (`ui/onboarding.zig`)

Three-step modal `NSWindow` (560pt × 400pt), non-resizable, centered.

| Step | Content | Action |
|---|---|---|
| 1 | Hero animation (looping `AVPlayerView` or animated `NSImageView`) | "Continue" button |
| 2 | Accessibility permission guide. Check status with `AXIsProcessTrusted()`. Deep link via `NSWorkspace.open(URL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"))` | "Open System Settings" + "I've Enabled It" |
| 3 | Default shortcut set picker (Compact / Full / Custom) | "Get Started" button |

**Permission polling:** After step 2, poll `AXIsProcessTrusted()` every 1 second with a `Timer`. Auto-advance to step 3 when granted.

### 9.5 Shortcut Recorder (`ui/shortcut_recorder.zig`)

A custom `NSView` subclass via ObjC interop that:
1. Displays current shortcut as text (e.g., "⌃⌥←")
2. On click, enters recording mode (highlighted border, "Press shortcut..." text)
3. Captures next key-down event with modifiers
4. Validates: requires at least one modifier (⌃, ⌥, ⌘, or ⇧)
5. Checks for conflicts with other bindings
6. Writes to config on confirmation

---

## 10. Persistence & Configuration

### 10.1 File Locations

| Data | Path | Format |
|---|---|---|
| Configuration | `~/Library/Application Support/SnapPoint/config.json` | JSON |
| Window state cache | `~/Library/Caches/SnapPoint/window_states.json` | JSON |
| Logs | Unified logging via `os_log` | System |

### 10.2 Config JSON Schema

```json
{
  "$schema": "snappoint-config-v1",
  "general": {
    "launch_at_login": false,
    "snap_sensitivity": 10,
    "show_ghost_window": true,
    "has_completed_onboarding": false
  },
  "visuals": {
    "window_gap": 0,
    "ghost_opacity": 0.3
  },
  "shortcuts": [
    { "action": "left_half",    "key": "left",  "modifiers": ["ctrl", "opt"], "enabled": true },
    { "action": "right_half",   "key": "right", "modifiers": ["ctrl", "opt"], "enabled": true },
    { "action": "top_half",     "key": "up",    "modifiers": ["ctrl", "opt"], "enabled": true },
    { "action": "bottom_half",  "key": "down",  "modifiers": ["ctrl", "opt"], "enabled": true },
    "... (25 layouts + 2 multi-monitor actions)"
  ],
  "blacklist": [
    "com.apple.finder"
  ]
}
```

### 10.3 Window State Cache (Restore-on-Unsnap)

```json
{
  "windows": {
    "com.apple.Safari:12345": {
      "original_frame": { "x": 100, "y": 200, "w": 800, "h": 600 },
      "snapped_layout": 0,
      "timestamp": 1709337600
    }
  }
}
```

Windows are keyed by `bundleID:windowID`. Entries older than 24 hours are pruned on app launch.

### 10.4 Launch at Login

Implemented via `SMAppService.mainApp` (macOS 13+):

```zig
// Enable
SMAppService.mainApp().register();

// Disable
SMAppService.mainApp().unregister();

// Check status
SMAppService.mainApp().status == .enabled;
```

---

## 11. Multi-Monitor Support

### 11.1 Display Topology

```
┌──────────────┐  ┌──────────────┐
│   Display 1  │  │   Display 2  │
│   (Primary)  │──│  (External)  │
│  2560×1440   │  │  3440×1440   │
└──────────────┘  └──────────────┘
```

### 11.2 Multi-Monitor Throw Logic

```zig
pub fn throwWindow(direction: enum { next, prev }) !void {
    var wc = try WindowController.getFocusedWindow();
    const current_display = DisplayManager.displayForWindow(wc);

    const target_display = switch (direction) {
        .next => DisplayManager.nextDisplay(current_display.display_id),
        .prev => DisplayManager.prevDisplay(current_display.display_id),
    } orelse return; // no other display

    // Preserve relative position (proportional mapping)
    const current_frame = try wc.getFrame();
    const relative_x = (current_frame.origin.x - current_display.safe_area.origin.x) / current_display.safe_area.size.width;
    const relative_y = (current_frame.origin.y - current_display.safe_area.origin.y) / current_display.safe_area.size.height;
    const relative_w = current_frame.size.width / current_display.safe_area.size.width;
    const relative_h = current_frame.size.height / current_display.safe_area.size.height;

    const target_rect = Rect{
        .origin = .{
            .x = target_display.safe_area.origin.x + (relative_x * target_display.safe_area.size.width),
            .y = target_display.safe_area.origin.y + (relative_y * target_display.safe_area.size.height),
        },
        .size = .{
            .width = relative_w * target_display.safe_area.size.width,
            .height = relative_h * target_display.safe_area.size.height,
        },
    };

    try wc.setFrame(target_rect);
}
```

### 11.3 Display Change Handling

| Event | Response |
|---|---|
| Display connected | Rebuild display list, recalculate zones |
| Display disconnected | Move windows from vanished display to primary |
| Resolution changed | Recalculate safe areas and reapply active snaps |
| Arrangement changed | Rebuild spatial topology for throw ordering |

---

## 12. Security & Permissions

### 12.1 Entitlements

```xml
<!-- Entitlements.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

### 12.2 Info.plist (Key Entries)

```xml
<key>CFBundleIdentifier</key>
<string>com.snappoint.app</string>

<key>CFBundleName</key>
<string>SnapPoint</string>

<key>LSMinimumSystemVersion</key>
<string>13.0</string>

<key>LSUIElement</key>
<true/>  <!-- Agent app: no Dock icon, no "App is not responding" dialog -->

<key>NSAccessibilityUsageDescription</key>
<string>SnapPoint needs Accessibility access to move and resize windows on your behalf.</string>
```

### 12.3 Permission Check Flow

```
App Launch
    │
    ├── AXIsProcessTrusted() == true?
    │       ├── Yes → Continue to main app
    │       └── No  → Show Onboarding (Step 2)
    │
    ├── After onboarding, poll every 1s:
    │       ├── AXIsProcessTrusted() == true → Advance to Step 3
    │       └── Still false → Keep waiting (show instructions)
    │
    └── On subsequent launches:
            ├── AXIsProcessTrusted() == true → Normal operation
            └── AXIsProcessTrusted() == false → Show permission re-request dialog
```

### 12.4 Code Signing & Notarization

```bash
# 1. Build universal binary
zig build -Doptimize=ReleaseSmall -Dtarget=aarch64-macos
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-macos
lipo -create zig-out/bin/SnapPoint-aarch64 zig-out/bin/SnapPoint-x86_64 -output SnapPoint

# 2. Create .app bundle
mkdir -p SnapPoint.app/Contents/MacOS
mkdir -p SnapPoint.app/Contents/Resources
cp SnapPoint SnapPoint.app/Contents/MacOS/
cp resources/Info.plist SnapPoint.app/Contents/
cp resources/SnapPoint.icns SnapPoint.app/Contents/Resources/

# 3. Sign
codesign --deep --force --verify --verbose \
    --sign "Developer ID Application: <TEAM>" \
    --options runtime \
    --entitlements resources/Entitlements.plist \
    SnapPoint.app

# 4. Notarize
xcrun notarytool submit SnapPoint.app.zip \
    --apple-id "$APPLE_ID" \
    --password "$APP_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait

# 5. Staple
xcrun stapler staple SnapPoint.app

# 6. Create DMG
hdiutil create -volname "SnapPoint" \
    -srcfolder SnapPoint.app \
    -ov -format UDZO \
    SnapPoint.dmg
```

---

## 13. Testing Strategy

### 13.1 Unit Tests

| Module | Test Coverage |
|---|---|
| `engine/layout.zig` | All 25 layouts resolve to correct absolute rects for known display sizes |
| `engine/zone.zig` | Zone detection returns correct zone for cursor positions at edges, corners, center |
| `engine/restore.zig` | Store/restore cycle preserves original frame exactly |
| `core/config.zig` | JSON serialization round-trip, defaults population, migration |
| `util/geometry.zig` | Rect intersection, containment, point-in-rect |

### 13.2 Integration Tests

| Test | Description |
|---|---|
| Full snap cycle | Trigger snap via simulated hotkey → verify window moved to correct rect |
| Multi-monitor throw | Simulate two displays → throw window → verify proportional mapping |
| Config persistence | Write config → restart → verify values loaded correctly |
| Blacklist enforcement | Add app to blacklist → attempt snap → verify no-op |
| Display change | Simulate display disconnect → verify windows moved to primary |

### 13.3 Manual Test Matrix

| Scenario | macOS 13 | macOS 14 | macOS 15 | macOS 16 (Tahoe) |
|---|---|---|---|---|
| Basic snap (all 25 layouts) | ✓ | ✓ | ✓ | ✓ |
| Ghost window rendering | ✓ | ✓ | ✓ | ✓ |
| Permission onboarding | ✓ | ✓ | ✓ | ✓ |
| Multi-monitor | ✓ | ✓ | ✓ | ✓ |
| Retina scaling | ✓ | ✓ | ✓ | ✓ |
| Launch at login | ✓ | ✓ | ✓ | ✓ |
| SF Symbols version | Bundled PNG | v5 | v6 | v7 |

### 13.4 Sanitizer Configuration

Debug builds enable Zig's safety features:
- Bounds checking on all array/slice accesses
- Integer overflow detection
- Null pointer dereference detection
- Use-after-free detection (via arena pattern — freed arenas trap on access in debug)

---

## 14. Build, Packaging & Distribution

### 14.1 CI/CD Pipeline

```
┌─────────┐    ┌──────────┐    ┌──────────┐    ┌───────────┐    ┌──────────┐
│  Push /  │───▸│  Build   │───▸│  Test    │───▸│  Sign &   │───▸│  Upload  │
│  Tag     │    │  (Debug) │    │  (unit + │    │  Notarize │    │  Release │
└─────────┘    └──────────┘    │  integ.) │    └───────────┘    └──────────┘
                               └──────────┘
```

**CI Environment:** GitHub Actions with macOS runner (macos-14).

### 14.2 Release Artifacts

| Artifact | Contents |
|---|---|
| `SnapPoint-v1.0.0.dmg` | Signed .app bundle + Applications shortcut |
| `SnapPoint-v1.0.0.zip` | Signed .app bundle (for Homebrew cask) |
| `SHA256SUMS.txt` | Checksums for verification |

### 14.3 Update Mechanism

v1.0 uses a simple check: on "Check for Updates" click, fetch `https://api.github.com/repos/<org>/snap-point/releases/latest` and compare `tag_name` with compiled-in version. If newer, open the release page in the default browser.

---

## 15. Performance Budgets

### 15.1 Latency Breakdown (Snap Event)

| Phase | Budget | Notes |
|---|---|---|
| Event tap callback entry | 0 ms | Kernel delivers event |
| Zone detection | < 0.1 ms | Simple arithmetic comparisons |
| Layout resolution | < 0.01 ms | Comptime-precomputed fractions |
| AXUIElement get focused window | < 5 ms | IPC to target app |
| AXUIElement set position + size | < 8 ms | IPC to target app |
| Ghost window show/hide | < 2 ms | GPU compositing |
| **Total** | **< 16 ms** | **Within single frame** |

### 15.2 Memory Budget

| Component | Budget |
|---|---|
| Binary (mapped) | < 100 KB |
| Heap (config, display list, window cache) | < 1 MB |
| ObjC objects (menus, windows) | < 2 MB |
| Event tap buffers | < 0.5 MB |
| **Total RSS** | **< 5 MB** |

### 15.3 CPU Budget

| State | Budget |
|---|---|
| Idle (no user interaction) | < 0.1% |
| Active snapping (drag in progress) | < 2% |
| Settings window open | < 1% |

---

## 16. Phased Implementation Plan

### Phase 0: Scaffolding (Week 1)

| Task | Deliverable |
|---|---|
| Initialize Zig project with `build.zig` | Compiling skeleton |
| Set up `zig-objc` dependency | ObjC interop working |
| Implement ObjC bridge (`objc/bridge.zig`) | NSLog callable from Zig |
| Create `main.zig` with `NSApplication` bootstrap | App launches, no crash |
| Add `LSUIElement` to Info.plist | Agent app (no dock icon) |
| Basic logging via `os_log` | Console.app shows SnapPoint logs |

### Phase 1: Core Engine (Weeks 2–3)

| Task | Deliverable |
|---|---|
| Implement `AXIsProcessTrusted` check | Permission status detected |
| Implement `WindowController` (AXUIElement) | Can read/write window frames |
| Implement `DisplayManager` (CGDisplay) | Enumerates displays + safe areas |
| Define all 25 layouts (comptime) | Layout table compiles |
| Implement layout resolver | Layouts resolve to pixel rects |
| Unit tests for layout + geometry | All 25 layouts verified |

### Phase 2: Event System (Week 4)

| Task | Deliverable |
|---|---|
| Implement `CGEventTap` for mouse events | Mouse drag tracking works |
| Implement trigger zone detection | Zones detected at screen edges |
| Implement snap execution (zone → layout → AX) | Windows snap on mouse-up |
| Implement restorative unsnapping | Dragging away restores original size |
| Implement `CGEventTap` for keyboard events | Key events captured |
| Implement `HotkeyManager` | Hotkeys trigger layout actions |

### Phase 3: UI — Menu Bar & Ghost Window (Week 5)

| Task | Deliverable |
|---|---|
| Create `NSStatusItem` with icon | Menu bar icon appears |
| Build full `NSMenu` with all actions | All 25 layouts accessible |
| Implement "Ignore [App]" dynamic item | Shows frontmost app name |
| Implement `GhostWindow` with `NSVisualEffectView` | Preview overlay renders |
| Connect ghost window to snap tracking | Ghost follows cursor zones |

### Phase 4: UI — Settings & Onboarding (Weeks 6–7)

| Task | Deliverable |
|---|---|
| Create Settings `NSWindow` with sidebar | Window opens and navigates |
| Implement General settings page | Switches and pickers functional |
| Implement Keyboard settings page | Shortcut recorder captures keys |
| Implement Visuals settings page | Sliders control gap + opacity |
| Implement Blacklist settings page | Add/remove apps from list |
| Implement config persistence (JSON) | Settings survive restart |
| Implement three-step onboarding flow | New users guided through setup |
| Implement permission polling | Auto-advance on AX grant |

### Phase 5: Multi-Monitor & Polish (Week 8)

| Task | Deliverable |
|---|---|
| Implement multi-monitor throw | Windows move across displays |
| Handle display connect/disconnect | Dynamic topology updates |
| Implement launch-at-login | `SMAppService` integration |
| Handle display scaling (Retina) | Correct positioning on HiDPI |
| Add keyboard shortcut hints to menu | Shortcuts shown in menu items |
| Implement "Check for Updates" | GitHub API comparison |

### Phase 6: Testing & Release (Weeks 9–10)

| Task | Deliverable |
|---|---|
| Full integration test pass | All flows verified |
| macOS version compatibility testing | 13, 14, 15, 16 tested |
| Performance profiling (Instruments) | All budgets met |
| Create app icon and assets | Final visual assets |
| Code signing + notarization pipeline | Signed DMG produced |
| Create DMG with background image | Polished installer |
| Write README and documentation | User-facing docs complete |
| GitHub release | v1.0.0 published |

---

## 17. Risk Register

| # | Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|---|
| R1 | `zig-objc` lacks coverage for needed AppKit APIs | High | Medium | Fork and extend; contribute patches upstream. Fall back to raw `@extern` C function calls. |
| R2 | CGEventTap disabled by macOS security (TCC changes) | Critical | Low | Monitor Apple developer forums; event taps currently require only Accessibility permission (not Input Monitoring separately in macOS 13+). |
| R3 | AXUIElement latency exceeds 16ms for some apps (e.g., Electron) | Medium | Medium | Accept graceful degradation; log slow apps. Investigate batching position+size into fewer IPC calls. |
| R4 | Zig 0.13+ breaking changes to `std` library | Medium | Medium | Pin Zig version in CI. Use `zig version manager` (`zigup`). Isolate `std` usage behind wrapper modules. |
| R5 | Apple deprecates CGEventTap in future macOS | Critical | Low | Long-term: investigate `NSEvent.addGlobalMonitorForEvents` as fallback (limited but functional). |
| R6 | Binary size exceeds 100 KB target | Low | Medium | Use `ReleaseSmall`, strip debug info, avoid unnecessary `std` imports. Profile with `bloaty`. |
| R7 | SF Symbols 7 not backward-compatible | Low | High | Already planned: fallback to SF Symbols 5 (macOS 14) or bundled PNGs (macOS 13). |
| R8 | Multi-monitor with mixed Retina/non-Retina displays | Medium | Medium | Use `CGDisplayScreenSize` and `backingScaleFactor` to normalize coordinates. Test with external displays. |

---

## 18. Appendices

### Appendix A: Default Keyboard Shortcuts

| # | Action | Default Shortcut |
|---|---|---|
| 1 | Left Half | `⌃⌥ ←` |
| 2 | Right Half | `⌃⌥ →` |
| 3 | Top Half | `⌃⌥ ↑` |
| 4 | Bottom Half | `⌃⌥ ↓` |
| 5 | Top-Left Quarter | `⌃⌥ U` |
| 6 | Top-Right Quarter | `⌃⌥ I` |
| 7 | Bottom-Left Quarter | `⌃⌥ J` |
| 8 | Bottom-Right Quarter | `⌃⌥ K` |
| 9 | First Third | `⌃⌥ D` |
| 10 | Center Third | `⌃⌥ F` |
| 11 | Last Third | `⌃⌥ G` |
| 12 | Top Third | `⌃⌥⇧ ↑` |
| 13 | Middle Third | `⌃⌥⇧ →` |
| 14 | Bottom Third | `⌃⌥⇧ ↓` |
| 15 | Left Two-Thirds | `⌃⌥ E` |
| 16 | Right Two-Thirds | `⌃⌥ T` |
| 17 | Top Two-Thirds | `⌃⌥⇧ U` |
| 18 | Bottom Two-Thirds | `⌃⌥⇧ J` |
| 19 | Top-Left Sixth | `⌃⌥⇧ 1` |
| 20 | Top-Center Sixth | `⌃⌥⇧ 2` |
| 21 | Top-Right Sixth | `⌃⌥⇧ 3` |
| 22 | Bottom-Left Sixth | `⌃⌥⇧ 4` |
| 23 | Bottom-Center Sixth | `⌃⌥⇧ 5` |
| 24 | Bottom-Right Sixth | `⌃⌥⇧ 6` |
| 25 | Almost Maximize | `⌃⌥ ↩` |
| 26 | Throw to Next Display | `⌃⌥⌘ →` |
| 27 | Throw to Prev Display | `⌃⌥⌘ ←` |

### Appendix B: Geometry Types (`util/geometry.zig`)

```zig
pub const Point = struct {
    x: f64,
    y: f64,
};

pub const Size = struct {
    width: f64,
    height: f64,
};

pub const Rect = struct {
    origin: Point,
    size: Size,

    pub fn contains(self: Rect, point: Point) bool {
        return point.x >= self.origin.x and
               point.x <= self.origin.x + self.size.width and
               point.y >= self.origin.y and
               point.y <= self.origin.y + self.size.height;
    }

    pub fn intersects(self: Rect, other: Rect) bool {
        return !(self.origin.x + self.size.width < other.origin.x or
                 other.origin.x + other.size.width < self.origin.x or
                 self.origin.y + self.size.height < other.origin.y or
                 other.origin.y + other.size.height < self.origin.y);
    }

    pub fn center(self: Rect) Point {
        return .{
            .x = self.origin.x + self.size.width / 2.0,
            .y = self.origin.y + self.size.height / 2.0,
        };
    }
};
```

### Appendix C: External References

| Resource | URL |
|---|---|
| Zig Language Reference | https://ziglang.org/documentation/master/ |
| zig-objc Library | https://github.com/hexops/zig-objc |
| Apple Accessibility API | https://developer.apple.com/documentation/applicationservices/axuielement_h |
| Quartz Event Services | https://developer.apple.com/documentation/coregraphics/quartz_event_services |
| CGDisplay API | https://developer.apple.com/documentation/coregraphics/cgdisplay |
| SMAppService (Login Items) | https://developer.apple.com/documentation/servicemanagement/smappservice |
| SF Symbols | https://developer.apple.com/sf-symbols/ |
| Apple Notarization Guide | https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution |

---

*End of Technical Requirements Document*
