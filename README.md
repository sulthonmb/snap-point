# SnapPoint

High-performance macOS window manager built with Zig.

Snap windows to any of 25 precise layouts using configurable keyboard shortcuts
or by dragging to screen edges — with zero CPU cost at idle.

---

## Features

- **25 preset layouts** — halves, quarters, thirds, two-thirds, sixths, and
  Almost Maximize (95% screen fill)
- **Edge & corner trigger zones** — drag a window to any screen edge or corner
  to snap it instantly
- **Restorative unsnapping** — drag away from a snapped position to restore the
  original window size
- **27 configurable hotkeys** — 25 layouts + throw-to-next/prev-display
- **Multi-monitor throw** — move windows across displays with `⌃⌥⌘→ / ⌃⌥⌘←`
- **Ghost window preview** — translucent overlay shows the target layout while
  dragging
- **App blacklist** — exclude apps that should manage their own windows
- **< 100 KB binary** — minimal resource footprint; invisible in Activity
  Monitor memory charts
- **macOS 13–16** — Ventura, Sonoma, Sequoia, Tahoe

---

## Requirements

| Dependency | Version |
|---|---|
| macOS | 13.0 (Ventura) or later |
| Zig | 0.15+ |
| Xcode Command Line Tools | latest |

```sh
xcode-select --install           # install Xcode CLT
brew install zig                 # or use zigup: https://github.com/marler8997/zigup
```

---

## Installation

### Download DMG (recommended)

1. Download the latest `SnapPoint-x.y.z.dmg` from
   [Releases](https://github.com/YOUR_USERNAME/snap-point/releases).
2. Open the DMG and drag **SnapPoint.app** to your Applications folder.
3. Launch SnapPoint from Applications.
4. Follow the three-step onboarding to grant Accessibility permission.

### Build from source

```sh
git clone https://github.com/YOUR_USERNAME/snap-point.git
cd snap-point
zig build bundle                 # builds .app in zig-out/SnapPoint.app
./scripts/run-dev.sh             # launch from bundle (required for Accessibility)
```

---

## Build

```sh
zig build                          # debug build
zig build -Doptimize=ReleaseSmall  # release build (min binary size)
zig build bundle                   # build + assemble .app bundle
zig build run                      # build and run (bare binary, no bundle)
```

---

## Testing

```sh
zig build test                     # run unit tests
zig build test-integration         # run macOS integration tests (needs Accessibility)
zig build test-all                 # run all tests
```

### Test Suites

| Suite | Description |
|---|---|
| `test_layout` | Layout geometry and resolution for all 25 layouts |
| `test_geometry` | Rect/Point/Size math utilities |
| `test_config` | Config struct defaults, validation, and blacklist |
| `test_zone` | Edge/corner trigger zone detection |
| `test_hotkey` | Keyboard shortcut matching and conflict detection |
| `test_abi` | C/ObjC ABI compatibility |
| `test_config_persistence` | JSON serialization round-trips |
| `test_memory` | Arena allocator and leak detection |
| `test_snap` | Snap action dispatch and enum coverage |
| `test_settings` | Shortcut formatting, layout names, reset-defaults logic |
| `integration_runner` | Live macOS system interaction (display, AX, CGEvent) |

### Integration tests and Accessibility

Integration tests call `AXIsProcessTrusted()` at runtime. To run the full
suite with accessibility checks enabled, grant the **Accessibility** permission
to whichever process executes the tests:

```sh
# Open the Accessibility pane in System Settings and add Terminal (or your IDE)
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

# Or grant via tccutil (requires sudo)
sudo tccutil add Accessibility com.apple.Terminal

# Verify the grant took effect
zig build test-integration 2>&1 | grep '\[info\]'
# → [info] Accessibility is GRANTED
```

Tests that require accessibility will automatically skip (not fail) when run
without the permission.

---

## Default Keyboard Shortcuts

### Halves

| Action | Shortcut |
|---|---|
| Left Half | `⌃⌥ ←` |
| Right Half | `⌃⌥ →` |
| Top Half | `⌃⌥ ↑` |
| Bottom Half | `⌃⌥ ↓` |

### Quarters

| Action | Shortcut |
|---|---|
| Top-Left Quarter | `⌃⌥ U` |
| Top-Right Quarter | `⌃⌥ I` |
| Bottom-Left Quarter | `⌃⌥ J` |
| Bottom-Right Quarter | `⌃⌥ K` |

### Thirds

| Action | Shortcut |
|---|---|
| First Third | `⌃⌥ D` |
| Center Third | `⌃⌥ F` |
| Last Third | `⌃⌥ G` |
| Top Third | `⌃⌥⇧ ↑` |
| Middle Third | `⌃⌥⇧ →` |
| Bottom Third | `⌃⌥⇧ ↓` |

### Two-Thirds

| Action | Shortcut |
|---|---|
| Left Two-Thirds | `⌃⌥ E` |
| Right Two-Thirds | `⌃⌥ T` |
| Top Two-Thirds | `⌃⌥⇧ U` |
| Bottom Two-Thirds | `⌃⌥⇧ J` |

### Sixths

| Action | Shortcut |
|---|---|
| Top-Left Sixth | `⌃⌥⇧ 1` |
| Top-Center Sixth | `⌃⌥⇧ 2` |
| Top-Right Sixth | `⌃⌥⇧ 3` |
| Bottom-Left Sixth | `⌃⌥⇧ 4` |
| Bottom-Center Sixth | `⌃⌥⇧ 5` |
| Bottom-Right Sixth | `⌃⌥⇧ 6` |

### Focus & Multi-Monitor

| Action | Shortcut |
|---|---|
| Almost Maximize | `⌃⌥ ↩` |
| Throw to Next Display | `⌃⌥⌘ →` |
| Throw to Prev Display | `⌃⌥⌘ ←` |

All shortcuts are reconfigurable in **Settings → Keyboard**.

---

## Binary Validation

```sh
./scripts/validate-binary.sh           # development checks
./scripts/validate-binary.sh --release # strict distribution checks
```

Checks: architecture (universal), binary size, Info.plist validity,
code signature, entitlements, minimum OS version, dynamic dependencies.

---

## Performance Profiling

```sh
./scripts/profile.sh                          # Time Profiler, 30s
./scripts/profile.sh --time 60                # 60-second sample
./scripts/profile.sh --instrument Allocations # memory profiling
```

Performance budgets:

| Metric | Budget |
|---|---|
| Binary size | < 100 KB |
| Resident RAM (idle) | < 20 MB |
| Snap execution latency | < 16 ms |
| CPU (idle) | < 0.1% |

---

## Distribution Pipeline

```sh
# Full release: build → sign → notarize → DMG
APPLE_TEAM_ID=... APPLE_ID=... APPLE_APP_PASSWORD=... \
    ./scripts/build-release.sh 1.0.0

# Development DMG (unsigned, skips notarization)
SKIP_SIGN=1 SKIP_NOTARIZE=1 ./scripts/build-release.sh 1.0.0
```

Individual steps:

```sh
./scripts/sign-release.sh      # code sign the bundle
./scripts/notarize.sh          # submit to Apple Notary Service + staple
./scripts/create-dmg.sh 1.0.0  # package into DMG
```

---

## Compatibility Testing

```sh
./scripts/test-compat.sh
```

Runs unit tests, integration tests, and binary validation on the current
macOS version. Results are saved to `test-results/`.

---

## Architecture

SnapPoint is a **macOS agent application** (no Dock icon):

```
CGEventTap (mouse drag)
    │
    ├─ Dragging window titlebar? → Enter SNAP_TRACKING mode
    │
    ├─ Mouse moved → evaluate trigger zones → show ghost window
    │
    └─ Mouse up   → apply snap via AXUIElement → clear ghost window

CGEventTap (key down)
    └─ Matches hotkey? → executeSnap(action)
```

Key modules:

| Module | Path | Responsibility |
|---|---|---|
| App lifecycle | `src/core/app.zig` | init, run, shutdown |
| Layout definitions | `src/engine/layout.zig` | 25 comptime layouts |
| Snap engine | `src/engine/snap.zig` | layout → AX frame set |
| Trigger zones | `src/engine/zone.zig` | edge/corner detection |
| Event tap | `src/platform/event_tap.zig` | CGEventTap setup |
| Hotkeys | `src/platform/hotkey.zig` | global shortcut dispatch |
| Accessibility | `src/platform/accessibility.zig` | AXUIElement wrapper |
| Display manager | `src/platform/display.zig` | multi-monitor topology |
| Ghost window | `src/ui/ghost_window.zig` | snap preview overlay |
| Settings | `src/ui/settings_window.zig` | settings UI |
| Onboarding | `src/ui/onboarding.zig` | first-launch flow |

For the full technical specification, see
[Technical Requirements Document](Technical%20Requirements%20Document%20-%20SnapPoint.md).

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, coding style,
and PR guidelines.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

---

## License

MIT — see [LICENSE](LICENSE).
