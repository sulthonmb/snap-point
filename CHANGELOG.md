# Changelog

All notable changes to SnapPoint are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Planned
- Workspace Snapshots: save and restore multi-window arrangements
- AI-driven layout suggestions based on open applications
- Tahoe-native hardware "Lensing" material for ghost window

---

## [1.0.0] — 2026-03-02

Initial public release.

### Added

**Snapping Engine**
- 25 predefined window layouts across 6 categories: Standard, Thirds, Portrait Thirds, Two-Thirds, Sixths, and Focus
- Edge trigger zones: drag a window to any screen edge to snap it
- Corner trigger zones: drag to a corner to snap to a 25% quadrant
- Bottom-edge thirds detection based on horizontal cursor position
- Restorative unsnapping: dragging away from a snap restores the original window dimensions
- Per-display safe-area awareness (menu bar and Dock excluded)

**Global Hotkeys**
- 27 configurable keyboard shortcuts (25 layouts + 2 multi-monitor actions)
- Default shortcut set: `⌃⌥` + arrow/letter keys
- CGEventTap-based interception (no deprecated Carbon RegisterEventHotKey)
- Conflict detection during shortcut recording

**Multi-Monitor Support**
- Throw window to next/previous display (`⌃⌥⌘→` / `⌃⌥⌘←`)
- Proportional position preservation when throwing
- Dynamic display topology updates on connect/disconnect/rearrange
- Retina (HiDPI) display scaling support

**User Interface**
- Menu-bar agent: no Dock icon, no "app is not responding" dialogs
- Status bar menu with all 25 layouts, submenus for Thirds/Two-Thirds/Sixths
- "Ignore [App]" contextual toggle showing the frontmost application name
- Ghost window snap preview using `NSVisualEffectView` (`.hudWindow` material)
- 150 ms fade-in / 100 ms fade-out animation on ghost window
- Settings window (800 × 600 pt, sidebar layout)
  - General: launch-at-login (`SMAppService`), snap sensitivity, ghost toggle
  - Keyboard: shortcut recorder for all 27 actions with conflict checking
  - Visuals: window gap (0–50 px) and ghost opacity (0.1–1.0) sliders
  - Blacklist: add/remove apps by bundle identifier

**Onboarding**
- Three-step modal for first-launch guidance
- Accessibility permission deep-link to System Settings
- 1-second polling with auto-advance after permission is granted
- Initial shortcut set picker (Compact / Full / Custom)

**Platform & Infrastructure**
- Written in Zig 0.15+ with `zig-objc` for Objective-C runtime interop
- Arena allocators for per-snap-event memory (zero GC pauses)
- 25 layout geometries resolved at compile-time (`comptime`)
- Binary target: < 100 KB (`ReleaseSmall`)
- Atomic config writes to prevent corruption on crash
- Structured logging via `os_log` (visible in Console.app)
- Universal binary (ARM64 + x86_64)
- Notarized DMG distribution
- macOS 13.0 (Ventura) through macOS 16 (Tahoe) support

---

## Release Notes Format

Each release section uses the following change types:

| Type | Description |
|---|---|
| **Added** | New features |
| **Changed** | Changes to existing behaviour |
| **Deprecated** | Features that will be removed in a future release |
| **Removed** | Features removed in this release |
| **Fixed** | Bug fixes |
| **Security** | Security-related fixes or improvements |

[Unreleased]: https://github.com/YOUR_USERNAME/snap-point/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/YOUR_USERNAME/snap-point/releases/tag/v1.0.0
