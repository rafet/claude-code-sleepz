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

# Convert hex timestamp to decimal centiseconds, calculate remaining using awk
# No Python subprocess needed — awk is ~5ms vs Python's ~30ms
HOOK_CS=$((16#${HOOK_TS}))
NOW_CS=$(date +%s%N | awk '{printf "%d", ($1 / 10000000) % 8640000}')

REMAINING=$(awk -v hook="$HOOK_CS" -v now="$NOW_CS" -v dur="$DURATION" 'BEGIN {
    hook_s = hook / 100.0
    now_s = now / 100.0
    elapsed = now_s - hook_s
    if (elapsed < 0) elapsed += 86400
    remaining = dur - elapsed
    if (remaining <= 0)
        printf "0"
    else
        printf "%.2f", remaining
}')

if [[ "$REMAINING" == "0" ]]; then
    echo "sleepz: ${DURATION}s -> 0s (skipped)" >&2
elif [[ "$REMAINING" == "${DURATION}" || "$REMAINING" == "${DURATION}.00" ]]; then
    sleep "$REMAINING"
else
    echo "sleepz: ${DURATION}s -> ${REMAINING}s" >&2
    sleep "$REMAINING"
fi
