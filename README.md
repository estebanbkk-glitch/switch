# Switch - DeepSeek Switcher for Claude Code

Routes Claude Code through DeepSeek instead of Anthropic, preserving the full Claude Code experience while using DeepSeek credits. Perfect for when you're running low on your Anthropic weekly limit.

## How It Works

A lightweight Node.js proxy translates between Claude Code's Anthropic API format and DeepSeek's OpenAI-compatible API. Claude Code sends requests to `localhost:4000` instead of `api.anthropic.com` — it doesn't know the difference.

```
Claude Code → localhost:4000 (proxy) → api.deepseek.com
```

The proxy handles full translation: messages, tool use (Read/Write/Bash/etc.), streaming, and system prompts.

## Files

| File | Purpose |
|------|---------|
| `deepseek-proxy.js` | The Node.js proxy server (zero npm dependencies) |
| `deepseek-tray.ps1` | System tray GUI with ON/OFF buttons and API key field |
| `launch-tray.vbs` | Silent launcher for the tray GUI |
| `start-proxy.vbs` | Launches the proxy as a hidden background process |
| `deepseek-on.bat` | Starts proxy + sets env var (original method) |
| `deepseek-off.bat` | Kills proxy + clears env var (original method) |
| `DeepSeek-Switcher.md` | Full documentation |

## Quick Start (Recommended)

1. Double-click `launch-tray.vbs` or create a shortcut to it
2. Enter your DeepSeek API key in the GUI
3. Click **Use DeepSeek** — the tray icon turns blue
4. Open a new terminal and run `claude` as normal
5. Click **Use Claude** to switch back

## Visual Indicator

The system tray icon shows:
- **Orange** — Claude (Anthropic) mode
- **Blue** — DeepSeek active

PowerShell terminals also show a dark gray background with `*** DEEPSEEK MODE ACTIVE ***` when the proxy is on.

## Technical Notes

- **Model:** Routes to `deepseek-chat` regardless of which Claude model name is sent
- **"I'm Claude" responses:** DeepSeek's training data causes it to identify as Claude — cosmetic only
- **Port:** `4000` — cleared automatically on start
- **Dependencies:** Zero — pure Node.js with no npm packages

## Requirements

- Node.js installed
- DeepSeek API key from https://platform.deepseek.com
