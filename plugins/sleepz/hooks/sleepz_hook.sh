#!/usr/bin/env bash
# sleepz_hook.sh — PreToolUse hook: detects `sleep <N>` in Bash commands,
# records a timestamp, and returns updatedInput with the sleepz wrapper.

set -euo pipefail

SYMLINK_PATH="$HOME/.claude/sleepz"

INPUT=$(cat)

# Kill switch
[[ "${DISABLE_CC_SLEEPZ:-}" == "1" ]] && exit 0

# Fast path: no "sleep " in input
case "$INPUT" in *'"sleep '*) ;; *) exit 0 ;; esac

# Extract command from JSON: {"tool_input":{"command":"VALUE"}}
if [[ "$INPUT" == *'"command": "'* ]]; then
    COMMAND="${INPUT#*\"command\": \"}"
else
    COMMAND="${INPUT#*\"command\":\"}"
fi
COMMAND="${COMMAND%\"*}"
# Unescape JSON
COMMAND="${COMMAND//\\n/$'\n'}"; COMMAND="${COMMAND//\\\"/\"}"; COMMAND="${COMMAND//\\\\/\\}"

[[ -z "$COMMAND" ]] && exit 0

# Skip nested bash -c commands
[[ "$COMMAND" =~ bash[[:space:]]+-c[[:space:]]+[\"\'] ]] && exit 0

# Match sleep <number> (integer or float)
[[ ! "$COMMAND" =~ sleep[[:space:]]+([0-9]+(\.[0-9]+)?) ]] && exit 0

DURATION="${BASH_REMATCH[1]}"
MATCH="${BASH_REMATCH[0]}"

# Skip suffixed durations (s, m, h, d)
AFTER="${COMMAND#*$MATCH}"
[[ "${AFTER:0:1}" =~ [smhd] ]] && exit 0

# Skip variable arguments
ARG="${COMMAND#*sleep}"; ARG="${ARG%%[[:space:]&|;]*}"
[[ "$ARG" == *'$'* ]] && exit 0

# Resolve sleepz.sh path
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SLEEPZ_SCRIPT="${PLUGIN_ROOT}/scripts/sleepz.sh"
[[ ! -f "$SLEEPZ_SCRIPT" ]] && exit 0

# Ensure symlink exists
CMD_PATH="$SLEEPZ_SCRIPT"
if [[ -L "$SYMLINK_PATH" ]]; then
    CMD_PATH="~/.claude/sleepz"
elif mkdir -p "$(dirname "$SYMLINK_PATH")" 2>/dev/null && ln -sf "$SLEEPZ_SCRIPT" "$SYMLINK_PATH" 2>/dev/null; then
    chmod +x "$SLEEPZ_SCRIPT" 2>/dev/null || true
    CMD_PATH="~/.claude/sleepz"
fi

# Timestamp: centiseconds since midnight in hex
HOOK_TS=$(printf '%x' $(( ($(date +%s) % 86400) * 100 )))

# Replace first `sleep <duration>` with sleepz call
MODIFIED="${COMMAND/${MATCH}/${CMD_PATH} ${DURATION} ${HOOK_TS}}"

# Escape for JSON output
ESCAPED="${MODIFIED//\\/\\\\}"; ESCAPED="${ESCAPED//\"/\\\"}"; ESCAPED="${ESCAPED//$'\n'/\\n}"; ESCAPED="${ESCAPED//$'\t'/\\t}"

# Output JSON
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","updatedInput":{"command":"%s"}}}' "$ESCAPED"
