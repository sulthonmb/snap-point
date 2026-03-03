//! Global hotkey manager.
//! Maps key-code + modifier combos to snap Actions.
//! The matching logic is called from the CGEventTap callback on keyDown events.
//! No ObjC or framework dependencies – pure Zig.

const config_mod = @import("../core/config.zig");
const constants  = @import("../core/constants.zig");
const log        = @import("../core/log.zig");
const snap       = @import("../engine/snap.zig");

// ── CGEventFlags modifier bitmasks (from CGEventTypes.h) ─────────────────

pub const CGEventFlags = u64;
pub const kCGEventFlagMaskShift     : CGEventFlags = 0x0002_0000;
pub const kCGEventFlagMaskControl   : CGEventFlags = 0x0004_0000;
pub const kCGEventFlagMaskAlternate : CGEventFlags = 0x0008_0000; // Option
pub const kCGEventFlagMaskCommand   : CGEventFlags = 0x0010_0000;

// Mask of all modifier bits we care about.
pub const kModifierMask: CGEventFlags =
    kCGEventFlagMaskShift | kCGEventFlagMaskControl |
    kCGEventFlagMaskAlternate | kCGEventFlagMaskCommand;

// ── HotkeyManager ────────────────────────────────────────────────────────

pub const HotkeyManager = struct {
    bindings: [constants.action_count]config_mod.Shortcut,

    /// Initialise from the loaded config.
    pub fn init(config: *const config_mod.Config) HotkeyManager {
        return .{ .bindings = config.shortcuts };
    }

    /// Reload bindings from an updated config (e.g. after settings save).
    pub fn reload(self: *HotkeyManager, config: *const config_mod.Config) void {
        self.bindings = config.shortcuts;
    }

    /// Called from the CGEventTap callback on every keyDown event.
    /// Returns the matching `snap.Action` if a binding is found, else null.
    pub fn handleKeyEvent(
        self: *HotkeyManager,
        key_code: u16,
        flags:    CGEventFlags,
    ) ?snap.Action {
        for (self.bindings, 0..) |binding, i| {
            if (!binding.enabled) continue;
            if (binding.key_code == key_code and modifiersMatch(binding, flags)) {
                const action: snap.Action = @enumFromInt(i);
                log.debug("hotkey: matched action={d} key={d}", .{ i, key_code });
                return action;
            }
        }
        return null;
    }
};

// ── Internal ──────────────────────────────────────────────────────────────

/// Return true when the shortcut's modifier requirements match `flags`.
/// We only compare the four modifiers we support; other bits (e.g. NumLock)
/// are ignored.
pub fn modifiersMatch(shortcut: config_mod.Shortcut, flags: CGEventFlags) bool {
    const ctrl  = (flags & kCGEventFlagMaskControl)   != 0;
    const opt   = (flags & kCGEventFlagMaskAlternate) != 0;
    const cmd   = (flags & kCGEventFlagMaskCommand)   != 0;
    const shift = (flags & kCGEventFlagMaskShift)     != 0;
    return shortcut.modifiers.ctrl  == ctrl
       and shortcut.modifiers.opt   == opt
       and shortcut.modifiers.cmd   == cmd
       and shortcut.modifiers.shift == shift;
}

/// Build the CGEventMask bit for a given CGEventType numeric value.
pub inline fn eventBit(event_type: u6) u64 {
    return @as(u64, 1) << event_type;
}
