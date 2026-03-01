# CLAUDE.md — Session Memory for claude-code-copilot-connect

> Read this file at the start of every Claude Code session in this repo.
> It contains all context needed to understand, maintain, and extend this project.

## What This Project Does

Installs `copilot-api` as a macOS LaunchAgent so Claude Code
(configured with `ANTHROPIC_BASE_URL=http://localhost:4141`) starts automatically
at login with a running backend — no manual `copilot-api start` required.

## Repo Structure

```
install.sh                  ← main installer (one command to set up a new machine)
scripts/
  copilot-api-start         ← launchd wrapper script (copied to ~/.local/bin/ at install)
brew/
  copilot-api-connect.rb    ← Homebrew formula for `brew install` support
CLAUDE.md                   ← this file (session memory)
README.md                   ← user-facing setup guide
LICENSE                     ← MIT
.gitignore                  ← excludes token, plist (contains token), logs
```

## What install.sh Creates (NOT in this repo — excluded by .gitignore)

| Path | Purpose | Perms |
|------|---------|-------|
| `~/.local/bin/copilot-api-start` | launchd wrapper (copied from scripts/) | 755 |
| `~/.config/copilot-api/token` | GitHub OAuth token | 600 |
| `~/Library/LaunchAgents/com.user.copilot-api.plist` | launchd config (embeds token) | 600 |
| `~/Library/Logs/copilot-api/` | log directory | — |

**The plist and token are never committed** (excluded by .gitignore).

## Key Design Decisions

1. **`exec` in wrapper** — copilot-api runs in the foreground via `exec` at the end of
   `scripts/copilot-api-start`. This means launchd tracks the node process PID directly.
   The wrapper shell is replaced by node. KeepAlive and crash recovery work correctly.

2. **Background subshell for health-check** — `( ... ) &` runs BEFORE the `exec`.
   It polls `GET /v1/models` every 2s up to 30s. Sends a macOS notification ONLY on
   failure — no notification on success (avoids notification spam on every restart).

3. **`elapsed=$(( elapsed + POLL_INTERVAL ))`** — uses command substitution arithmetic.
   Do NOT change to `(( elapsed += ... ))` — that form returns exit code 1 when the
   result is 0, which triggers `set -e` and kills the subshell silently.

4. **Token in plist** — launchd `EnvironmentVariables` requires the literal token value
   at load time. The plist is `chmod 600`. The source token file is also `chmod 600`.
   Neither is committed to git.

5. **`ThrottleInterval: 10`** — prevents rapid crash-loop restarts if copilot-api fails
   immediately (e.g. expired token). Gives 10s between restart attempts.

6. **`COPILOT_BIN` env override** — both `install.sh` and `scripts/copilot-api-start`
   respect `${COPILOT_BIN:-/usr/local/bin/copilot-api}` for non-standard npm prefix paths.

## Token Lifecycle

Tokens are GitHub OAuth device tokens (`ghu_...`) obtained via:
```bash
copilot-api auth
```
They expire periodically. Symptom: `ERROR Failed to get Copilot token` in stderr log.

**Fix:**
```bash
copilot-api auth          # Follow device flow, enter code at github.com/login/device
./install.sh --force      # Updates token file + plist, reloads LaunchAgent
```

## Claude Code Integration

`~/.claude/settings.json` must contain:
```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:4141",
    "ANTHROPIC_AUTH_TOKEN": "sk-dummy"
  }
}
```
`sk-dummy` is intentional — copilot-api uses the GitHub Copilot token, not Anthropic's.

## install.sh Flags Reference

| Flag | Effect |
|------|--------|
| *(none)* | Install: prompt for token, write all files, load LaunchAgent |
| `--dry-run` | Preflight checks + print planned actions — no writes, exits 0 on pass |
| `--force` | Overwrite token even if token file already exists |
| `--uninstall` | Unload LaunchAgent, remove plist/wrapper/token dir |
| `--uninstall --dry-run` | Preview what uninstall would remove — no writes |
| `--help` | Print usage |

## How to Continue Development

1. Check service: `launchctl list | grep copilot-api`
2. View live logs: `tail -f ~/Library/Logs/copilot-api/stdout.log`
3. Test installer: `cd /path/to/repo && ./install.sh --dry-run`
4. After changing `scripts/copilot-api-start`: `./install.sh --force` to redeploy
5. After changing `install.sh`: test with `--dry-run` and `--help` before deploying

## Quick Reference

| Task | Command |
|------|---------|
| Check service status | `launchctl list \| grep copilot-api` |
| View live logs | `tail -f ~/Library/Logs/copilot-api/stdout.log` |
| Restart service | `launchctl kickstart -k gui/$(id -u)/com.user.copilot-api` |
| Stop service | `launchctl unload ~/Library/LaunchAgents/com.user.copilot-api.plist` |
| Re-authenticate | `copilot-api auth && ./install.sh --force` |
| Dry run | `./install.sh --dry-run` |
| Uninstall | `./install.sh --uninstall` |
| Uninstall dry run | `./install.sh --uninstall --dry-run` |
| Brew tap install | `brew tap oliguo/copilot-api-connect . && brew install copilot-api-connect` |
| Verify API | `curl -s http://localhost:4141/v1/models \| python3 -m json.tool \| head -20` |

## Repository

- GitHub: https://github.com/oliguo/claude-code-copliot-connect
- License: MIT
- Maintainer: oliguo
