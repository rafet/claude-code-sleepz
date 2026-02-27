#!/usr/bin/env bash
# sleepz_hook.sh — Fast pre-filter for the sleepz hook.
#
# Reads stdin, checks if the command contains "sleep" using bash builtins.
# If not, exits immediately (~1ms). If yes, delegates to the Python hook
# for full parsing and command rewriting.

set -euo pipefail

INPUT=$(cat)

# Fast path: if "sleep" not in input, exit immediately
case "$INPUT" in
  *'"sleep '*)
    # Delegate to Python for full parsing
    echo "$INPUT" | python3 "${CLAUDE_PLUGIN_ROOT}/hooks/sleepz_hook.py"
    ;;
esac
