#!/bin/bash
# validate-binary.sh
# Validates the SnapPoint binary and app bundle for distribution readiness.
#
# Checks performed:
#   1. Architecture (Universal Binary: ARM64 + x86_64)
#   2. Code signature validity
#   3. Entitlements
#   4. Info.plist validity
#   5. Minimum macOS version
#   6. Binary size
#
# Usage:
#   ./scripts/validate-binary.sh [--release]
#
# With --release flag, performs stricter checks for distribution.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUNDLE="$PROJECT_ROOT/zig-out/SnapPoint.app"
BINARY="$BUNDLE/Contents/MacOS/SnapPoint"
RELEASE_MODE=false

# Parse arguments
if [[ "$1" == "--release" ]]; then
    RELEASE_MODE=true
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}✓${NC} $1"
}

fail() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}!${NC} $1"
}

echo "╔════════════════════════════════════════════════════════════╗"
echo "║            SnapPoint Binary Validation                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check bundle exists
if [[ ! -d "$BUNDLE" ]]; then
    fail "App bundle not found at $BUNDLE"
    echo "  Run 'zig build bundle' first."
    exit 1
fi

if [[ ! -f "$BINARY" ]]; then
    fail "Binary not found at $BINARY"
    exit 1
fi

pass "App bundle found"

# ── 1. Architecture Check ──────────────────────────────────────────────────

echo ""
echo "=== Architecture Check ==="

ARCH_INFO=$(lipo -info "$BINARY" 2>&1)
echo "  $ARCH_INFO"

if [[ "$ARCH_INFO" == *"arm64"* ]]; then
    pass "ARM64 architecture present"
else
    if $RELEASE_MODE; then
        fail "ARM64 architecture missing (required for Apple Silicon)"
    else
        warn "ARM64 architecture missing (OK for dev builds)"
    fi
fi

if [[ "$ARCH_INFO" == *"x86_64"* ]]; then
    pass "x86_64 architecture present"
else
    if $RELEASE_MODE; then
        fail "x86_64 architecture missing (required for Intel Macs)"
    else
        warn "x86_64 architecture missing (OK for dev builds)"
    fi
fi

# ── 2. Binary Size ─────────────────────────────────────────────────────────

echo ""
echo "=== Binary Size ==="

BINARY_SIZE=$(stat -f%z "$BINARY" 2>/dev/null || stat --printf="%s" "$BINARY")
BINARY_SIZE_KB=$((BINARY_SIZE / 1024))

echo "  Size: ${BINARY_SIZE_KB} KB"

if [[ $BINARY_SIZE_KB -lt 100 ]]; then
    pass "Binary size under 100 KB target"
elif [[ $BINARY_SIZE_KB -lt 500 ]]; then
    warn "Binary size ${BINARY_SIZE_KB} KB (target: < 100 KB)"
else
    warn "Binary size ${BINARY_SIZE_KB} KB - consider stripping (-Doptimize=ReleaseSmall)"
fi

# ── 3. Info.plist Validation ───────────────────────────────────────────────

echo ""
echo "=== Info.plist Validation ==="

PLIST="$BUNDLE/Contents/Info.plist"
if [[ ! -f "$PLIST" ]]; then
    fail "Info.plist not found"
fi

if plutil -lint "$PLIST" > /dev/null 2>&1; then
    pass "Info.plist is valid"
else
    fail "Info.plist syntax error"
fi

# Check required keys
BUNDLE_ID=$(defaults read "$PLIST" CFBundleIdentifier 2>/dev/null || echo "")
if [[ -n "$BUNDLE_ID" ]]; then
    pass "CFBundleIdentifier: $BUNDLE_ID"
else
    fail "CFBundleIdentifier missing"
fi

MIN_OS=$(defaults read "$PLIST" LSMinimumSystemVersion 2>/dev/null || echo "")
if [[ -n "$MIN_OS" ]]; then
    pass "LSMinimumSystemVersion: $MIN_OS"
else
    warn "LSMinimumSystemVersion not set"
fi

LSUIELEMENT=$(defaults read "$PLIST" LSUIElement 2>/dev/null || echo "")
if [[ "$LSUIELEMENT" == "1" ]]; then
    pass "LSUIElement: true (agent app, no Dock icon)"
else
    warn "LSUIElement not set to true"
fi

# ── 4. Code Signature ──────────────────────────────────────────────────────

echo ""
echo "=== Code Signature ==="

CODESIGN_OUTPUT=$(codesign -dv --verbose=2 "$BUNDLE" 2>&1 || true)

if [[ "$CODESIGN_OUTPUT" == *"valid on disk"* ]]; then
    pass "Code signature is valid"
elif [[ "$CODESIGN_OUTPUT" == *"not signed"* ]] || [[ "$CODESIGN_OUTPUT" == *"code signature"*"invalid"* ]]; then
    if $RELEASE_MODE; then
        fail "Bundle is not properly signed (required for distribution)"
    else
        warn "Bundle is not signed (OK for development)"
    fi
else
    warn "Code signature status unclear"
    echo "  $CODESIGN_OUTPUT" | head -5
fi

# ── 5. Entitlements Check ──────────────────────────────────────────────────

echo ""
echo "=== Entitlements ==="

ENTITLEMENTS=$(codesign -d --entitlements :- "$BUNDLE" 2>&1 || true)

if [[ "$ENTITLEMENTS" == *"com.apple.security.app-sandbox"*"<false/>"* ]] || \
   [[ "$ENTITLEMENTS" == *"com.apple.security.app-sandbox"*"false"* ]]; then
    pass "Sandbox disabled (required for window management)"
elif [[ "$ENTITLEMENTS" == *"not signed"* ]]; then
    warn "Cannot check entitlements - bundle not signed"
else
    # No sandbox key or unclear - check raw output
    if [[ "$ENTITLEMENTS" == *"com.apple.security.app-sandbox"*"<true/>"* ]]; then
        fail "App sandbox is ENABLED - will break window management!"
    fi
fi

# Check for dangerous entitlements
DANGEROUS_ENTITLEMENTS=(
    "com.apple.security.cs.disable-library-validation"
    "com.apple.security.cs.allow-dyld-environment-variables"
    "com.apple.security.cs.debugger"
)

for ent in "${DANGEROUS_ENTITLEMENTS[@]}"; do
    if [[ "$ENTITLEMENTS" == *"$ent"*"true"* ]]; then
        warn "Dangerous entitlement enabled: $ent"
    fi
done

# ── 6. Minimum OS Version from Binary ──────────────────────────────────────

echo ""
echo "=== LC_BUILD_VERSION ==="

BUILD_VERSION=$(otool -l "$BINARY" 2>/dev/null | grep -A4 "LC_BUILD_VERSION" || true)
if [[ -n "$BUILD_VERSION" ]]; then
    echo "$BUILD_VERSION" | head -6 | sed 's/^/  /'
    if echo "$BUILD_VERSION" | grep -q "minos"; then
        pass "LC_BUILD_VERSION present"
    fi
else
    warn "LC_BUILD_VERSION not found"
fi

# ── 7. Dynamic Library Dependencies ────────────────────────────────────────

echo ""
echo "=== Dynamic Dependencies ==="

DYLIBS=$(otool -L "$BINARY" 2>/dev/null | tail -n +2 | head -10)
DYLIB_COUNT=$(echo "$DYLIBS" | wc -l | tr -d ' ')

echo "  Linked libraries: $DYLIB_COUNT"

# Check for unexpected dependencies
if echo "$DYLIBS" | grep -q "/usr/local\|/opt/homebrew"; then
    warn "Non-system library dependencies found:"
    echo "$DYLIBS" | grep "/usr/local\|/opt/homebrew" | sed 's/^/    /'
else
    pass "All dependencies are system libraries"
fi

# ── Summary ────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════════"

if $RELEASE_MODE; then
    echo "Release validation complete."
    echo ""
    echo "Next steps for distribution:"
    echo "  1. Sign with: codesign --deep --force --sign \"Developer ID Application: <TEAM>\" \\"
    echo "                --options runtime --entitlements resources/Entitlements.plist $BUNDLE"
    echo "  2. Notarize with: xcrun notarytool submit ..."
    echo "  3. Staple with: xcrun stapler staple $BUNDLE"
else
    echo "Development validation complete."
    echo ""
    echo "For release validation, run:"
    echo "  ./scripts/validate-binary.sh --release"
fi

echo ""
