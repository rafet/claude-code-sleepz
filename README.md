<p align="center">
  <img src="img.png" alt="Sleepz mascot" width="260">
</p>

<h1 align="center">Sleepz</h1>

<p align="center">
  <strong>Stop wasting time waiting for <code>sleep</code> to finish.</strong><br>
  A Claude Code plugin that automatically adjusts sleep durations to account for permission dialog wait time and internal processing overhead.
</p>

<p align="center">
  <a href="#install">Install</a> · <a href="#how-it-works">How It Works</a> · <a href="#what-gets-adjusted">Compatibility</a> · <a href="#configuration">Configuration</a>
</p>

---

## The Problem

When Claude Code proposes `sleep 60 && npm run build`, you have to approve it first. If you take 15 seconds to hit "Allow", the sleep still runs for the full 60 seconds — meaning **75 seconds** pass instead of the intended 60.

Claude Code also adds its own processing overhead (~1s) between deciding to run a command and actually executing it. These hidden delays add up.

**Sleepz fixes this.** It accounts for both delays and ensures the total wall-clock time matches what was originally intended.

## Install

```
/plugin marketplace add rafet/claude-code-sleepz
/plugin install sleepz@claude-code-sleepz
```

That's it. No configuration needed — it works out of the box.

## How It Works

A `PreToolUse` hook intercepts Bash commands containing `sleep`, records a timestamp, and replaces `sleep` with a lightweight wrapper. After you approve the command, the wrapper calculates how much time already elapsed and sleeps only the remaining duration.

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

The hook itself adds only **~30ms** of overhead — negligible compared to the time it saves.

## What Gets Adjusted

| Command | Behavior |
|---------|----------|
| `sleep 60` | Adjusted |
| `sleep 60 && cmd` | First sleep adjusted, rest of the command runs normally |
| `sleep 0.5` | Adjusted (fractional values supported) |
| `sleep $VAR` | Skipped — variables can't be parsed statically |
| `sleep 60s` / `sleep 1m` | Skipped — suffixed durations not supported |
| `bash -c "sleep 60"` | Skipped — nested shells are left untouched |
| `sleep 10 && sleep 20` | Only the first sleep is adjusted |
| Hook or script error | Original command runs unmodified — never breaks your workflow |

## Configuration

Disable Sleepz temporarily with an environment variable:

```bash
export DISABLE_CC_SLEEPZ=1
```

Debug logs are written to `/tmp/sleepz-log.txt` for troubleshooting.

## Requirements

- Python 3
- Bash
- [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) with plugin support

## License

MIT
