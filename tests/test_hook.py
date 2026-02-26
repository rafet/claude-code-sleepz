#!/usr/bin/env python3
"""Unit tests for smart_sleep_hook.py"""

import json
import os
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
    """Run the hook with a given Bash command and return (exit_code, stderr_json)."""
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
    if result.stderr.strip():
        try:
            parsed = json.loads(result.stderr)
        except json.JSONDecodeError:
            pass
    return result.returncode, parsed


class TestHookDetection(unittest.TestCase):
    """Test that the hook correctly identifies which commands to modify."""

    def test_basic_sleep(self):
        code, output = run_hook("sleep 60")
        self.assertEqual(code, 2)
        self.assertIn("smart-sleep.sh", output["hookSpecificOutput"]["updatedInput"]["command"])

    def test_sleep_with_continuation(self):
        code, output = run_hook("sleep 60 && echo done")
        self.assertEqual(code, 2)
        self.assertIn("&& echo done", output["hookSpecificOutput"]["updatedInput"]["command"])

    def test_fractional_sleep(self):
        code, output = run_hook("sleep 0.5")
        self.assertEqual(code, 2)
        self.assertIn("0.5", output["hookSpecificOutput"]["updatedInput"]["command"])

    def test_no_sleep(self):
        code, _ = run_hook("echo hello")
        self.assertEqual(code, 0)

    def test_sleep_with_variable(self):
        code, _ = run_hook("sleep $VAR")
        self.assertEqual(code, 0)

    def test_sleep_with_suffix_s(self):
        code, _ = run_hook("sleep 60s")
        self.assertEqual(code, 0)

    def test_sleep_with_suffix_m(self):
        code, _ = run_hook("sleep 1m")
        self.assertEqual(code, 0)

    def test_nested_bash_c(self):
        code, _ = run_hook('bash -c "sleep 60"')
        self.assertEqual(code, 0)

    def test_non_bash_tool(self):
        payload = json.dumps({"tool_name": "Edit", "tool_input": {"command": "sleep 60"}})
        result = subprocess.run(
            [sys.executable, HOOK_SCRIPT],
            input=payload,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0)

    def test_empty_command(self):
        code, _ = run_hook("")
        self.assertEqual(code, 0)


class TestHookOutput(unittest.TestCase):
    """Test the structure of the hook's output."""

    def test_output_has_correct_structure(self):
        _, output = run_hook("sleep 30")
        self.assertIn("hookSpecificOutput", output)
        hook_output = output["hookSpecificOutput"]
        self.assertEqual(hook_output["permissionDecision"], "ask")
        self.assertIn("updatedInput", hook_output)
        self.assertIn("command", hook_output["updatedInput"])

    def test_only_first_sleep_replaced(self):
        _, output = run_hook("sleep 10 && sleep 20")
        cmd = output["hookSpecificOutput"]["updatedInput"]["command"]
        self.assertIn("smart-sleep.sh", cmd)
        # The second sleep should remain untouched
        self.assertIn("&& sleep 20", cmd)

    def test_timestamp_file_created(self):
        _, output = run_hook("sleep 5")
        cmd = output["hookSpecificOutput"]["updatedInput"]["command"]
        # Extract timestamp file path from the command
        # Format: bash "/path/to/smart-sleep.sh" 5 "/path/to/ts-file.txt"
        parts = cmd.split('"')
        ts_file = parts[-2]  # second-to-last quoted string
        self.assertTrue(os.path.isfile(ts_file), f"Timestamp file {ts_file} should exist")
        # Clean up
        os.unlink(ts_file)


class TestKillSwitch(unittest.TestCase):
    """Test the DISABLE_CC_SMART_SLEEP environment variable."""

    def test_disabled_via_env(self):
        code, _ = run_hook("sleep 60", env_override={"DISABLE_CC_SMART_SLEEP": "1"})
        self.assertEqual(code, 0)

    def test_enabled_by_default(self):
        code, _ = run_hook("sleep 60", env_override={"DISABLE_CC_SMART_SLEEP": ""})
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
