#!/bin/bash
# profile.sh
# Performance profiling for SnapPoint using macOS Instruments.
#
# Profiles the running SnapPoint process and captures:
#   - CPU usage over a sampling window
#   - Memory allocations (Allocations instrument)
#   - System call latency via dtrace (when SIP allows)
#
# Usage:
#   ./scripts/profile.sh [--time <seconds>] [--instrument <name>]
#
# Examples:
#   ./scripts/profile.sh                          # default: Time Profiler, 30s
#   ./scripts/profile.sh --time 60                # 60-second sample
#   ./scripts/profile.sh --instrument Allocations # memory profiling

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROFILE_DIR="$PROJECT_ROOT/profiles"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
SAMPLE_TIME="${SAMPLE_TIME:-30}"
INSTRUMENT="${INSTRUMENT:-Time Profiler}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --time)    SAMPLE_TIME="$2"; shift 2 ;;
        --instrument) INSTRUMENT="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

pass()  { echo -e "${GREEN}✓${NC} $1"; }
fail()  { echo -e "${RED}✗${NC} $1"; exit 1; }
warn()  { echo -e "${YELLOW}!${NC} $1"; }
info()  { echo -e "  $1"; }
step()  { echo -e "\n${BLUE}${BOLD}── $1 ──${NC}"; }

mkdir -p "$PROFILE_DIR"
TRACE_FILE="$PROFILE_DIR/SnapPoint-${TIMESTAMP}.trace"
REPORT_FILE="$PROFILE_DIR/SnapPoint-${TIMESTAMP}-report.txt"

echo ""
echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║            SnapPoint Performance Profiler                  ║${NC}"
echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
info "Instrument:  $INSTRUMENT"
info "Sample time: ${SAMPLE_TIME}s"
info "Trace file:  $TRACE_FILE"
echo ""

# ── Check Instruments ────────────────────────────────────────────────────────
step "Preflight"

if ! command -v instruments &>/dev/null; then
    warn "instruments not found. Install Xcode from the App Store."
    echo ""
    echo "Falling back to sample(1) for basic CPU profiling..."
    FALLBACK=true
else
    FALLBACK=false
    pass "instruments found"
fi

# ── Find SnapPoint process ────────────────────────────────────────────────────
step "Locate Process"

PID=$(pgrep -x SnapPoint 2>/dev/null || echo "")

if [[ -z "$PID" ]]; then
    info "SnapPoint not running — launching bundle..."

    BUNDLE="$PROJECT_ROOT/zig-out/SnapPoint.app"
    if [[ ! -d "$BUNDLE" ]]; then
        info "Bundle not found, building first..."
        cd "$PROJECT_ROOT"
        zig build bundle
    fi

    open "$BUNDLE"
    info "Waiting for SnapPoint to start..."
    sleep 2

    PID=$(pgrep -x SnapPoint 2>/dev/null || echo "")
    if [[ -z "$PID" ]]; then
        fail "Could not find SnapPoint process after launch"
    fi
fi

pass "Found SnapPoint (PID: $PID)"

# ── Baseline memory snapshot ─────────────────────────────────────────────────
step "Baseline Memory"

VMSIZE=$(ps -o vsz= -p "$PID" 2>/dev/null | tr -d ' ' || echo "unknown")
RSIZE=$(ps -o rss= -p "$PID" 2>/dev/null | tr -d ' ' || echo "unknown")

info "Virtual memory:  ${VMSIZE} KB"
info "Resident memory: ${RSIZE} KB"

if [[ "$RSIZE" != "unknown" ]]; then
    RSIZE_MB=$((RSIZE / 1024))
    if [[ $RSIZE_MB -lt 20 ]]; then
        pass "Resident memory ${RSIZE_MB} MB — within target (< 20 MB)"
    elif [[ $RSIZE_MB -lt 50 ]]; then
        warn "Resident memory ${RSIZE_MB} MB — acceptable but above target (< 20 MB)"
    else
        warn "Resident memory ${RSIZE_MB} MB — exceeds 50 MB budget"
    fi
fi

# Log to report
{
    echo "SnapPoint Performance Report"
    echo "============================"
    echo "Date:        $(date)"
    echo "PID:         $PID"
    echo "Instrument:  $INSTRUMENT"
    echo "Sample time: ${SAMPLE_TIME}s"
    echo ""
    echo "=== Baseline Memory ==="
    echo "Virtual:  ${VMSIZE} KB"
    echo "Resident: ${RSIZE} KB"
    echo ""
} > "$REPORT_FILE"

# ── CPU sampling ─────────────────────────────────────────────────────────────
step "CPU Sampling (${SAMPLE_TIME}s)"
info "Triggering snap actions now will show hotspot activity in the profile..."
echo ""

if [[ "$FALLBACK" == "true" ]]; then
    # Use sample(1) as fallback
    SAMPLE_FILE="$PROFILE_DIR/SnapPoint-${TIMESTAMP}-sample.txt"
    info "Running sample(1) for ${SAMPLE_TIME}s..."
    sample "$PID" "$SAMPLE_TIME" -f "$SAMPLE_FILE" || true

    if [[ -f "$SAMPLE_FILE" ]]; then
        pass "CPU sample saved to: $SAMPLE_FILE"
        # Append top 20 stacks to report
        echo "=== CPU Sample (sample(1)) ===" >> "$REPORT_FILE"
        head -60 "$SAMPLE_FILE" >> "$REPORT_FILE" 2>/dev/null || true
    fi
else
    # Use Instruments
    info "Recording Instruments trace for ${SAMPLE_TIME}s..."
    info "(Xcode Instruments will open when done)"

    instruments \
        -t "$INSTRUMENT" \
        -p "$PID" \
        -D "$TRACE_FILE" \
        -l "${SAMPLE_TIME}000" \
        2>&1 | tail -5 || warn "Instruments reported non-zero exit (trace may still be valid)"

    if [[ -d "$TRACE_FILE" ]]; then
        pass "Instruments trace saved to: $TRACE_FILE"
        info "Open with: open \"$TRACE_FILE\""
    else
        warn "Trace file not found. Instruments may require screen recording permission."
    fi
fi

# ── Post-sample memory ───────────────────────────────────────────────────────
step "Post-Sample Memory"

RSIZE_AFTER=$(ps -o rss= -p "$PID" 2>/dev/null | tr -d ' ' || echo "unknown")
info "Resident memory after sampling: ${RSIZE_AFTER} KB"

if [[ "$RSIZE" != "unknown" && "$RSIZE_AFTER" != "unknown" ]]; then
    DELTA=$((RSIZE_AFTER - RSIZE))
    info "Memory delta: +${DELTA} KB over ${SAMPLE_TIME}s"
    if [[ $DELTA -lt 1024 ]]; then
        pass "Memory growth under 1 MB — no obvious leak"
    else
        warn "Memory grew by $((DELTA / 1024)) MB — investigate with Allocations instrument"
    fi
fi

{
    echo "=== Post-Sample Memory ==="
    echo "Resident: ${RSIZE_AFTER} KB"
    echo "Delta:    +$((${RSIZE_AFTER:-0} - ${RSIZE:-0})) KB over ${SAMPLE_TIME}s"
    echo ""
} >> "$REPORT_FILE"

# ── Leaks check ──────────────────────────────────────────────────────────────
step "Leaks Check"

if command -v leaks &>/dev/null; then
    info "Running leaks(1) against PID $PID..."
    LEAKS_OUTPUT=$(leaks "$PID" 2>&1 || true)
    LEAK_COUNT=$(echo "$LEAKS_OUTPUT" | grep -c "leak" || echo "0")

    if echo "$LEAKS_OUTPUT" | grep -q "0 leaks"; then
        pass "leaks(1): 0 leaks found"
    else
        warn "leaks(1) found potential leaks (expected for ObjC runtime objects)"
        echo "$LEAKS_OUTPUT" | grep "leak" | head -5 | sed 's/^/  /'
    fi

    echo "=== Leaks Check ===" >> "$REPORT_FILE"
    echo "$LEAKS_OUTPUT" | head -20 >> "$REPORT_FILE" || true
    echo "" >> "$REPORT_FILE"
else
    warn "leaks(1) not found — skipping"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo "Profiling complete."
echo ""
echo "  Report:     $REPORT_FILE"
[[ "$FALLBACK" == "false" && -d "$TRACE_FILE" ]] && \
    echo "  Trace:      $TRACE_FILE  (open with Xcode Instruments)"
echo ""
echo "Performance budgets:"
echo "  Binary size:    < 100 KB"
echo "  Resident RAM:   < 20 MB"
echo "  Snap latency:   < 16 ms"
echo "  CPU (idle):     < 0.1%"
echo ""

cat "$REPORT_FILE"
