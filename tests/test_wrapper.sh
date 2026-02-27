#!/usr/bin/env bash
# Unit tests for sleepz.sh wrapper script

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WRAPPER="$SCRIPT_DIR/../plugins/sleepz/scripts/sleepz.sh"

# Shared helpers
source "$SCRIPT_DIR/test_helpers.sh"

# Constants for timestamp calculations
SECS_PER_DAY=86400
CENTISEC=100

# Isolate filesystem: temp HOME + cleanup trap
HOME_BACKUP="$HOME"
TEST_HOME=$(mktemp -d)
export HOME="$TEST_HOME"
mkdir -p "$TEST_HOME/.claude"

# Mock sleep: no-op so tests run instantly
MOCK_BIN=$(mktemp -d)
cat > "$MOCK_BIN/sleep" << 'MOCK'
#!/bin/bash
exit 0
MOCK
chmod +x "$MOCK_BIN/sleep"
PATH_BACKUP="$PATH"
export PATH="$MOCK_BIN:$PATH"

cleanup() {
    rm -rf "$TEST_HOME" "$MOCK_BIN"
    export HOME="$HOME_BACKUP"
    export PATH="$PATH_BACKUP"
}
trap cleanup EXIT

# Helper: generate hook timestamp with a given elapsed offset (in seconds)
make_hook_ts() {
    local elapsed_secs="$1"
    local now_secs
    now_secs=$(date +%s)
    printf '%x' $(( (now_secs - elapsed_secs) % SECS_PER_DAY * CENTISEC ))
}

echo "=== sleepz.sh wrapper tests ==="
echo ""

# Test 1: Elapsed time exceeds duration -> skip entirely
echo "Test: elapsed > duration skips sleep"
HOOK_TS=$(make_hook_ts 120)
OUTPUT=$(bash "$WRAPPER" 60 "$HOOK_TS" 2>&1)
assert_contains "skip message" "0s (skipped)" "$OUTPUT"

# Test 2: Elapsed time less than duration -> adjusted sleep
echo "Test: elapsed < duration adjusts sleep"
HOOK_TS=$(make_hook_ts 5)
OUTPUT=$(bash "$WRAPPER" 60 "$HOOK_TS" 2>&1)
assert_contains "adjusted message" "sleepz: 60s ->" "$OUTPUT"

# Test 3: Missing arguments -> graceful fallback
echo "Test: missing arguments"
OUTPUT=$(bash "$WRAPPER" 0 "" 2>&1 || true)
assert_contains "missing args message" "missing arguments" "$OUTPUT"

# Test 4: Very recent timestamp -> nearly full sleep
echo "Test: very recent timestamp"
HOOK_TS=$(make_hook_ts 1)
OUTPUT=$(bash "$WRAPPER" 60 "$HOOK_TS" 2>&1)
assert_contains "adjusted message" "sleepz: 60s ->" "$OUTPUT"

# ── Stats tracking tests ──

echo ""
echo "=== Stats Tracking Tests ==="
echo ""

STATS_FILE="$TEST_HOME/.claude/sleepz-stats"

# Test 5: Stats file created when time is saved (self-contained)
echo "Test: stats file created on save"
rm -f "$STATS_FILE"
HOOK_TS=$(make_hook_ts 10)
bash "$WRAPPER" 60 "$HOOK_TS" 2>/dev/null
if [[ -f "$STATS_FILE" ]]; then
    echo "  PASS: stats file created"
    ((PASS++))
else
    echo "  FAIL: stats file not created"
    ((FAIL++))
fi

# Test 6: Stats file has entries after save
echo "Test: stats file has entries"
LINE_COUNT=$(wc -l < "$STATS_FILE" 2>/dev/null | tr -d ' ')
if [[ "$LINE_COUNT" -gt 0 ]]; then
    echo "  PASS: has $LINE_COUNT entries"
    ((PASS++))
else
    echo "  FAIL: stats file is empty"
    ((FAIL++))
fi

# Test 7: --stats with data shows summary
echo "Test: --stats shows summary"
printf '10.00\n5.50\n3.00\n' > "$STATS_FILE"
OUTPUT=$(bash "$WRAPPER" --stats 2>&1)
assert_contains "command count" "3 commands" "$OUTPUT"
assert_contains "time saved" "18.5s saved" "$OUTPUT"

# Test 8: --stats with large values shows minutes
echo "Test: --stats shows minutes for large values"
printf '30.00\n30.00\n30.00\n' > "$STATS_FILE"
OUTPUT=$(bash "$WRAPPER" --stats 2>&1)
assert_contains "shows minutes" "1m 30s" "$OUTPUT"

# Test 9: --stats with no file
echo "Test: --stats with no data"
rm -f "$STATS_FILE"
OUTPUT=$(bash "$WRAPPER" --stats 2>&1)
assert_contains "no data message" "no data yet" "$OUTPUT"

# ── Results ──

report_results
