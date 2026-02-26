# Smart Sleep

A [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) plugin that adjusts `sleep` durations in Bash commands to account for the time you spend in the permission dialog.

## The Problem

When Claude Code proposes `sleep 60 && npm run build`, you have to approve it first. If you take 15 seconds to hit "Allow", the sleep still runs for the full 60 seconds — so 75 seconds pass instead of the intended 60.

## How It Works

A PreToolUse hook intercepts Bash commands containing `sleep`. It records a timestamp before the permission dialog appears, then replaces `sleep` with a wrapper script that calculates how much time already elapsed and sleeps only the remaining duration.

```
sleep 60 && npm run build
       │
       ▼
  Hook records timestamp
       │
       ▼
  Permission dialog (you wait 15s)
       │
       ▼
  Wrapper: 60 - 15 = 45s remaining
       │
       ▼
  sleep 45 && npm run build
```

## Install

```
/plugin marketplace add rafet/claude-smart-sleep
/plugin install smart-sleep@claude-smart-sleep
```

## What Gets Adjusted

| Command | Behavior |
|---------|----------|
| `sleep 60` | Adjusted |
| `sleep 60 && cmd` | First sleep adjusted |
| `sleep 0.5` | Adjusted (fractional) |
| `sleep $VAR` | Skipped (can't parse) |
| `sleep 60s` / `sleep 1m` | Skipped (suffix) |
| `bash -c "sleep 60"` | Skipped (nested) |
| Multiple sleeps | Only first adjusted |
| Hook/script error | Original command runs unmodified |

## Configuration

Disable the plugin temporarily:

```bash
export DISABLE_CC_SMART_SLEEP=1
```

Debug logs are written to `/tmp/smart-sleep-log.txt`.

## Requirements

- Python 3
- Bash
