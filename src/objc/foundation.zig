//! Foundation framework class names and selector constants.

// ── Class names ─────────────────────────────────────────────────────────
pub const cls_NSString       = "NSString";
pub const cls_NSMutableString= "NSMutableString";
pub const cls_NSArray        = "NSArray";
pub const cls_NSMutableArray = "NSMutableArray";
pub const cls_NSDictionary   = "NSDictionary";
pub const cls_NSUserDefaults = "NSUserDefaults";
pub const cls_NSBundle       = "NSBundle";
pub const cls_NSTimer        = "NSTimer";
pub const cls_NSRunLoop      = "NSRunLoop";
pub const cls_NSNotificationCenter = "NSNotificationCenter";
pub const cls_NSFileManager  = "NSFileManager";
pub const cls_NSURL          = "NSURL";
pub const cls_NSData         = "NSData";
pub const cls_NSNumber       = "NSNumber";

// ── Selector strings ────────────────────────────────────────────────────
pub const sel_stringWithUTF8String_  = "stringWithUTF8String:";
pub const sel_UTF8String             = "UTF8String";
pub const sel_length                 = "length";
pub const sel_standardUserDefaults   = "standardUserDefaults";
pub const sel_objectForKey_          = "objectForKey:";
pub const sel_setObject_forKey_      = "setObject:forKey:";
pub const sel_mainBundle             = "mainBundle";
pub const sel_bundleIdentifier       = "bundleIdentifier";
pub const sel_defaultCenter          = "defaultCenter";
pub const sel_mainRunLoop            = "mainRunLoop";
pub const sel_currentRunLoop         = "currentRunLoop";
pub const sel_run                    = "run";
pub const sel_fileURLWithPath_       = "fileURLWithPath:";
pub const sel_URLWithString_         = "URLWithString:";
pub const sel_absoluteString         = "absoluteString";

// ── NSNotification names ────────────────────────────────────────────────
pub const notification_ApplicationDidFinishLaunching
    = "NSApplicationDidFinishLaunchingNotification";
pub const notification_ApplicationWillTerminate
    = "NSApplicationWillTerminateNotification";
pub const notification_ScreenParametersChanged
    = "NSApplicationDidChangeScreenParametersNotification";
