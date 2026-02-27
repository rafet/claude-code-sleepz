#!/usr/bin/env bash
# Unit tests for sleepz_hook.sh (pure bash hook)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$SCRIPT_DIR/../plugins/sleepz"
HOOK_SH="$PLUGIN_ROOT/hooks/sleepz_hook.sh"

# Shared helpers
source "$SCRIPT_DIR/test_helpers.sh"

# Isolate filesystem: temp HOME + cleanup trap
HOME_BACKUP="$HOME"
TEST_HOME=$(mktemp -d)
export HOME="$TEST_HOME"
mkdir -p "$TEST_HOME/.claude"

cleanup() {
    rm -rf "$TEST_HOME"
    export HOME="$HOME_BACKUP"
}
trap cleanup EXIT

run_hook() {
    local command="$1"
    local payload="{\"tool_name\": \"Bash\", \"tool_input\": {\"command\": \"$command\"}}"
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$HOOK_SH" <<< "$payload" 2>/dev/null
}

# ── Detection tests ──

echo "=== Hook Detection Tests ==="
echo ""

echo "Test: basic sleep"
OUT=$(run_hook "sleep 60")
assert_contains "modifies command" "sleepz" "$OUT"

echo "Test: sleep with continuation"
OUT=$(run_hook "sleep 60 && echo done")
assert_contains "keeps continuation" "&& echo done" "$OUT"

echo "Test: fractional sleep"
OUT=$(run_hook "sleep 0.5")
assert_contains "keeps fraction" "0.5" "$OUT"

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
assert_contains "has hookSpecificOutput" "hookSpecificOutput" "$OUT"
assert_contains "has hookEventName" "PreToolUse" "$OUT"
assert_contains "has updatedInput" "updatedInput" "$OUT"
assert_not_contains "no permissionDecision" "permissionDecision" "$OUT"

echo "Test: only first sleep replaced"
OUT=$(run_hook "sleep 10 && sleep 20")
assert_contains "has sleepz" "sleepz" "$OUT"
assert_contains "second sleep unchanged" "&& sleep 20" "$OUT"

echo "Test: timestamp and symlink path"
OUT=$(run_hook "sleep 5")
assert_matches "hex timestamp" "sleepz 5 [0-9a-f]+" "$OUT"
assert_contains "uses ~/.claude/sleepz" "~/.claude/sleepz" "$OUT"
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

report_results
