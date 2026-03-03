#!/bin/bash
# sign-release.sh
# Code sign the SnapPoint app bundle for distribution.
#
# Required environment variables:
#   APPLE_TEAM_ID - Your Apple Developer Team ID
#
# Usage:
#   ./scripts/sign-release.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUNDLE="$PROJECT_ROOT/zig-out/SnapPoint.app"
ENTITLEMENTS="$PROJECT_ROOT/resources/Entitlements.plist"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}!${NC} $1"; }

echo "╔════════════════════════════════════════════════════════════╗"
echo "║            SnapPoint Code Signing                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check required environment
if [[ -z "${APPLE_TEAM_ID:-}" ]]; then
    fail "APPLE_TEAM_ID environment variable is required"
fi

# Check bundle exists
if [[ ! -d "$BUNDLE" ]]; then
    fail "App bundle not found at $BUNDLE"
    echo "  Run 'zig build bundle' first."
fi

# Check entitlements exist
if [[ ! -f "$ENTITLEMENTS" ]]; then
    fail "Entitlements file not found at $ENTITLEMENTS"
fi

pass "Bundle found: $BUNDLE"
pass "Entitlements found: $ENTITLEMENTS"

echo ""
echo "=== Signing Bundle ==="

# Sign the bundle with Developer ID certificate
IDENTITY="Developer ID Application: $APPLE_TEAM_ID"

codesign --deep --force --verify --verbose \
    --sign "$IDENTITY" \
    --options runtime \
    --timestamp \
    --entitlements "$ENTITLEMENTS" \
    "$BUNDLE"

if [[ $? -eq 0 ]]; then
    pass "Code signing successful"
else
    fail "Code signing failed"
fi

echo ""
echo "=== Verifying Signature ==="

codesign --verify --deep --strict --verbose=2 "$BUNDLE"
if [[ $? -eq 0 ]]; then
    pass "Signature verification passed"
else
    fail "Signature verification failed"
fi

# Check Hardened Runtime
HR_CHECK=$(codesign -dv "$BUNDLE" 2>&1 | grep -c "runtime" || echo "0")
if [[ "$HR_CHECK" -gt 0 ]]; then
    pass "Hardened Runtime enabled"
else
    warn "Hardened Runtime may not be enabled"
fi

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "Code signing complete."
echo ""
echo "Next step: Notarize with ./scripts/notarize.sh"
echo ""
