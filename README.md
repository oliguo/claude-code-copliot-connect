# claude-code-copilot-connect

> Use Claude Code with GitHub Copilot as the backend — auto-starts at login, restarts on crash.

This repo installs [`copilot-api`](https://github.com/ericc-ch/copilot-api) as a macOS
LaunchAgent so it runs automatically at every login. Claude Code connects to it via
`ANTHROPIC_BASE_URL=http://localhost:4141` — no manual startup needed.

## Prerequisites

- macOS (uses launchd + osascript)
- [Node.js](https://nodejs.org) v18+
- [GitHub Copilot](https://github.com/features/copilot) subscription
- `copilot-api` installed globally:
  ```bash
  npm install -g copilot-api
  ```
- [Claude Code](https://claude.ai/code) installed

## Quick Start

```bash
# 1. Clone
git clone https://github.com/oliguo/claude-code-copliot-connect.git
cd claude-code-copliot-connect

# 2. Authenticate with GitHub Copilot (follow the device flow shown)
copilot-api auth

# 3. Install — enter the token from step 2 when prompted
./install.sh
```

That's it. `copilot-api` now starts at every login and restarts automatically if it crashes.

## Configure Claude Code

Add to `~/.claude/settings.json`:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:4141",
    "ANTHROPIC_AUTH_TOKEN": "sk-dummy"
  }
}
```

> `sk-dummy` is intentional — copilot-api uses your GitHub Copilot token, not an Anthropic key.

## Install via Homebrew (local tap)

```bash
# Tap the local repo
brew tap oliguo/copilot-api-connect /path/to/claude-code-copliot-connect
brew install copilot-api-connect

# Authenticate and install
copilot-api auth
copilot-api-connect-install
```

## Installer Options

```bash
./install.sh                       # Install (prompts for token if not present)
./install.sh --dry-run             # Preview all actions + preflight checks, no changes made
./install.sh --force               # Overwrite token (use after copilot-api auth)
./install.sh --uninstall           # Remove LaunchAgent and all installed files
./install.sh --uninstall --dry-run # Preview what uninstall would remove, no changes made
./install.sh --help                # Show usage
```

### Dry Run Example

```
$ ./install.sh --dry-run

==========================================================
  DRY RUN - no changes will be made
==========================================================

[install] Running preflight checks...
[install] ✓ copilot-api found at /usr/local/bin/copilot-api
[install] ✓ osascript found (macOS notifications available)
[install] ✓ curl found
[install] ✓ scripts/copilot-api-start found
[install] ✓ Token file exists (40 bytes, chmod 600)
...
PREFLIGHT PASSED - ready to install.
Run: ./install.sh
```

### Uninstall Dry Run Example

```
$ ./install.sh --uninstall --dry-run

==========================================================
  DRY RUN - no changes will be made
==========================================================

[install] Planned uninstall actions:
[dry-run]   launchctl unload ~/Library/LaunchAgents/com.user.copilot-api.plist  (service is currently running)
[dry-run]   rm -f ~/Library/LaunchAgents/com.user.copilot-api.plist
[dry-run]   rm -f ~/.local/bin/copilot-api-start
[dry-run]   rm -rf ~/.config/copilot-api
[dry-run]   Logs at ~/Library/Logs/copilot-api — not removed (manual cleanup if desired)

DRY RUN COMPLETE - run: ./install.sh --uninstall
```

## What Gets Installed

| File | Purpose | Permissions |
|------|---------|-------------|
| `~/.local/bin/copilot-api-start` | launchd wrapper script | 755 |
| `~/.config/copilot-api/token` | GitHub OAuth token | 600 |
| `~/Library/LaunchAgents/com.user.copilot-api.plist` | launchd config | 600 |
| `~/Library/Logs/copilot-api/` | log directory | — |

The plist and token are generated at install time and **never stored in this repo**.

## Token Refresh

GitHub Copilot tokens expire periodically. When they do, copilot-api exits immediately
with `ERROR Failed to get Copilot token` in the logs. Fix:

```bash
copilot-api auth         # Get a fresh token (follow the device flow)
./install.sh --force     # Update the installed token and reload
```

## Troubleshooting

**Repeated "Failed to start" notifications**
Token has expired. Run: `copilot-api auth && ./install.sh --force`

**No notification, but API not responding**
Check logs: `tail -20 ~/Library/Logs/copilot-api/stdout.log`
Check stderr: `tail -20 ~/Library/Logs/copilot-api/stderr.log`

**Service shows exit code ≠ 0 in launchctl**
```bash
launchctl list | grep copilot-api   # check exit code (column 2)
tail -20 ~/Library/Logs/copilot-api/stderr.log
```

**`invalid authorization header` crash-loop after fresh install**
Your token was corrupted by an ANSI escape sequence during paste. Diagnose with:
```bash
xxd ~/.config/copilot-api/token | head -1
# Corrupt:  1b5b 313b 3243 6768 755f ...   ← starts with 1b (ESC byte)
# Clean:    6768 755f ...                   ← starts with "gh"
```
Fix by copying the token directly from where `copilot-api auth` saved it:
```bash
cp ~/.local/share/copilot-api/github_token ~/.config/copilot-api/token
chmod 600 ~/.config/copilot-api/token
./install.sh --force
```
> Note: `install.sh` now sanitises the token automatically on paste, so this
> should only affect installs from before that fix.

## Tested

All flags verified working on macOS (tested 2026-03-01):

| Command | Result |
|---------|--------|
| `./install.sh --help` | ✅ Clean usage output |
| `./install.sh --dry-run` | ✅ Preflight passes, planned actions shown |
| `./install.sh --dry-run --force` | ✅ Shows token overwrite in plan |
| `./install.sh --uninstall --dry-run` | ✅ Shows planned removals, no changes |
| `./install.sh --uninstall` | ✅ Unloads service, removes all files |
| `./install.sh` (fresh install) | ✅ Full end-to-end: installs, loads, API healthy |

Fresh install log output:
```
[install] ✓ copilot-api found at /usr/local/bin/copilot-api
[install] ✓ osascript found (macOS notifications available)
[install] ✓ curl found
[install] ✓ scripts/copilot-api-start found
[install] ⚠ No token file — will prompt during install
[install] Token saved (chmod 600).
[install] Wrapper installed.
/Users/oli/Library/LaunchAgents/com.user.copilot-api.plist: OK
[install] Plist written (chmod 600).
[install] LaunchAgent loaded.
```

Service health confirmed in logs:
```
➜ Listening on: http://localhost:4141/ (all interfaces)
--> GET /v1/models 200 3ms
[2026-03-01 17:23:12] copilot-api is healthy on port 4141
--> POST /v1/messages?beta=true 200 2s
```

## Quick Reference

```bash
# Check status (PID in col 1, exit code in col 2)
launchctl list | grep copilot-api

# View live logs
tail -f ~/Library/Logs/copilot-api/stdout.log

# Restart
launchctl kickstart -k gui/$(id -u)/com.user.copilot-api

# Stop
launchctl unload ~/Library/LaunchAgents/com.user.copilot-api.plist

# Verify API is responding
curl -s http://localhost:4141/v1/models | python3 -m json.tool | head -20
```

## License

MIT — see [LICENSE](LICENSE)
