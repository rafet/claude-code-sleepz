#!/usr/bin/env bash
# Unit tests for sleepz_hook.sh (pure bash hook)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$SCRIPT_DIR/../plugins/sleepz"
HOOK_SH="$PLUGIN_ROOT/hooks/sleepz_hook.sh"
PASS=0
FAIL=0

run_hook() {
    local command="$1"
    local payload="{\"tool_name\": \"Bash\", \"tool_input\": {\"command\": \"$command\"}}"
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK_SH" <<< "$payload" 2>/dev/null
}

assert_output_contains() {
    local test_name="$1" expected="$2" actual="$3"
    if [[ "$actual" == *"$expected"* ]]; then
        echo "  PASS: $test_name"
        ((PASS++))
    else
        echo "  FAIL: $test_name (expected to contain '$expected', got '$actual')"
        ((FAIL++))
    fi
}

assert_empty() {
    local test_name="$1" actual="$2"
    if [[ -z "$actual" ]]; then
        echo "  PASS: $test_name"
        ((PASS++))
    else
        echo "  FAIL: $test_name (expected empty, got '$actual')"
        ((FAIL++))
    fi
}

assert_not_empty() {
    local test_name="$1" actual="$2"
    if [[ -n "$actual" ]]; then
        echo "  PASS: $test_name"
        ((PASS++))
    else
        echo "  FAIL: $test_name (expected non-empty output)"
        ((FAIL++))
    fi
}

assert_matches() {
    local test_name="$1" pattern="$2" actual="$3"
    if [[ "$actual" =~ $pattern ]]; then
        echo "  PASS: $test_name"
        ((PASS++))
    else
        echo "  FAIL: $test_name (expected to match '$pattern', got '$actual')"
        ((FAIL++))
    fi
}

assert_not_contains() {
    local test_name="$1" unexpected="$2" actual="$3"
    if [[ "$actual" != *"$unexpected"* ]]; then
        echo "  PASS: $test_name"
        ((PASS++))
    else
        echo "  FAIL: $test_name (expected NOT to contain '$unexpected')"
        ((FAIL++))
    fi
}

# ── Detection tests ──

echo "=== Hook Detection Tests ==="
echo ""

echo "Test: basic sleep"
OUT=$(run_hook "sleep 60")
assert_output_contains "modifies command" "sleepz" "$OUT"

echo "Test: sleep with continuation"
OUT=$(run_hook "sleep 60 && echo done")
assert_output_contains "keeps continuation" "&& echo done" "$OUT"

echo "Test: fractional sleep"
OUT=$(run_hook "sleep 0.5")
assert_output_contains "keeps fraction" "0.5" "$OUT"

echo "Test: no sleep"
OUT=$(run_hook "echo hello")
assert_empty "no output" "$OUT"

echo "Test: sleep with variable"
OUT=$(run_hook 'sleep $VAR')
assert_empty "no output" "$OUT"

echo "Test: sleep with suffix s"
OUT=$(run_hook "sleep 60s")
assert_empty "no output" "$OUT"

echo "Test: sleep with suffix m"
OUT=$(run_hook "sleep 1m")
assert_empty "no output" "$OUT"

echo "Test: nested bash -c"
OUT=$(run_hook 'bash -c "sleep 60"')
assert_empty "no output" "$OUT"

echo "Test: empty command"
OUT=$(run_hook "")
assert_empty "no output" "$OUT"

# ── Output structure tests ──

echo ""
echo "=== Hook Output Tests ==="
echo ""

echo "Test: correct JSON structure"
OUT=$(run_hook "sleep 30")
assert_output_contains "has hookSpecificOutput" "hookSpecificOutput" "$OUT"
assert_output_contains "has hookEventName" "PreToolUse" "$OUT"
assert_output_contains "has updatedInput" "updatedInput" "$OUT"
assert_not_contains "no permissionDecision" "permissionDecision" "$OUT"

echo "Test: only first sleep replaced"
OUT=$(run_hook "sleep 10 && sleep 20")
assert_output_contains "has sleepz" "sleepz" "$OUT"
assert_output_contains "second sleep unchanged" "&& sleep 20" "$OUT"

echo "Test: timestamp passed inline"
OUT=$(run_hook "sleep 5")
assert_matches "hex timestamp" "sleepz 5 [0-9a-f]+" "$OUT"

echo "Test: uses short symlink path"
OUT=$(run_hook "sleep 5")
assert_output_contains "uses ~/.claude/sleepz" "~/.claude/sleepz" "$OUT"
assert_not_contains "no plugins/cache" "plugins/cache" "$OUT"

# ── Kill switch tests ──

echo ""
echo "=== Kill Switch Tests ==="
echo ""

echo "Test: disabled via env"
OUT=$(export DISABLE_CC_SLEEPZ=1; run_hook "sleep 60")
assert_empty "no output when disabled" "$OUT"

echo "Test: enabled by default"
OUT=$(unset DISABLE_CC_SLEEPZ; run_hook "sleep 60")
assert_not_empty "output when enabled" "$OUT"

# ── Results ──

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
