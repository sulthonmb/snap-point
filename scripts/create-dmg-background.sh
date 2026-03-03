#!/bin/bash
# create-dmg-background.sh
# Generate and apply a background image to the SnapPoint DMG.
#
# This script:
#   1. Generates a simple gradient background PNG using sips/Python
#   2. Applies it to the DMG using AppleScript (Finder window customization)
#
# Prerequisites:
#   - Python 3 (bundled with macOS 12+)
#   - A writable DMG mounted at the given mount point
#
# Usage (internal, called by create-dmg.sh):
#   ./scripts/create-dmg-background.sh <mount_point> <app_name>
#
# Standalone usage to regenerate resources/dmg-background.png:
#   ./scripts/create-dmg-background.sh --generate-only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKGROUND_FILE="$PROJECT_ROOT/resources/dmg-background.png"
GENERATE_ONLY=false
MOUNT_POINT="${1:-}"
APP_NAME="${2:-SnapPoint}"

if [[ "${1:-}" == "--generate-only" ]]; then
    GENERATE_ONLY=true
fi

# ── Color helpers ─────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
pass() { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }

# ── Generate background PNG ───────────────────────────────────────────────────
generate_background() {
    echo ""
    echo "=== Generating DMG Background ==="

    # Use Python 3 (bundled with macOS) to create a gradient PNG
    # DMG window size: 600x400 pt (standard installer canvas)
    python3 - <<'PYEOF'
import struct
import zlib
import math

WIDTH, HEIGHT = 600, 400

def make_png(width, height, pixels):
    """Encode raw RGB pixel data as a minimal PNG."""
    def chunk(name, data):
        c = struct.pack('>I', len(data)) + name + data
        return c + struct.pack('>I', zlib.crc32(name + data) & 0xFFFFFFFF)

    # IHDR
    ihdr_data = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    ihdr = chunk(b'IHDR', ihdr_data)

    # IDAT: scanlines with filter byte 0
    raw_rows = b''
    for y in range(height):
        row = b'\x00'  # no-filter
        for x in range(width):
            raw_rows += b'\x00'  # placeholder; filled below
        raw_rows = raw_rows[:-width]  # undo placeholder
        scanline = bytearray()
        for x in range(width):
            r, g, b = pixels[y * width + x]
            scanline += bytes([r, g, b])
        raw_rows += b'\x00' + bytes(scanline)

    compressed = zlib.compress(raw_rows, 9)
    idat = chunk(b'IDAT', compressed)
    iend = chunk(b'IEND', b'')

    return b'\x89PNG\r\n\x1a\n' + ihdr + idat + iend

pixels = []
# Dark purple-to-charcoal gradient (matches macOS dark UI aesthetic)
for y in range(HEIGHT):
    for x in range(WIDTH):
        t = y / HEIGHT  # 0=top, 1=bottom
        # Top: dark violet-grey, Bottom: near-black charcoal
        r = int(30 + (18 - 30) * t)
        g = int(28 + (18 - 28) * t)
        b = int(38 + (24 - 38) * t)

        # Subtle vignette at corners
        cx = (x - WIDTH / 2) / (WIDTH / 2)
        cy = (y - HEIGHT / 2) / (HEIGHT / 2)
        vignette = 1.0 - 0.15 * (cx * cx + cy * cy)
        r = max(0, min(255, int(r * vignette)))
        g = max(0, min(255, int(g * vignette)))
        b = max(0, min(255, int(b * vignette)))
        pixels.append((r, g, b))

import sys, os
out_path = os.environ.get('BACKGROUND_OUT', '/dev/stdout')
data = make_png(WIDTH, HEIGHT, pixels)
with open(out_path, 'wb') as f:
    f.write(data)
PYEOF

    return 0
}

# Generate the background file
BACKGROUND_OUT="$BACKGROUND_FILE" generate_background
if [[ -f "$BACKGROUND_FILE" ]]; then
    pass "Background image: $BACKGROUND_FILE"
    SIZE=$(stat -f%z "$BACKGROUND_FILE" 2>/dev/null || stat --printf="%s" "$BACKGROUND_FILE")
    echo "  Size: ${SIZE} bytes"
else
    warn "Background image generation failed — using plain DMG"
    exit 0
fi

if $GENERATE_ONLY; then
    echo ""
    echo "Background image generated at: $BACKGROUND_FILE"
    echo "Open with: open \"$BACKGROUND_FILE\""
    exit 0
fi

# ── Apply background to mounted DMG ──────────────────────────────────────────
if [[ -z "$MOUNT_POINT" ]]; then
    warn "No mount point provided — background image generated but not applied"
    exit 0
fi

if [[ ! -d "$MOUNT_POINT" ]]; then
    warn "Mount point not found: $MOUNT_POINT"
    exit 0
fi

echo ""
echo "=== Applying Background to DMG ==="

# Copy background into a hidden .background folder inside the DMG
BG_DIR="$MOUNT_POINT/.background"
mkdir -p "$BG_DIR"
cp "$BACKGROUND_FILE" "$BG_DIR/background.png"
pass "Copied background to $BG_DIR/background.png"

# Use AppleScript to set the Finder window appearance
# This sets: background image, icon positions, window size, view options
osascript <<APPLESCRIPT || warn "AppleScript customization failed (Finder may not be running)"
tell application "Finder"
    tell disk (POSIX file "$MOUNT_POINT" as alias)
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 1000, 500}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set background picture of theViewOptions to ¬
            file ".background:background.png"
        set position of item "${APP_NAME}.app" of container window to {150, 190}
        set position of item "Applications" of container window to {450, 190}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

pass "DMG window appearance configured"
echo ""
echo "Background image applied. The DMG Finder window will show:"
echo "  - SnapPoint.app on the left (icon position: 150, 190)"
echo "  - Applications symlink on the right (icon position: 450, 190)"
echo "  - Dark gradient background"
