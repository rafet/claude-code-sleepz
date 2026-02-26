#!/usr/bin/env bash
# smart-sleep.sh — Runtime wrapper for the smart-sleep plugin.
#
# Called in place of `sleep <duration>` after the user approves the command.
# Reads the timestamp recorded by the PreToolUse hook, calculates how long the
# user spent in the permission dialog, and sleeps only the remaining time.
#
# Usage: smart-sleep.sh <duration> <timestamp_file>

set -euo pipefail

DURATION="${1:-}"
TIMESTAMP_FILE="${2:-}"

if [[ -z "$DURATION" || -z "$TIMESTAMP_FILE" ]]; then
    echo "smart-sleep: missing arguments, falling back to full sleep" >&2
    sleep "${DURATION:-0}"
    exit 0
fi

cleanup() {
    rm -f "$TIMESTAMP_FILE" 2>/dev/null || true
}
trap cleanup EXIT

# Read the hook timestamp and calculate remaining sleep
if [[ -f "$TIMESTAMP_FILE" ]]; then
    HOOK_TS=$(cat "$TIMESTAMP_FILE")

    REMAINING=$(python3 -c "
import time, sys
try:
    hook_ts = float('${HOOK_TS}')
    duration = float('${DURATION}')
    elapsed = time.time() - hook_ts
    remaining = duration - elapsed
    if remaining <= 0:
        print('0', end='')
    else:
        # Round to 2 decimal places
        print(f'{remaining:.2f}', end='')
except Exception as e:
    print('${DURATION}', end='', file=sys.stdout)
    print(f'smart-sleep: calc error: {e}', file=sys.stderr)
" 2>&2)

    if [[ "$REMAINING" == "0" ]]; then
        echo "smart-sleep: adjusted ${DURATION}s -> 0s (skipped entirely)" >&2
    else
        echo "smart-sleep: adjusted ${DURATION}s -> ${REMAINING}s" >&2
        sleep "$REMAINING"
    fi
else
    echo "smart-sleep: timestamp file not found, using full sleep ${DURATION}s" >&2
    sleep "$DURATION"
fi
