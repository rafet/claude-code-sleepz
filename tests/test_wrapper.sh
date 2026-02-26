#!/usr/bin/env bash
# Unit tests for smart-sleep.sh wrapper script

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WRAPPER="$SCRIPT_DIR/../plugins/smart-sleep/scripts/smart-sleep.sh"
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

echo "=== smart-sleep.sh wrapper tests ==="
echo ""

# Test 1: Elapsed time exceeds duration -> skip entirely
echo "Test: elapsed > duration skips sleep"
HOOK_TS=$(python3 -c "import time; print(format(int((time.time() - 120) % 86400), 'x'))")
OUTPUT=$(bash "$WRAPPER" 60 "$HOOK_TS" 2>&1)
assert_contains "skip message" "0s (skipped entirely)" "$OUTPUT"

# Test 2: Elapsed time less than duration -> adjusted sleep (use tiny duration)
echo "Test: elapsed < duration adjusts sleep"
HOOK_TS=$(python3 -c "import time; print(format(int((time.time() - 0.5) % 86400), 'x'))")
OUTPUT=$(bash "$WRAPPER" 2 "$HOOK_TS" 2>&1)
assert_contains "adjusted message" "adjusted 2s ->" "$OUTPUT"

# Test 3: Missing arguments -> graceful fallback
echo "Test: missing arguments"
OUTPUT=$(bash "$WRAPPER" 0 "" 2>&1 || true)
assert_contains "missing args message" "missing arguments" "$OUTPUT"

# Test 4: Very recent timestamp -> nearly full sleep (use tiny duration)
echo "Test: very recent timestamp"
HOOK_TS=$(python3 -c "import time; print(format(int(time.time() % 86400), 'x'))")
OUTPUT=$(bash "$WRAPPER" 0.5 "$HOOK_TS" 2>&1)
assert_contains "adjusted message" "adjusted 0.5s ->" "$OUTPUT"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
