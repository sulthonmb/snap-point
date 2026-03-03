# Contributing to SnapPoint

Thank you for your interest in contributing! SnapPoint is a small, focused
utility and we welcome bug reports, feature proposals, and pull requests.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Submitting a Pull Request](#submitting-a-pull-request)
- [Reporting Bugs](#reporting-bugs)
- [Requesting Features](#requesting-features)
- [Code Style](#code-style)
- [Architecture Notes](#architecture-notes)

---

## Code of Conduct

Be respectful. We follow the
[Contributor Covenant v2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).

---

## Getting Started

### Prerequisites

| Tool | Version | Install |
|---|---|---|
| macOS | 13.0+ | — |
| Zig | 0.15+ | `brew install zig` or [zigup](https://github.com/marler8997/zigup) |
| Xcode CLT | latest | `xcode-select --install` |

### Clone and build

```sh
git clone https://github.com/sulthonmb/snap-point.git
cd snap-point
zig build                # debug build
zig build bundle         # assemble .app
./scripts/run-dev.sh     # build + launch from bundle
```

### Grant Accessibility permission

The app **must run from the `.app` bundle** for macOS to register it in
`System Settings → Privacy & Security → Accessibility`.

Run `./scripts/run-dev.sh`, then toggle SnapPoint on in System Settings.
Relaunch afterwards.

---

## Development Workflow

### Running tests

```sh
zig build test               # unit tests only
zig build test-integration   # macOS system interaction tests
zig build test-all           # all tests
```

Integration tests require a graphical session and, for some tests,
Accessibility permission. They are designed to *not crash* if permission
is not granted, but verification will be skipped.

### Validating the binary

```sh
./scripts/validate-binary.sh           # development checks
./scripts/validate-binary.sh --release # strict distribution checks
```

### Compatibility testing

```sh
./scripts/test-compat.sh
```

Logs are saved to `test-results/`. Run this on each macOS major version you
want to verify.

---

## Submitting a Pull Request

1. **Fork** the repository and create a branch from `main`:
   ```sh
   git checkout -b fix/my-bugfix
   ```

2. **Make your changes.** Keep commits small and focused.

3. **Add or update tests** for any changed behaviour. The test suite lives in
   `tests/`.

4. **Run the full test suite** and ensure it passes:
   ```sh
   zig build test-all
   ```

5. **Update `CHANGELOG.md`** under `[Unreleased]` with a brief description of
   your change.

6. **Open a pull request** against `main`. Fill in the PR template, including:
   - What problem it solves
   - How you tested it
   - Any macOS versions you tested on

### PR requirements

- All CI checks must pass
- No un-addressed test failures
- Code follows the style guide below
- Sensitive credentials must never appear in commits

---

## Reporting Bugs

Open a [GitHub Issue](https://github.com/sulthonmb/snap-point/issues/new)
and include:

- macOS version (`sw_vers`)
- SnapPoint version
- Steps to reproduce
- Expected vs. actual behaviour
- Relevant Console.app logs (filter by `SnapPoint`)

---

## Requesting Features

Open a GitHub Issue with the `enhancement` label. Describe:

- The use-case / problem you're trying to solve
- Your proposed solution (optional)
- Any alternatives you've considered

---

## Code Style

SnapPoint is written in Zig 0.15. Follow these conventions:

### Naming

| Construct | Convention | Example |
|---|---|---|
| Types, structs | `PascalCase` | `WindowController` |
| Functions, methods | `camelCase` | `getFocusedWindow` |
| Variables, fields | `snake_case` | `snap_sensitivity` |
| Constants | `snake_case` | `default_gap` |
| Comptime constants | `snake_case` | `layout_count` |

### Formatting

- Use `zig fmt` before committing: `zig fmt src/ tests/`
- 4-space indentation (Zig default)
- Maximum line length: 100 characters

### Error handling

- Prefer explicit error unions (`!T`) over sentinel values
- Propagate errors with `try`; handle locally only when meaningful recovery is possible
- Log errors at the appropriate `os_log` level before returning

### Memory

- Use the appropriate allocator for the lifetime of the allocation:
  - `GlobalAllocator` (arena) — lives for the process lifetime
  - `RequestAllocator` (arena) — freed after each snap event
  - `std.heap.page_allocator` — only for ObjC objects that outlive arenas
- Never pass allocators through ObjC boundaries

---

## Architecture Notes

A quick map to help you find the right file:

| Area | File |
|---|---|
| App startup / shutdown | `src/core/app.zig` |
| Config load / save | `src/core/config.zig` |
| Layout definitions (all 25) | `src/engine/layout.zig` |
| Snap decision | `src/engine/snap.zig` |
| Edge/corner trigger zones | `src/engine/zone.zig` |
| Window position restore | `src/engine/restore.zig` |
| Accessibility (AXUIElement) | `src/platform/accessibility.zig` |
| Display enumeration | `src/platform/display.zig` |
| Mouse/keyboard event tap | `src/platform/event_tap.zig` |
| Global hotkeys | `src/platform/hotkey.zig` |
| ObjC interop helpers | `src/objc/bridge.zig` |
| Ghost window preview | `src/ui/ghost_window.zig` |
| Settings window | `src/ui/settings_window.zig` |
| Onboarding | `src/ui/onboarding.zig` |

For a full technical deep-dive, see the
[Technical Requirements Document](Technical%20Requirements%20Document%20-%20SnapPoint.md).
