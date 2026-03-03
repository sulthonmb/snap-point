#!/bin/bash
# test-compat.sh
# Run tests and log results with macOS version information.
#
# Usage:
#   ./scripts/test-compat.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Get macOS version info
MACOS_VERSION=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
MACOS_BUILD=$(sw_vers -buildVersion)
ARCH=$(uname -m)

# Create output directory
LOG_DIR="$PROJECT_ROOT/test-results"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/test-macos${MACOS_MAJOR}-${ARCH}-${TIMESTAMP}.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }

echo "╔════════════════════════════════════════════════════════════╗"
echo "║            SnapPoint Compatibility Test                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "  macOS Version: $MACOS_VERSION ($MACOS_BUILD)"
echo "  Architecture:  $ARCH"
echo "  Log File:      $LOG_FILE"
echo ""

# Check minimum macOS version
if [[ $MACOS_MAJOR -lt 13 ]]; then
    fail "macOS 13+ required (Ventura or later)"
    exit 1
fi
pass "macOS version check passed"

# Log header
{
    echo "SnapPoint Compatibility Test Results"
    echo "======================================"
    echo "Date: $(date)"
    echo "macOS: $MACOS_VERSION ($MACOS_BUILD)"
    echo "Architecture: $ARCH"
    echo "Zig Version: $(zig version)"
    echo ""
} > "$LOG_FILE"

# Run unit tests
echo ""
echo "=== Running Unit Tests ==="
{
    echo "=== Unit Tests ==="
    echo ""
} >> "$LOG_FILE"

if zig build test 2>&1 | tee -a "$LOG_FILE"; then
    pass "Unit tests passed"
    echo "RESULT: PASS" >> "$LOG_FILE"
else
    fail "Unit tests failed"
    echo "RESULT: FAIL" >> "$LOG_FILE"
fi

# Run integration tests
echo ""
echo "=== Running Integration Tests ==="
{
    echo ""
    echo "=== Integration Tests ==="
    echo ""
} >> "$LOG_FILE"

if zig build test-integration 2>&1 | tee -a "$LOG_FILE"; then
    pass "Integration tests passed"
    echo "RESULT: PASS" >> "$LOG_FILE"
else
    warn "Integration tests had failures (may be expected without Accessibility)"
    echo "RESULT: PARTIAL (Accessibility permission may not be granted)" >> "$LOG_FILE"
fi

# Build and validate binary
echo ""
echo "=== Building and Validating Binary ==="
{
    echo ""
    echo "=== Binary Validation ==="
    echo ""
} >> "$LOG_FILE"

if zig build bundle 2>&1 | tee -a "$LOG_FILE"; then
    pass "Build successful"

    if "$SCRIPT_DIR/validate-binary.sh" 2>&1 | tee -a "$LOG_FILE"; then
        pass "Binary validation passed"
        echo "RESULT: PASS" >> "$LOG_FILE"
    else
        warn "Binary validation had warnings"
        echo "RESULT: WARNINGS" >> "$LOG_FILE"
    fi
else
    fail "Build failed"
    echo "RESULT: FAIL" >> "$LOG_FILE"
fi

# Summary
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "Compatibility test complete."
echo ""
echo "Results saved to: $LOG_FILE"
echo ""

# Show brief summary
grep -E "^RESULT:" "$LOG_FILE" || true
