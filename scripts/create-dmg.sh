#!/bin/bash
# create-dmg.sh
# Create a DMG installer for SnapPoint distribution.
#
# Usage:
#   ./scripts/create-dmg.sh [version]
#
# Example:
#   ./scripts/create-dmg.sh 1.0.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUNDLE="$PROJECT_ROOT/zig-out/SnapPoint.app"
VERSION="${1:-1.0.0}"
DMG_NAME="SnapPoint-${VERSION}.dmg"
DMG_PATH="$PROJECT_ROOT/$DMG_NAME"
STAGING_DIR="$PROJECT_ROOT/dmg-staging"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}!${NC} $1"; }

echo "╔════════════════════════════════════════════════════════════╗"
echo "║            SnapPoint DMG Creator                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  Version: $VERSION"
echo "  Output:  $DMG_NAME"
echo ""

# Check bundle exists
if [[ ! -d "$BUNDLE" ]]; then
    fail "App bundle not found at $BUNDLE"
fi

pass "Bundle found: $BUNDLE"

# Check signature
echo ""
echo "=== Verifying Signature ==="
if codesign --verify --deep --strict "$BUNDLE" 2>/dev/null; then
    pass "Code signature valid"
else
    warn "Bundle may not be properly signed"
fi

# Create staging directory
echo ""
echo "=== Preparing DMG Contents ==="
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Copy app bundle
cp -R "$BUNDLE" "$STAGING_DIR/"
pass "Copied SnapPoint.app"

# Create Applications symlink
ln -s /Applications "$STAGING_DIR/Applications"
pass "Created Applications symlink"

# Generate background image (if script exists)
BACKGROUND_SCRIPT="$SCRIPT_DIR/create-dmg-background.sh"
BACKGROUND_FILE="$PROJECT_ROOT/resources/dmg-background.png"

if [[ -f "$BACKGROUND_SCRIPT" ]] && [[ ! -f "$BACKGROUND_FILE" ]]; then
    echo ""
    echo "=== Generating DMG Background ==="
    bash "$BACKGROUND_SCRIPT" --generate-only || warn "Background generation skipped"
fi

if [[ -f "$BACKGROUND_FILE" ]]; then
    pass "Background image ready: $BACKGROUND_FILE"
fi

# Create a writable DMG first (so we can customise Finder view)
echo ""
echo "=== Creating DMG ==="
rm -f "$DMG_PATH"

WRITABLE_DMG="$PROJECT_ROOT/SnapPoint-rw.dmg"
rm -f "$WRITABLE_DMG"

# Step 1: writable DMG for Finder customisation
hdiutil create \
    -volname "SnapPoint $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    -size 80m \
    "$WRITABLE_DMG"

pass "Writable DMG created"

# Step 2: mount and apply background + icon layout
MOUNT_DIR="$PROJECT_ROOT/dmg-mount"
rm -rf "$MOUNT_DIR"
mkdir -p "$MOUNT_DIR"

DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen \
    -mountpoint "$MOUNT_DIR" "$WRITABLE_DMG" 2>&1 | \
    grep "^/dev" | awk '{print $1}' | head -1)

if [[ -n "$DEVICE" ]]; then
    pass "DMG mounted at $MOUNT_DIR (device: $DEVICE)"

    # Apply background image and Finder window layout
    if [[ -f "$BACKGROUND_SCRIPT" ]]; then
        bash "$BACKGROUND_SCRIPT" "$MOUNT_DIR" "SnapPoint" || \
            warn "DMG background customisation failed — DMG will work without it"
    fi

    # Ensure DS_Store is written
    sync
    sleep 1

    # Unmount
    hdiutil detach "$DEVICE" -quiet || hdiutil detach "$DEVICE" -force
    pass "DMG unmounted"
    rm -rf "$MOUNT_DIR"
else
    warn "Could not mount writable DMG — skipping Finder customisation"
fi

# Step 3: convert to compressed, read-only DMG
hdiutil convert "$WRITABLE_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH"

rm -f "$WRITABLE_DMG"

if [[ -f "$DMG_PATH" ]]; then
    pass "DMG created: $DMG_NAME"
else
    fail "Failed to create DMG"
fi

# Sign the DMG if APPLE_TEAM_ID is set
if [[ -n "${APPLE_TEAM_ID:-}" ]]; then
    echo ""
    echo "=== Signing DMG ==="
    codesign --sign "Developer ID Application: $APPLE_TEAM_ID" "$DMG_PATH"
    if [[ $? -eq 0 ]]; then
        pass "DMG signed"
    else
        warn "Failed to sign DMG"
    fi
fi

# Cleanup
rm -rf "$STAGING_DIR"
rm -rf "$PROJECT_ROOT/dmg-mount"
pass "Cleaned up staging directory"

# Generate checksum
echo ""
echo "=== Generating Checksum ==="
shasum -a 256 "$DMG_PATH" | tee "$PROJECT_ROOT/SHA256SUMS.txt"
pass "SHA256 checksum saved to SHA256SUMS.txt"

# Show DMG info
echo ""
echo "=== DMG Info ==="
DMG_SIZE=$(stat -f%z "$DMG_PATH" 2>/dev/null || stat --printf="%s" "$DMG_PATH")
DMG_SIZE_MB=$((DMG_SIZE / 1024 / 1024))
echo "  File: $DMG_NAME"
echo "  Size: ${DMG_SIZE_MB} MB"

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "DMG creation complete!"
echo ""
echo "Distribution files:"
echo "  - $DMG_PATH"
echo "  - $PROJECT_ROOT/SHA256SUMS.txt"
echo ""
