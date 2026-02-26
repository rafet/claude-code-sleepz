<p align="center">
  <img src="img.png" alt="Sleepz mascot" width="200">
</p>

# Sleepz

A [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) plugin that adjusts `sleep` durations in Bash commands to account for the time you spend in the permission dialog — and Claude Code's own internal processing overhead.

## The Problem

When Claude Code proposes `sleep 60 && npm run build`, you have to approve it first. If you take 15 seconds to hit "Allow", the sleep still runs for the full 60 seconds — so 75 seconds pass instead of the intended 60.

On top of that, Claude Code itself adds processing overhead between deciding to run a command and actually executing it. Sleepz accounts for both delays.

## How It Works

A PreToolUse hook intercepts Bash commands containing `sleep`. It records a timestamp before the permission dialog appears, then replaces `sleep` with a wrapper script that calculates how much time already elapsed — including both user wait time and Claude Code's internal overhead — and sleeps only the remaining duration.

```
sleep 60 && npm run build
       │
       ▼
  Hook records timestamp ─────────────────┐
       │                                   │
       ▼                                   │
  Claude Code overhead (~1s)               │  These delays are
       │                                   │  subtracted from
       ▼                                   │  sleep duration
  Permission dialog (you wait 15s)         │
       │                                   │
       ▼                                   │
  Wrapper: 60 - 16 = 44s remaining  ──────┘
       │
       ▼
  sleep 44 && npm run build
```

## Install

```
/plugin marketplace add rafet/claude-code-sleepz
/plugin install sleepz@claude-code-sleepz
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
export DISABLE_CC_SLEEPZ=1
```

Debug logs are written to `/tmp/sleepz-log.txt`.

## Requirements

- Python 3
- Bash
