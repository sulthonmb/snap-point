#!/bin/bash
# notarize.sh
# Notarize the SnapPoint app bundle for Gatekeeper approval.
#
# Required environment variables:
#   APPLE_ID         - Your Apple ID email
#   APPLE_TEAM_ID    - Your Apple Developer Team ID
#   APPLE_APP_PASSWORD - App-specific password (not your Apple ID password)
#
# Usage:
#   ./scripts/notarize.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUNDLE="$PROJECT_ROOT/zig-out/SnapPoint.app"
ZIP_NAME="SnapPoint-notarize.zip"
ZIP_PATH="$PROJECT_ROOT/$ZIP_NAME"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}!${NC} $1"; }

echo "╔════════════════════════════════════════════════════════════╗"
echo "║            SnapPoint Notarization                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check required environment
if [[ -z "${APPLE_ID:-}" ]]; then
    fail "APPLE_ID environment variable is required"
fi
if [[ -z "${APPLE_TEAM_ID:-}" ]]; then
    fail "APPLE_TEAM_ID environment variable is required"
fi
if [[ -z "${APPLE_APP_PASSWORD:-}" ]]; then
    fail "APPLE_APP_PASSWORD environment variable is required"
    echo "  Create an app-specific password at: https://appleid.apple.com"
fi

# Check bundle exists
if [[ ! -d "$BUNDLE" ]]; then
    fail "App bundle not found at $BUNDLE"
fi

# Verify code signature before notarization
echo "=== Verifying Code Signature ==="
if ! codesign --verify --deep --strict "$BUNDLE" 2>/dev/null; then
    fail "Bundle is not properly signed. Run ./scripts/sign-release.sh first."
fi
pass "Code signature verified"

# Create ZIP for upload
echo ""
echo "=== Creating Archive ==="
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$BUNDLE" "$ZIP_PATH"
pass "Created $ZIP_NAME"

# Submit for notarization
echo ""
echo "=== Submitting to Apple Notary Service ==="
echo "  This may take several minutes..."

xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait

if [[ $? -eq 0 ]]; then
    pass "Notarization successful"
else
    fail "Notarization failed"
fi

# Staple the notarization ticket
echo ""
echo "=== Stapling Ticket ==="
xcrun stapler staple "$BUNDLE"
if [[ $? -eq 0 ]]; then
    pass "Notarization ticket stapled"
else
    fail "Failed to staple ticket"
fi

# Verify stapling
echo ""
echo "=== Verifying Stapled Ticket ==="
xcrun stapler validate "$BUNDLE"
if [[ $? -eq 0 ]]; then
    pass "Stapled ticket validated"
else
    warn "Stapling validation warning"
fi

# Cleanup
rm -f "$ZIP_PATH"
pass "Cleaned up temporary archive"

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "Notarization complete!"
echo ""
echo "The app is now notarized and will pass Gatekeeper."
echo ""
echo "Next step: Create DMG with ./scripts/create-dmg.sh"
echo ""
