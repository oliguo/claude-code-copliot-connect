# Copilot Instructions

## Project Purpose

Installs [`copilot-api`](https://github.com/ericc-ch/copilot-api) as a macOS LaunchAgent so Claude Code connects to GitHub Copilot as its backend via `ANTHROPIC_BASE_URL=http://localhost:4141`. No manual startup — service auto-starts at login and restarts on crash.

## Key Files

| File | Role |
|------|------|
| `install.sh` | Installer: writes token, plist, wrapper; supports `--dry-run`, `--force`, `--uninstall` |
| `scripts/copilot-api-start` | launchd wrapper — run by launchd, NOT directly by users |
| `brew/copilot-api-connect.rb` | Homebrew formula for local tap install |

Generated at install time (not in repo, excluded by `.gitignore`):
- `~/.config/copilot-api/token` — GitHub OAuth token (chmod 600)
- `~/Library/LaunchAgents/com.user.copilot-api.plist` — embeds token at install time (chmod 600)
- `~/.local/bin/copilot-api-start` — copy of `scripts/copilot-api-start`

## Critical Architecture Decisions

**`exec` at end of wrapper, not `&` background:** `scripts/copilot-api-start` ends with `exec "$COPILOT_BIN" start ...`. This replaces the shell process with node, so launchd tracks the node PID directly. `KeepAlive` and crash recovery depend on this — never change to a backgrounded call.

**Background subshell runs BEFORE `exec`:** The health-check `( ... ) &` must be launched before `exec`, since the shell process is replaced after `exec`. The subshell notifies macOS only on failure to avoid notification spam.

**`elapsed=$(( elapsed + POLL_INTERVAL ))` — not `(( elapsed += ... ))`:** The `(( expr ))` form returns exit code 1 when the result is 0, which triggers `set -e` and silently kills the subshell. Use command substitution arithmetic inside the health-check loop.

**Token sanitisation order matters:** `sed` strips ANSI escape sequences first, then `tr -cd '[:print:]'` strips non-printables. Reversing leaves printable remnants of escape codes in the token.

**`sed` uses `[[:space:]]*` not `\?`:** macOS BSD sed uses BRE; `\?` is not valid and causes literal `#` in output. The `--help` text extraction uses `s/^#[[:space:]]*//'`.

**Token embedded in plist at install time:** `launchd EnvironmentVariables` requires the literal value at load time. The plist is chmod 600 and never committed. Re-auth requires regenerating the plist via `./install.sh --force`.

## Developer Workflows

```bash
# Test installer logic without writing anything
./install.sh --dry-run

# After editing scripts/copilot-api-start, redeploy
./install.sh --force

# Token expired (symptom: "ERROR Failed to get Copilot token" in stderr.log)
copilot-api auth && ./install.sh --force

# Diagnose ANSI-corrupted token (starts with 0x1b = ESC byte)
xxd ~/.config/copilot-api/token | head -1

# Live log monitoring
tail -f ~/Library/Logs/copilot-api/stdout.log

# Service status (col 1 = PID, col 2 = last exit code)
launchctl list | grep copilot-api

# Restart running service
launchctl kickstart -k gui/$(id -u)/com.user.copilot-api
```

## Environment Variable Overrides

Both `install.sh` and `scripts/copilot-api-start` respect:
- `COPILOT_BIN` — override binary path (default: `/usr/local/bin/copilot-api`)
- `COPILOT_API_PORT` — override port (default: `4141`)

The plist injects `GITHUB_PERSONAL_ACCESS_TOKEN` and a minimal `PATH` into the launchd environment.

## Tokens

Tokens from `copilot-api auth` have prefix `ghu_` and are stored at `~/.local/share/copilot-api/github_token`. `install.sh` prompts to paste them into `~/.config/copilot-api/token`. Tokens expire periodically; the service crash-loops with `invalid authorization header` when they do.
