#!/usr/bin/env python3
"""Unit tests for smart_sleep_hook.py"""

import json
import os
import re
import subprocess
import sys
import unittest

HOOK_SCRIPT = os.path.join(
    os.path.dirname(__file__),
    "..",
    "plugins",
    "smart-sleep",
    "hooks",
    "smart_sleep_hook.py",
)


def run_hook(command, env_override=None):
    """Run the hook with a given Bash command and return (exit_code, stdout_json).

    The hook outputs JSON to stdout and exits with 0 when it modifies a command.
    When the command doesn't match (no sleep), it also exits 0 but with no stdout.
    """
    payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": command}})
    env = os.environ.copy()
    if env_override:
        env.update(env_override)
    result = subprocess.run(
        [sys.executable, HOOK_SCRIPT],
        input=payload,
        capture_output=True,
        text=True,
        env=env,
    )
    parsed = None
    if result.stdout.strip():
        try:
            parsed = json.loads(result.stdout)
        except json.JSONDecodeError:
            pass
    return result.returncode, parsed


class TestHookDetection(unittest.TestCase):
    """Test that the hook correctly identifies which commands to modify."""

    def test_basic_sleep(self):
        code, output = run_hook("sleep 60")
        self.assertEqual(code, 0)
        self.assertIsNotNone(output)
        cmd = output["hookSpecificOutput"]["updatedInput"]["command"]
        self.assertIn("smart-sleep", cmd)

    def test_sleep_with_continuation(self):
        code, output = run_hook("sleep 60 && echo done")
        self.assertEqual(code, 0)
        self.assertIn("&& echo done", output["hookSpecificOutput"]["updatedInput"]["command"])

    def test_fractional_sleep(self):
        code, output = run_hook("sleep 0.5")
        self.assertEqual(code, 0)
        self.assertIsNotNone(output)
        self.assertIn("0.5", output["hookSpecificOutput"]["updatedInput"]["command"])

    def test_no_sleep(self):
        code, output = run_hook("echo hello")
        self.assertEqual(code, 0)
        self.assertIsNone(output)

    def test_sleep_with_variable(self):
        code, output = run_hook("sleep $VAR")
        self.assertEqual(code, 0)
        self.assertIsNone(output)

    def test_sleep_with_suffix_s(self):
        code, output = run_hook("sleep 60s")
        self.assertEqual(code, 0)
        self.assertIsNone(output)

    def test_sleep_with_suffix_m(self):
        code, output = run_hook("sleep 1m")
        self.assertEqual(code, 0)
        self.assertIsNone(output)

    def test_nested_bash_c(self):
        code, output = run_hook('bash -c "sleep 60"')
        self.assertEqual(code, 0)
        self.assertIsNone(output)

    def test_non_bash_tool(self):
        payload = json.dumps({"tool_name": "Edit", "tool_input": {"command": "sleep 60"}})
        result = subprocess.run(
            [sys.executable, HOOK_SCRIPT],
            input=payload,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "")

    def test_empty_command(self):
        code, output = run_hook("")
        self.assertEqual(code, 0)
        self.assertIsNone(output)


class TestHookOutput(unittest.TestCase):
    """Test the structure of the hook's output."""

    def test_output_has_correct_structure(self):
        _, output = run_hook("sleep 30")
        self.assertIn("hookSpecificOutput", output)
        hook_output = output["hookSpecificOutput"]
        self.assertEqual(hook_output["hookEventName"], "PreToolUse")
        self.assertEqual(hook_output["permissionDecision"], "ask")
        self.assertIn("updatedInput", hook_output)
        self.assertIn("command", hook_output["updatedInput"])

    def test_only_first_sleep_replaced(self):
        _, output = run_hook("sleep 10 && sleep 20")
        cmd = output["hookSpecificOutput"]["updatedInput"]["command"]
        self.assertIn("smart-sleep", cmd)
        # The second sleep should remain untouched
        self.assertIn("&& sleep 20", cmd)

    def test_timestamp_passed_inline(self):
        _, output = run_hook("sleep 5")
        cmd = output["hookSpecificOutput"]["updatedInput"]["command"]
        # Timestamp should be an integer (seconds since midnight, max 86400)
        # Format: smart-sleep 5 <timestamp>
        self.assertRegex(cmd, r"smart-sleep 5 \d+")
        # Should NOT contain temp file paths
        self.assertNotIn("/var/folders", cmd)
        self.assertNotIn("smart-sleep-ts-", cmd)

    def test_uses_short_symlink_path(self):
        _, output = run_hook("sleep 5")
        cmd = output["hookSpecificOutput"]["updatedInput"]["command"]
        # Should use ~/.claude/bin/smart-sleep (short path)
        self.assertIn("~/.claude/bin/smart-sleep", cmd)
        # Should NOT contain long cache paths
        self.assertNotIn("plugins/cache", cmd)


class TestKillSwitch(unittest.TestCase):
    """Test the DISABLE_CC_SMART_SLEEP environment variable."""

    def test_disabled_via_env(self):
        code, output = run_hook("sleep 60", env_override={"DISABLE_CC_SMART_SLEEP": "1"})
        self.assertEqual(code, 0)
        self.assertIsNone(output)

    def test_enabled_by_default(self):
        code, output = run_hook("sleep 60", env_override={"DISABLE_CC_SMART_SLEEP": ""})
        self.assertEqual(code, 0)
        self.assertIsNotNone(output)


if __name__ == "__main__":
    unittest.main()
