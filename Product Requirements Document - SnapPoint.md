# Comprehensive Product Requirements Document: SnapPoint

**Project Name:** SnapPoint

**Platform:** macOS (13.0+)

**Architecture:** Zig (Systems Programming Language)

**License:** MIT (Open Source)


## 1. Executive Summary

SnapPoint is a high-performance, open-source window management utility for macOS designed to bridge the gap between native system tiling and the advanced needs of professionals. While macOS Sequoia introduced basic tiling, it remains limited in layout variety and lacks the granular control required for complex multi-monitor workflows.<!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><sup><!----></sup><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----> Built with the **Zig** programming language, SnapPoint provides a professional-grade alternative that delivers ultra-low latency, a minimal resource footprint, and a "Mac-native" aesthetic that feels integrated into the operating system rather than layered upon it.<!----><!----><!----><!----><!---->


## 2. Strategic Positioning & Brand Identity

- **Core Value Proposition:** Precision window manipulation with zero performance overhead.

- **Target Audience:** Software developers, creative professionals, and ultra-wide monitor users who require more than standard 50/50 splits.

- **Visual Identity:** The "Invisibility" philosophy. The UI appears only during active interactions (snapping) or configuration, utilizing macOS Tahoe’s "Liquid Glass" design language for visual harmony.


## 3. Technical Architecture: Engineering with Zig

SnapPoint is architected to leverage the systems-level advantages of Zig for a background utility.


### 3.1 Framework Integration

- **Objective-C Interop:** Using the `zig-objc` library, the core engine interfaces directly with the macOS Objective-C runtime to call `AppKit` and `Foundation` APIs while maintaining manual memory management.

- **Accessibility API (AXUIElement):** Resizing logic utilizes the `AXUIElement` framework. The app operates as a trusted accessibility client, using `AXUIElementSetAttributeValue` to programmatically adjust `kAXPositionAttribute` and `kAXSizeAttribute`.

- **Global Event Monitoring:** A background daemon implements a `CGEventTap` via Quartz Event Services. This allows the app to intercept global hotkeys and mouse coordinates before they reach foreground applications.


### 3.2 Performance & Reliability

- **Memory Management:** Use of Arena allocators for request-scoped tasks (e.g., a single snap event) ensures that memory is reclaimed instantly without garbage collection pauses.

- **Compile-Time Optimization:** Mathematical calculations for the 25 layout geometries are resolved at compile-time using Zig's `comptime` feature, ensuring zero runtime CPU cycles are wasted on layout logic.

- **Minimal Footprint:** By avoiding heavy runtimes, the binary remains under 100 KB, ensuring it does not appear in "Heavy RAM" usage lists in Activity Monitor.


## 4. User Interface & Layout Specifications

### 4.1 Menu Bar (The Command Center)

A minimalist `NSStatusItem` utilizing SF Symbols 7 in hierarchical rendering mode.

- **Visual Style:** Icons illuminate upon hover using the `glass` button style.

- **Layout Sections:**

  - **Snapping Section:** Symbolic icons for immediate tiling (Halves, Quarters, Fullscreen).

  - **Advanced Submenu:** Nested layouts for Thirds and Sixths.

  - **Contextual Actions:** "Move to Next Display" (dynamic) and "Ignore \[Active App]" toggle.<!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><sup><!----></sup><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!---->

  - **Footer:** Settings, Check for Updates, and Quit.


### 4.2 Settings Window (Configuration Page)

A sidebar-based layout matching modern macOS Tahoe standards (800pt x 600pt).<!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><sup><!----></sup><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!---->

- **Navigation Sidebar (Left):** 200pt width, utilizes "Liquid Glass" material with a `sidebarAdaptable` style.

- **Content Area (Right):** 600pt width, featuring rounded corners with a 12pt radius.

- **Detailed Pages:**

  - **General:** Contains `glassProminent` switches for "Launch at login" and snap sensitivity pickers.

  - **Keyboard:** List of 25 actions with a recorder field using the `Zeys` module for virtual key codes.

  - **Visuals:** Sliders for "Window Gaps" (0px-50px) and "Ghost Window Opacity."

  - **Blacklist:** A `NSTableView` for ignored apps with a system-native `NSOpenPanel` picker.


### 4.3 Ghost Window (Snap Preview)

- **Technical Spec:** A borderless `NSWindow` set to `.statusBar` level that ignores all mouse events (`ignoresMouseEvents = true`).

- **Visual Design:** Uses `NSVisualEffectView` with "Lensing" material to refract the user's wallpaper rather than a simple blur.


### 4.4 Onboarding & Permissions

A three-step modal flow to acquire `AXUIElement` permissions.<!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><sup><!----></sup><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!---->

- **Step 1:** Looping hero video showing SnapPoint features in action.<!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><sup><!----></sup><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!---->

- **Step 2:** Deep link to `Privacy & Security > Accessibility` with a visual guide on toggling the permission.

- **Step 3:** Setup confirmation and selection of initial "Default Shortcut Set".


## 5. Detailed Feature Specifications

### 5.1 Advanced Snapping Engine

Coordinate-aware logic that respects the "Safe Area" of each display.

- **Edge Trigger Zones:** Top edge maximizes; left/right edges create halves; bottom edge triggers Thirds based on horizontal cursor position.<!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><sup><!----></sup><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!---->

- **Corner Trigger Zones:** Snaps to the four 25% quadrants.

- **Restorative Unsnapping:** Moving a window from a snapped position instantly restores its original pre-snap dimensions.


### 5.2 Predefined Layout Library (25 Presets)

| **Category**        | **Layouts** | **Description**                                                    |
| ------------------- | ----------- | ------------------------------------------------------------------ |
| **Standard**        | 1–8         | Left/Right/Top/Bottom Halves (50%) and 4 Corners (25%).            |
| **Thirds**          | 9–11        | Vertical 33.3% strips (First, Center, Last).                       |
| **Portrait Thirds** | 12–14       | Horizontal 33.3% strips for vertical monitor setups.               |
| **Two-Thirds**      | 15–18       | 66.6% blocks for focus + reference app arrangements.               |
| **Sixths**          | 19–24       | 3x2 grid layouts for high-density 5K/6K displays.                  |
| **Focus**           | 25          | **Almost Maximize:** 95% screen fill with a desktop "peek" margin. |


### 5.3 Power User Features

- **Multi-Monitor "Throw":** Global hotkeys (e.g., `Ctrl+Opt+Cmd+Right`) to move active windows across displays while maintaining snap state.<!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><sup><!----></sup><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!---->

- **Workspace Snapshots:** Saves current multi-window arrangements to persistent storage for instant recall.


## 6. Security, Distribution & Compliance

- **Distribution:** Distributed as a **notarized, non-sandboxed** DMG. This is required because the App Store sandbox prohibits the `AXUIElement` global control necessary for third-party window management.

- **Code Signing:** Signed with a Developer ID certificate to bypass Gatekeeper and satisfy macOS security protocols.<!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><sup><!----></sup><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!---->

- **Entitlements:** Declares `com.apple.security.accessibility` with a clear `NSAccessibilityUsageDescription`.<!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><sup><!----></sup><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!----><!---->


## 7. Roadmap

- **v1.0:** Core snapping engine, 25 layouts, hotkey support, and onboarding.

- **v1.1:** Workspace Snapshots and layout persistence.

- **v1.2:** Tahoe-native hardware "Lensing" support and AI-driven layout suggestions.
