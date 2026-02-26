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
TS_FILE=$(mktemp /tmp/smart-sleep-test-XXXXXX.txt)
python3 -c "import time; print(time.time() - 120)" > "$TS_FILE"
OUTPUT=$(bash "$WRAPPER" 60 "$TS_FILE" 2>&1)
assert_contains "skip message" "0s (skipped entirely)" "$OUTPUT"

# Test 2: Elapsed time less than duration -> adjusted sleep (use tiny duration)
echo "Test: elapsed < duration adjusts sleep"
TS_FILE=$(mktemp /tmp/smart-sleep-test-XXXXXX.txt)
python3 -c "import time; print(time.time() - 0.5)" > "$TS_FILE"
OUTPUT=$(bash "$WRAPPER" 1 "$TS_FILE" 2>&1)
assert_contains "adjusted message" "adjusted 1s ->" "$OUTPUT"

# Test 3: Missing timestamp file -> full sleep fallback (use 0 duration)
echo "Test: missing timestamp file falls back to full sleep"
OUTPUT=$(bash "$WRAPPER" 0 "/tmp/nonexistent-ts-file-xxx.txt" 2>&1)
assert_contains "fallback message" "timestamp file not found" "$OUTPUT"

# Test 4: Timestamp file is cleaned up after run
echo "Test: timestamp file cleanup"
TS_FILE=$(mktemp /tmp/smart-sleep-test-XXXXXX.txt)
python3 -c "import time; print(time.time() - 999)" > "$TS_FILE"
bash "$WRAPPER" 1 "$TS_FILE" 2>/dev/null
if [[ ! -f "$TS_FILE" ]]; then
    echo "  PASS: timestamp file cleaned up"
    ((PASS++))
else
    echo "  FAIL: timestamp file still exists"
    rm -f "$TS_FILE"
    ((FAIL++))
fi

# Test 5: Missing arguments -> graceful fallback
echo "Test: missing arguments"
OUTPUT=$(bash "$WRAPPER" 0 "" 2>&1 || true)
assert_contains "missing args message" "missing arguments" "$OUTPUT"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
