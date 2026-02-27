#!/usr/bin/env bash
# Unit tests for sleepz.sh wrapper script

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WRAPPER="$SCRIPT_DIR/../plugins/sleepz/scripts/sleepz.sh"
PASS=0
FAIL=0

assert_contains() {
    local test_name="$1" expected="$2" actual="$3"
    if [[ "$actual" == *"$expected"* ]]; then
        echo "  PASS: $test_name"
        ((PASS++))
    else
        echo "  FAIL: $test_name (expected to contain '$expected', got '$actual')"
        ((FAIL++))
    fi
}

# Use temp stats file so tests don't pollute real stats
TEST_STATS=$(mktemp)
rm -f "$TEST_STATS"
export HOME_BACKUP="$HOME"

# Create a temp home so stats go to a controlled location
TEST_HOME=$(mktemp -d)
export HOME="$TEST_HOME"
mkdir -p "$TEST_HOME/.claude"

cleanup() {
    rm -rf "$TEST_HOME"
    export HOME="$HOME_BACKUP"
}
trap cleanup EXIT

echo "=== sleepz.sh wrapper tests ==="
echo ""

# Test 1: Elapsed time exceeds duration -> skip entirely
echo "Test: elapsed > duration skips sleep"
NOW_SECS=$(date +%s)
HOOK_TS=$(printf '%x' $(( (NOW_SECS - 120) % 86400 * 100 )))
OUTPUT=$(bash "$WRAPPER" 60 "$HOOK_TS" 2>&1)
assert_contains "skip message" "0s (skipped)" "$OUTPUT"

# Test 2: Elapsed time less than duration -> adjusted sleep (use tiny duration)
echo "Test: elapsed < duration adjusts sleep"
NOW_SECS=$(date +%s)
HOOK_TS=$(printf '%x' $(( (NOW_SECS - 1) % 86400 * 100 )))
OUTPUT=$(bash "$WRAPPER" 2 "$HOOK_TS" 2>&1)
assert_contains "adjusted message" "sleepz: 2s ->" "$OUTPUT"

# Test 3: Missing arguments -> graceful fallback
echo "Test: missing arguments"
OUTPUT=$(bash "$WRAPPER" 0 "" 2>&1 || true)
assert_contains "missing args message" "missing arguments" "$OUTPUT"

# Test 4: Very recent timestamp -> nearly full sleep (use tiny duration)
echo "Test: very recent timestamp"
NOW_SECS=$(date +%s)
HOOK_TS=$(printf '%x' $(( NOW_SECS % 86400 * 100 )))
OUTPUT=$(bash "$WRAPPER" 0.5 "$HOOK_TS" 2>&1)
assert_contains "adjusted message" "sleepz: 0.5s ->" "$OUTPUT"

# ── Stats tracking tests ──

echo ""
echo "=== Stats Tracking Tests ==="
echo ""

# Test 5: Stats file created after time is saved
echo "Test: stats file created on save"
STATS_FILE="$TEST_HOME/.claude/sleepz-stats"
if [[ -f "$STATS_FILE" ]]; then
    assert_contains "stats file exists" "" "ok"
else
    echo "  FAIL: stats file not created"
    ((FAIL++))
fi

# Test 6: Stats file has entries
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

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
