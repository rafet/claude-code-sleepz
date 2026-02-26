#!/usr/bin/env bash
# smart-sleep.sh — Runtime wrapper for the smart-sleep plugin.
#
# Called in place of `sleep <duration>` after the user approves the command.
# Reads the hook timestamp passed as an argument, calculates how long the
# user spent in the permission dialog, and sleeps only the remaining time.
#
# Usage: smart-sleep.sh <duration> <hook_timestamp>

set -euo pipefail

DURATION="${1:-}"
HOOK_TS="${2:-}"

if [[ -z "$DURATION" || -z "$HOOK_TS" ]]; then
    echo "smart-sleep: missing arguments, falling back to full sleep" >&2
    sleep "${DURATION:-0}"
    exit 0
fi

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
