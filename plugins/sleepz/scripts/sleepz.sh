#!/usr/bin/env bash
# sleepz.sh — Runtime wrapper for the sleepz plugin.
#
# Called in place of `sleep <duration>` after the user approves the command.
# Reads the hook timestamp passed as an argument, calculates how long the
# user spent in the permission dialog, and sleeps only the remaining time.
#
# Usage: sleepz.sh <duration> <hook_timestamp_hex>

set -euo pipefail

DURATION="${1:-}"
HOOK_TS="${2:-}"

if [[ -z "$DURATION" || -z "$HOOK_TS" ]]; then
    echo "sleepz: missing arguments, falling back to full sleep" >&2
    sleep "${DURATION:-0}"
    exit 0
fi

REMAINING=$(python3 -c "
import time, sys
try:
    hook_ts = int('${HOOK_TS}', 16)
    duration = float('${DURATION}')
    now = int(time.time() % 86400)
    elapsed = (now - hook_ts + 86400) % 86400
    remaining = duration - elapsed
    if remaining <= 0:
        print('0', end='')
    else:
        print(f'{remaining:.2f}', end='')
except Exception as e:
    print('${DURATION}', end='', file=sys.stdout)
    print(f'sleepz: calc error: {e}', file=sys.stderr)
" 2>&2)

if [[ "$REMAINING" == "0" ]]; then
    echo "sleepz: ${DURATION}s -> 0s (skipped)" >&2
elif [[ "$REMAINING" == "${DURATION}" || "$REMAINING" == "${DURATION}.00" ]]; then
    sleep "$REMAINING"
else
    echo "sleepz: ${DURATION}s -> ${REMAINING}s" >&2
    sleep "$REMAINING"
fi
