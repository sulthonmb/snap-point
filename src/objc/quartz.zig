//! Quartz / CoreGraphics C-API declarations for direct @cImport usage.
//! CGEventTap and CGDisplay calls are made via these C bindings.

pub const c = @cImport({
    @cInclude("CoreGraphics/CoreGraphics.h");
    @cInclude("ApplicationServices/ApplicationServices.h");
});

// ── CGEventType constants ────────────────────────────────────────────────
pub const EventType = struct {
    pub const mouse_moved         : u32 = 5;
    pub const left_mouse_down     : u32 = 1;
    pub const left_mouse_up       : u32 = 2;
    pub const left_mouse_dragged  : u32 = 6;
    pub const key_down            : u32 = 10;
    pub const key_up              : u32 = 11;
    pub const flags_changed       : u32 = 12;
    pub const tap_disabled_by_timeout: u32 = 0xFFFFFFFE;
    pub const tap_disabled_by_user_input: u32 = 0xFFFFFFFF;
};

// ── CGEventFlags modifier bitmask ────────────────────────────────────────
pub const EventFlag = struct {
    pub const shift    : u64 = 0x00020000;
    pub const control  : u64 = 0x00040000;
    pub const option   : u64 = 0x00080000;
    pub const command  : u64 = 0x00100000;
};

// ── CGEventTapLocation ───────────────────────────────────────────────────
pub const TapLocation = enum(c_int) {
    cghid_event_tap       = 0, // intercept HID events before WindowServer
    cg_session_event_tap  = 1, // per-session events
    cg_annotation_event_tap = 2,
};

// ── AXUIElement attribute name constants ─────────────────────────────────
pub const kAXPositionAttribute = "AXPosition";
pub const kAXSizeAttribute     = "AXSize";
pub const kAXWindowsAttribute  = "AXWindows";
pub const kAXFocusedWindowAttribute = "AXFocusedWindow";
pub const kAXRoleAttribute     = "AXRole";
pub const kAXTitleAttribute    = "AXTitle";

// ── Display helpers (CGDisplay) ──────────────────────────────────────────
pub const kCGNullDirectDisplay: u32 = 0;
pub const kCGDirectMainDisplay: u32 = 1; // runtime value, use CGMainDisplayID()
