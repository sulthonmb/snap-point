#!/usr/bin/env bash
# scripts/run-dev.sh
# Build SnapPoint, assemble the .app bundle, and launch it.
#
# The app MUST run from the bundle for macOS to register it in
# System Settings > Privacy & Security > Accessibility.
#
# Usage:
#   ./scripts/run-dev.sh          # build + launch
#   ./scripts/run-dev.sh --logs   # build + launch + stream system logs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
BUNDLE="$ROOT/zig-out/SnapPoint.app"

# ── 1. Build ────────────────────────────────────────────────────────────────
echo "▶ Building…"
cd "$ROOT"
zig build bundle

# ── 2. Kill any running instance ────────────────────────────────────────────
if pgrep -qxf "$BUNDLE/Contents/MacOS/SnapPoint" 2>/dev/null; then
    echo "▶ Stopping existing instance…"
    pkill -f "$BUNDLE/Contents/MacOS/SnapPoint" || true
    sleep 0.5
fi

# ── 3. Launch from bundle ────────────────────────────────────────────────────
echo "▶ Launching $BUNDLE"
open "$BUNDLE"

echo ""
echo "✓ SnapPoint is running from the .app bundle."
echo "  If this is the first run, you'll see the onboarding window."
echo ""
echo "  To grant Accessibility permission:"
echo "    System Settings → Privacy & Security → Accessibility → toggle SnapPoint ON"
echo "  Then relaunch: ./scripts/run-dev.sh"
echo ""

# ── 4. Optional: stream logs ─────────────────────────────────────────────────
if [[ "${1:-}" == "--logs" ]]; then
    echo "▶ Streaming logs (Ctrl-C to stop)…"
    log stream --process SnapPoint --level debug 2>/dev/null | \
        grep --line-buffered "SnapPoint" || true
fi
