#!/usr/bin/env bash
# sleepz_hook.sh — PreToolUse hook for the sleepz plugin.
#
# Detects `sleep <number>` in Bash commands, records a timestamp, and returns
# updatedInput with the command modified to use the sleepz wrapper.
# Pure bash implementation.

set -euo pipefail

DEBUG_LOG="/tmp/sleepz-log.txt"
SYMLINK_PATH="$HOME/.claude/sleepz"

debug_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$DEBUG_LOG" 2>/dev/null || true
}

# Read stdin
INPUT=$(cat)

# Kill switch
if [[ "${DISABLE_CC_SLEEPZ:-}" == "1" ]]; then
    debug_log "Sleepz disabled via DISABLE_CC_SLEEPZ=1"
    exit 0
fi

# Fast path: no "sleep " in input, exit immediately
case "$INPUT" in
    *'"sleep '*) ;;
    *) exit 0 ;;
esac

# Extract command value from JSON: {"tool_input":{"command":"VALUE"}}
# Handle both "command":"..." and "command": "..." (json.dumps adds space)
if [[ "$INPUT" == *'"command": "'* ]]; then
    COMMAND="${INPUT#*\"command\": \"}"
else
    COMMAND="${INPUT#*\"command\":\"}"
fi
COMMAND="${COMMAND%\"*}"
# Unescape JSON
COMMAND="${COMMAND//\\n/$'\n'}"
COMMAND="${COMMAND//\\\"/\"}"
COMMAND="${COMMAND//\\\\/\\}"

if [[ -z "$COMMAND" ]]; then
    exit 0
fi

# Skip nested bash -c commands
if [[ "$COMMAND" =~ bash[[:space:]]+-c[[:space:]]+[\"\'] ]]; then
    debug_log "Skipping nested bash -c command: $COMMAND"
    exit 0
fi

# Match sleep <number> (integer or float)
if [[ ! "$COMMAND" =~ sleep[[:space:]]+([0-9]+(\.[0-9]+)?) ]]; then
    exit 0
fi

DURATION="${BASH_REMATCH[1]}"

# Check for suffix after duration (s, m, h, d)
MATCH="${BASH_REMATCH[0]}"
AFTER="${COMMAND#*$MATCH}"
NEXT_CHAR="${AFTER:0:1}"
if [[ "$NEXT_CHAR" =~ [smhd] ]]; then
    debug_log "Skipping sleep with suffix: sleep ${DURATION}${NEXT_CHAR}"
    exit 0
fi

# Check for variable ($) in the sleep argument area
BEFORE_SLEEP="${COMMAND%%sleep*}"
AFTER_SLEEP="${COMMAND#*sleep}"
ARG="${AFTER_SLEEP%%[[:space:]&|;]*}"
if [[ "$ARG" == *'$'* ]]; then
    debug_log "Skipping sleep with variable"
    exit 0
fi

debug_log "Found sleep ${DURATION} in command: $COMMAND"

# Resolve sleepz.sh path
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SLEEPZ_SCRIPT="${PLUGIN_ROOT}/scripts/sleepz.sh"

if [[ ! -f "$SLEEPZ_SCRIPT" ]]; then
    debug_log "sleepz.sh not found at $SLEEPZ_SCRIPT"
    exit 0
fi

# Ensure symlink exists
CMD_PATH="$SLEEPZ_SCRIPT"
if [[ -L "$SYMLINK_PATH" ]]; then
    CMD_PATH="~/.claude/sleepz"
elif mkdir -p "$(dirname "$SYMLINK_PATH")" 2>/dev/null && ln -sf "$SLEEPZ_SCRIPT" "$SYMLINK_PATH" 2>/dev/null; then
    chmod +x "$SLEEPZ_SCRIPT" 2>/dev/null || true
    CMD_PATH="~/.claude/sleepz"
    debug_log "Created symlink $SYMLINK_PATH -> $SLEEPZ_SCRIPT"
fi

# Timestamp: centiseconds since midnight in hex
NOW_SECS=$(date +%s)
MIDNIGHT_CS=$(( (NOW_SECS % 86400) * 100 ))
HOOK_TS=$(printf '%x' "$MIDNIGHT_CS")

# Build modified command: replace first `sleep <duration>` with sleepz call
REPLACEMENT="${CMD_PATH} ${DURATION} ${HOOK_TS}"
MODIFIED="${COMMAND/${MATCH}/${REPLACEMENT}}"

debug_log "Modified command: $MODIFIED"

# Escape for JSON output
ESCAPED="${MODIFIED//\\/\\\\}"
ESCAPED="${ESCAPED//\"/\\\"}"
ESCAPED="${ESCAPED//$'\n'/\\n}"
ESCAPED="${ESCAPED//$'\t'/\\t}"

# Output JSON to stdout
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","updatedInput":{"command":"%s"}}}' "$ESCAPED"
