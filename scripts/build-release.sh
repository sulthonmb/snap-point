#!/bin/bash
# build-release.sh
# Full SnapPoint release pipeline: build → bundle → sign → notarize → DMG.
#
# Required environment variables:
#   APPLE_TEAM_ID        - Apple Developer Team ID (for code signing)
#   APPLE_ID             - Apple ID email (for notarization)
#   APPLE_APP_PASSWORD   - App-specific password (for notarization)
#
# Optional environment variables:
#   VERSION              - Release version (default: read from build.zig.zon)
#   SKIP_NOTARIZE        - Set to "1" to skip notarization (dev testing)
#   SKIP_SIGN            - Set to "1" to skip signing (local testing only)
#
# Usage:
#   ./scripts/build-release.sh [version]
#
# Examples:
#   ./scripts/build-release.sh
#   ./scripts/build-release.sh 1.0.0
#   SKIP_NOTARIZE=1 ./scripts/build-release.sh 1.0.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# ── Version resolution ──────────────────────────────────────────────────────
if [[ -n "${1:-}" ]]; then
    VERSION="$1"
elif [[ -n "${VERSION:-}" ]]; then
    VERSION="$VERSION"
else
    # Try to extract version from build.zig.zon
    if [[ -f "build.zig.zon" ]]; then
        VERSION=$(grep -E '^\s+\.version\s*=' build.zig.zon | \
            sed 's/.*"\(.*\)".*/\1/' | head -1)
    fi
    VERSION="${VERSION:-1.0.0}"
fi

# ── Paths ───────────────────────────────────────────────────────────────────
BUNDLE="$PROJECT_ROOT/zig-out/SnapPoint.app"
DIST_DIR="$PROJECT_ROOT/dist"
DMG_NAME="SnapPoint-${VERSION}.dmg"

# ── Color helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

pass()  { echo -e "${GREEN}✓${NC} $1"; }
fail()  { echo -e "${RED}✗${NC} $1"; exit 1; }
warn()  { echo -e "${YELLOW}!${NC} $1"; }
step()  { echo -e "\n${BLUE}${BOLD}══ $1 ══${NC}"; }
info()  { echo -e "  $1"; }

echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║               SnapPoint Release Builder                    ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
info "Version:  $VERSION"
info "Root:     $PROJECT_ROOT"
info "Bundle:   $BUNDLE"
info "Output:   $DIST_DIR/$DMG_NAME"
echo ""

# ── Preflight checks ────────────────────────────────────────────────────────
step "Preflight"

# Zig
if ! command -v zig &>/dev/null; then
    fail "zig not found. Install via: brew install zig"
fi
ZIG_VERSION=$(zig version)
pass "zig $ZIG_VERSION"

# Xcode CLT (for codesign, xcrun, hdiutil)
if ! command -v codesign &>/dev/null; then
    fail "codesign not found. Install Xcode Command Line Tools: xcode-select --install"
fi
pass "Xcode Command Line Tools"

# macOS version
MACOS_VERSION=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
if [[ $MACOS_MAJOR -lt 13 ]]; then
    fail "macOS 13+ required for notarization tools (xcrun notarytool)"
fi
pass "macOS $MACOS_VERSION"

# Signing environment
SKIP_SIGN="${SKIP_SIGN:-0}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

if [[ "$SKIP_SIGN" == "1" ]]; then
    warn "Code signing SKIPPED (SKIP_SIGN=1)"
else
    if [[ -z "${APPLE_TEAM_ID:-}" ]]; then
        fail "APPLE_TEAM_ID is required for signing. Set it or use SKIP_SIGN=1"
    fi
    pass "APPLE_TEAM_ID set"
fi

if [[ "$SKIP_NOTARIZE" == "1" ]]; then
    warn "Notarization SKIPPED (SKIP_NOTARIZE=1)"
else
    if [[ -z "${APPLE_ID:-}" ]]; then
        fail "APPLE_ID is required for notarization. Set it or use SKIP_NOTARIZE=1"
    fi
    if [[ -z "${APPLE_APP_PASSWORD:-}" ]]; then
        fail "APPLE_APP_PASSWORD is required. Create one at https://appleid.apple.com"
    fi
    pass "Notarization credentials set"
fi

# ── Step 1: Run tests ────────────────────────────────────────────────────────
step "1 / 7  Run Tests"

if zig build test 2>&1; then
    pass "All unit tests passed"
else
    fail "Unit tests failed — aborting release"
fi

# ── Step 2: Build universal binary ──────────────────────────────────────────
step "2 / 7  Build Universal Binary"

info "Building ARM64…"
zig build -Doptimize=ReleaseSmall -Dtarget=aarch64-macos
cp zig-out/bin/SnapPoint zig-out/bin/SnapPoint-aarch64
pass "ARM64 build complete"

info "Building x86_64…"
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-macos
cp zig-out/bin/SnapPoint zig-out/bin/SnapPoint-x86_64
pass "x86_64 build complete"

info "Merging into universal binary…"
lipo -create \
    zig-out/bin/SnapPoint-aarch64 \
    zig-out/bin/SnapPoint-x86_64 \
    -output zig-out/bin/SnapPoint
pass "Universal binary created"

BINARY_SIZE=$(stat -f%z zig-out/bin/SnapPoint 2>/dev/null || stat --printf="%s" zig-out/bin/SnapPoint)
BINARY_SIZE_KB=$((BINARY_SIZE / 1024))
info "Binary size: ${BINARY_SIZE_KB} KB"
if [[ $BINARY_SIZE_KB -gt 100 ]]; then
    warn "Binary exceeds 100 KB target (${BINARY_SIZE_KB} KB)"
fi

# ── Step 3: Assemble app bundle ──────────────────────────────────────────────
step "3 / 7  Assemble App Bundle"

zig build bundle
pass "App bundle assembled at $BUNDLE"

# ── Step 4: Code sign ────────────────────────────────────────────────────────
step "4 / 7  Code Sign"

if [[ "$SKIP_SIGN" == "1" ]]; then
    warn "Skipping code signing (SKIP_SIGN=1)"
else
    "$SCRIPT_DIR/sign-release.sh"
    pass "Code signing complete"
fi

# ── Step 5: Validate bundle ──────────────────────────────────────────────────
step "5 / 7  Validate Bundle"

"$SCRIPT_DIR/validate-binary.sh" ${SKIP_SIGN:+} \
    $([ "$SKIP_SIGN" == "1" ] && echo "" || echo "--release")
pass "Bundle validation passed"

# ── Step 6: Notarize ─────────────────────────────────────────────────────────
step "6 / 7  Notarize"

if [[ "$SKIP_NOTARIZE" == "1" ]] || [[ "$SKIP_SIGN" == "1" ]]; then
    warn "Skipping notarization"
else
    "$SCRIPT_DIR/notarize.sh"
    pass "Notarization and stapling complete"
fi

# ── Step 7: Create DMG ───────────────────────────────────────────────────────
step "7 / 7  Create DMG"

mkdir -p "$DIST_DIR"
"$SCRIPT_DIR/create-dmg.sh" "$VERSION"

# Move DMG to dist/
if [[ -f "$PROJECT_ROOT/$DMG_NAME" ]]; then
    mv "$PROJECT_ROOT/$DMG_NAME" "$DIST_DIR/$DMG_NAME"
    # Move checksum too
    [[ -f "$PROJECT_ROOT/SHA256SUMS.txt" ]] && \
        mv "$PROJECT_ROOT/SHA256SUMS.txt" "$DIST_DIR/SHA256SUMS-${VERSION}.txt"
fi
pass "DMG created: dist/$DMG_NAME"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}Release build complete!${NC}"
echo ""
echo "  Version:  $VERSION"
echo "  DMG:      dist/$DMG_NAME"
[[ -f "$DIST_DIR/SHA256SUMS-${VERSION}.txt" ]] && \
    echo "  SHA256:   dist/SHA256SUMS-${VERSION}.txt"
echo ""

if [[ "$SKIP_NOTARIZE" == "1" ]] || [[ "$SKIP_SIGN" == "1" ]]; then
    warn "This build was NOT notarized — not suitable for distribution."
    echo ""
    echo "  For a distribution-ready build, set:"
    echo "    APPLE_TEAM_ID, APPLE_ID, APPLE_APP_PASSWORD"
    echo "  then run ./scripts/build-release.sh again."
else
    info "The DMG is signed, notarized, and ready for distribution."
    echo ""
    echo "  GitHub release checklist:"
    echo "    1. git tag v$VERSION && git push origin v$VERSION"
    echo "    2. Upload dist/$DMG_NAME to GitHub Releases"
    echo "    3. Paste SHA256 from dist/SHA256SUMS-${VERSION}.txt into the release notes"
fi
echo ""

# ── Cleanup temp lipo files ──────────────────────────────────────────────────
rm -f zig-out/bin/SnapPoint-aarch64 zig-out/bin/SnapPoint-x86_64
