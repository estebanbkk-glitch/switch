# DeepSeek Switcher for Claude Code

Routes Claude Code's API calls through DeepSeek instead of Anthropic, preserving the full Claude Code experience while using DeepSeek credits. Use this when running low on your Anthropic weekly limit.

---

## How It Works

A lightweight Node.js proxy runs locally on port 4000 and translates between Claude Code's Anthropic API format and DeepSeek's OpenAI-compatible API. Claude Code doesn't know the difference — it sends requests to `localhost:4000` instead of `api.anthropic.com`.

```
Claude Code  →  localhost:4000 (proxy)  →  api.deepseek.com
```

The proxy handles full translation: messages, tool use (Read/Write/Bash/etc.), streaming, and system prompts.

---

## Files

All files live in `C:\Users\USER\.claude\`

| File | Purpose |
|------|---------|
| `deepseek-on.bat` | Starts proxy, sets env var — double-click to activate |
| `deepseek-off.bat` | Kills proxy, clears env var — double-click to deactivate |
| `deepseek-proxy.js` | The Node.js proxy server (no npm dependencies) |
| `deepseek-tray.ps1` | System tray GUI with ON/OFF buttons, API key field, and usage stats |
| `launch-tray.vbs` | Silent launcher for the tray GUI |
| `start-proxy.vbs` | Launches the proxy as a hidden background process |
| `deepseek-stats.json` | Token usage data (auto-created, tracked across sessions) |
| `proxy.log` | Request log — created at runtime, shows all API calls |

---

## Usage

### Recommended: System Tray GUI
1. Double-click `launch-tray.vbs` (or the desktop shortcut)
2. Enter your DeepSeek API key in the GUI
3. Click **Use DeepSeek** to activate
4. Open a new terminal and run `claude` as normal
5. Click **Use Claude** to switch back

The tray icon shows the current state at a glance (orange = Claude, blue = DeepSeek).

### Legacy: Command-line toggles
**Switching to DeepSeek:**
1. Double-click `deepseek-on.bat`
2. Open a new PowerShell window — dark gray with `*** DEEPSEEK MODE ACTIVE ***`
3. Run `claude` as normal

**Switching back to Claude:**
1. Double-click `deepseek-off.bat`
2. Open a new PowerShell window — normal colors
3. Run `claude` as normal

> **Note:** The currently open Claude Code session is unaffected. Changes only apply to new sessions opened after running the bat.

---

## Usage Tracking

The proxy tracks DeepSeek token usage automatically. With the tray GUI open, you'll see real-time stats:

```
DeepSeek: 142.3K in / 28.7K out  (47 requests)
```

The data persists in `deepseek-stats.json` across sessions. Reset from the tray menu (**Reset Stats**).

---

## Visual Indicator

The PowerShell profile (`C:\Users\USER\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`) detects the `ANTHROPIC_BASE_URL` environment variable on session start:

- **DeepSeek active** → dark gray background, white text, window title `[ DEEPSEEK MODE ]`
- **Anthropic active** → normal PowerShell colors

---

## Verifying It's Working

Check `C:\Users\USER\.claude\proxy.log` — every `POST /v1/messages` entry is a call that went to DeepSeek, not Anthropic.

Or run a quick test from any PowerShell:
```powershell
Invoke-RestMethod -Uri "http://localhost:4000/health" -Method GET
```
Returns `{"status":"ok"}` if the proxy is running.

---

## DeepSeek API Key

The key is stored in `deepseek-on.bat` on the line:
```
set DEEPSEEK_API_KEY=sk-...
```

To rotate the key, edit that line only.

DeepSeek API: https://platform.deepseek.com

---

## Technical Notes

- **Model:** DeepSeek routes all requests to `deepseek-chat` regardless of which Claude model name is sent
- **"I'm Claude" responses:** DeepSeek's training data causes it to identify as Claude — this is cosmetic and doesn't affect functionality or billing
- **No Python required:** Earlier LiteLLM approach was abandoned due to Python 3.14 incompatibility with `orjson`. The current proxy is pure Node.js with zero dependencies.
- **Port:** Proxy uses `4000`. If something else is on that port, `deepseek-on.bat` clears it first.
