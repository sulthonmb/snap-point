//! Centralised AppKit class names and selector constants.
//! Import and use these rather than scattering string literals.

// ── Class names ─────────────────────────────────────────────────────────
pub const cls_NSApplication         = "NSApplication";
pub const cls_NSStatusBar           = "NSStatusBar";
pub const cls_NSStatusItem          = "NSStatusItem";
pub const cls_NSMenu                = "NSMenu";
pub const cls_NSMenuItem            = "NSMenuItem";
pub const cls_NSWindow              = "NSWindow";
pub const cls_NSView                = "NSView";
pub const cls_NSVisualEffectView    = "NSVisualEffectView";
pub const cls_NSImage               = "NSImage";
pub const cls_NSWorkspace           = "NSWorkspace";
pub const cls_NSScreen              = "NSScreen";
pub const cls_NSRunningApplication  = "NSRunningApplication";
pub const cls_NSColor               = "NSColor";
pub const cls_NSButton              = "NSButton";
pub const cls_NSTextField           = "NSTextField";
pub const cls_NSSlider              = "NSSlider";
pub const cls_NSSwitch              = "NSSwitch";
pub const cls_NSTableView           = "NSTableView";
pub const cls_NSSplitView           = "NSSplitView";
pub const cls_NSOutlineView         = "NSOutlineView";
pub const cls_NSOpenPanel           = "NSOpenPanel";

// ── Selector strings ────────────────────────────────────────────────────
pub const sel_sharedApplication     = "sharedApplication";
pub const sel_run                   = "run";
pub const sel_terminate_            = "terminate:";
pub const sel_setActivationPolicy_  = "setActivationPolicy:";
pub const sel_setDelegate_          = "setDelegate:";
pub const sel_systemStatusBar       = "systemStatusBar";
pub const sel_statusItemWithLength_ = "statusItemWithLength:";
pub const sel_setImage_             = "setImage:";
pub const sel_setMenu_              = "setMenu:";
pub const sel_addItem_              = "addItem:";
pub const sel_setTitle_             = "setTitle:";
pub const sel_imageNamed_           = "imageNamed:";
pub const sel_setTarget_            = "setTarget:";
pub const sel_setAction_            = "setAction:";
pub const sel_alloc                 = "alloc";
pub const sel_init                  = "init";
pub const sel_release               = "release";
pub const sel_autorelease           = "autorelease";

// ── NSApplicationActivationPolicy (NSInteger) ────────────────────────────
pub const ActivationPolicyRegular    : c_long = 0;
pub const ActivationPolicyAccessory  : c_long = 1;
pub const ActivationPolicyProhibited : c_long = 2;

// ── NSVisualEffectView material values ───────────────────────────────────
pub const VisualEffectMaterialHUDWindow   : c_long = 23;
pub const VisualEffectMaterialFullScreenUI: c_long = 15;
pub const VisualEffectBlendingBehindWindow: c_long = 0;
pub const VisualEffectStateActive         : c_long = 1;

// ── NSWindow style masks (bitmask) ───────────────────────────────────────
pub const WindowStyleBorderless       : c_ulong = 0;
pub const WindowStyleTitled           : c_ulong = 1 << 0;
pub const WindowStyleClosable         : c_ulong = 1 << 1;
pub const WindowStyleMiniaturizable   : c_ulong = 1 << 2;
pub const WindowStyleResizable        : c_ulong = 1 << 3;
pub const WindowStyleFullSizeContentView: c_ulong = 1 << 15;

// ── NSWindow level values ───────────────────────────────────────────────
pub const WindowLevelNormal      : c_int = 0;
pub const WindowLevelStatusBar   : c_int = 25;
pub const WindowLevelFloating    : c_int = 3;
pub const WindowLevelMainMenu    : c_int = 24;

// ── NSBackingStoreType ───────────────────────────────────────────────────
pub const BackingStoreBuffered   : c_ulong = 2;
