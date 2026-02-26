#!/usr/bin/env python3
"""
Sleepz Hook for Claude Code

PreToolUse hook that detects `sleep <number>` in Bash commands and returns
updatedInput with the command modified to use the sleepz wrapper.
The wrapper subtracts the time the user spent in the permission dialog
from the sleep duration.
"""

import json
import os
import re
import stat
import sys
import time
from datetime import datetime
from pathlib import Path

# Debug log file
DEBUG_LOG_FILE = "/tmp/sleepz-log.txt"

# Short symlink path for cleaner permission dialog display
SYMLINK_PATH = os.path.expanduser("~/.claude/sleepz")


def debug_log(message):
    """Append debug message to log file with timestamp."""
    try:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
        with open(DEBUG_LOG_FILE, "a") as f:
            f.write(f"[{timestamp}] {message}\n")
    except Exception:
        pass


def ensure_symlink(target_script):
    """Ensure ~/.claude/bin/sleepz symlink exists and points to the target."""
    try:
        symlink = Path(SYMLINK_PATH)
        symlink.parent.mkdir(parents=True, exist_ok=True)

        if symlink.is_symlink() or symlink.exists():
            current_target = str(symlink.resolve())
            if current_target == str(Path(target_script).resolve()):
                return True
            symlink.unlink()

        symlink.symlink_to(target_script)
        # Ensure the target is executable
        os.chmod(target_script, os.stat(target_script).st_mode | stat.S_IEXEC)
        debug_log(f"Created symlink {SYMLINK_PATH} -> {target_script}")
        return True
    except Exception as e:
        debug_log(f"Failed to create symlink: {e}")
        return False


# Regex to match `sleep <number>` (integer or float, no suffix, no variable)
SLEEP_PATTERN = re.compile(r"\bsleep\s+(\d+(?:\.\d+)?)\b")

# Pattern to detect nested bash -c commands
NESTED_BASH_PATTERN = re.compile(r'\bbash\s+-c\s+["\']')


def main():
    """Main hook function."""
    # Kill switch via environment variable
    if os.environ.get("DISABLE_CC_SLEEPZ", "") == "1":
        debug_log("Sleepz disabled via DISABLE_CC_SLEEPZ=1")
        sys.exit(0)

    # Read input from stdin
    try:
        raw_input = sys.stdin.read()
        input_data = json.loads(raw_input)
    except (json.JSONDecodeError, Exception) as e:
        debug_log(f"Failed to parse input: {e}")
        sys.exit(0)

    tool_name = input_data.get("tool_name", "")
    tool_input = input_data.get("tool_input", {})

    # Only process Bash tool calls
    if tool_name != "Bash":
        sys.exit(0)

    command = tool_input.get("command", "")
    if not command:
        debug_log("No command found in tool_input")
        sys.exit(0)

    # Skip if the command is inside a bash -c "..." wrapper (nested context)
    if NESTED_BASH_PATTERN.search(command):
        debug_log(f"Skipping nested bash -c command: {command}")
        sys.exit(0)

    # Find the first sleep match
    match = SLEEP_PATTERN.search(command)
    if not match:
        sys.exit(0)

    duration_str = match.group(1)

    # Verify this isn't sleep with a suffix (e.g., sleep 60s, sleep 1m)
    match_end = match.end()
    if match_end < len(command) and command[match_end] in "smhd":
        debug_log(f"Skipping sleep with suffix: {command[match.start():match_end+1]}")
        sys.exit(0)

    # Verify this isn't sleep with a variable (e.g., sleep $VAR)
    sleep_arg_start = match.start() + len("sleep")
    remaining = command[sleep_arg_start : match.end()]
    if "$" in remaining:
        debug_log(f"Skipping sleep with variable: {remaining}")
        sys.exit(0)

    debug_log(f"Found sleep {duration_str} in command: {command}")

    # Resolve the plugin root to find sleepz.sh
    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT", "")
    if not plugin_root:
        plugin_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    sleepz_script = os.path.join(plugin_root, "scripts", "sleepz.sh")

    if not os.path.isfile(sleepz_script):
        debug_log(f"sleepz.sh not found at {sleepz_script}")
        sys.exit(0)

    # Determine the command path to use in the replacement
    # Prefer short symlink path for cleaner permission dialog display
    if ensure_symlink(sleepz_script):
        cmd_path = "~/.claude/sleepz"
    else:
        cmd_path = sleepz_script

    # Record current time as seconds-since-midnight in hex for shorter display
    hook_ts = format(int(time.time() % 86400), 'x')

    # Build the replacement: `sleep N` -> `sleepz N <timestamp>`
    sleep_replacement = f'{cmd_path} {duration_str} {hook_ts}'
    modified_command = command[: match.start()] + sleep_replacement + command[match.end() :]

    debug_log(f"Modified command: {modified_command}")

    # Return updatedInput with ask permission (user still sees the dialog)
    # Must use stdout + exit 0 for JSON to be parsed by Claude Code
    result = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "updatedInput": {"command": modified_command},
        }
    }

    print(json.dumps(result))
    sys.exit(0)


if __name__ == "__main__":
    main()
