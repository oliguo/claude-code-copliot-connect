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
./install.sh              # Install (prompts for token if not present)
./install.sh --dry-run    # Preview all actions + preflight checks, no changes made
./install.sh --force      # Overwrite token (use after copilot-api auth)
./install.sh --uninstall  # Remove LaunchAgent and all installed files
./install.sh --help       # Show usage
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
