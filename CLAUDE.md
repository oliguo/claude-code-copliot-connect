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

7. **Token sanitisation on input** — `install.sh` strips ANSI escape sequences and
   non-printable bytes from the token after `read -s`. Some terminals inject
   `ESC[...` codes on paste which corrupt the token silently. Order matters:
   `sed` (strip ESC sequences) THEN `tr -cd '[:print:]'` (strip non-printables).
   Reversing the order leaves printable remnants of the escape sequence behind.

8. **`--help` uses `[[:space:]]*` not `\?`** — the `sed` pattern to strip leading `#`
   from the header comment block uses `s/^#[[:space:]]*//'`. The `\?` quantifier is
   not valid BRE on macOS BSD sed and causes `#` characters to appear in the output.

Tokens are GitHub OAuth device tokens (`ghu_...`) obtained via:
```bash
copilot-api auth
```
`copilot-api auth` writes the token to `~/.local/share/copilot-api/github_token`.
`install.sh` prompts you to paste it into `~/.config/copilot-api/token`.

They expire periodically. Symptom: `ERROR Failed to get Copilot token` in stderr log.

**Fix:**
```bash
copilot-api auth          # Follow device flow, enter code at github.com/login/device
./install.sh --force      # Updates token file + plist, reloads LaunchAgent
```

### Token Paste Bug (ANSI escape sequences)

**Symptom:** Service crash-loops with `invalid authorization header` in stderr log
immediately after a fresh install or `--force` re-auth.

**Cause:** When pasting into the hidden `read -s` prompt, some terminals inject ANSI
escape sequences (e.g. `ESC[1;2C`, a cursor-forward code) before the pasted text.
This corrupts the saved token: `<ESC>[1;2Cghu_...` instead of `ghu_...`.

**Diagnosis:**
```bash
xxd ~/.config/copilot-api/token | head -1
# Corrupt:  1b5b 313b 3243 6768 755f ...   ← starts with 1b (ESC)
# Clean:    6768 755f ...                   ← starts with 67 68 = "gh"
```

**Fix:** `install.sh` now sanitises the token automatically (sed strips ESC sequences,
tr removes remaining non-printable bytes). If you hit this on an older install:
```bash
cp ~/.local/share/copilot-api/github_token ~/.config/copilot-api/token
chmod 600 ~/.config/copilot-api/token
./install.sh --force   # re-enter token when prompted (will be clean this time)
```

**Key design note:** `install.sh` also warns if the saved token doesn't start with
`ghu_` — the expected prefix for `copilot-api auth` tokens.

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

## Git Log

```
abdd4b3 docs: add full test results and ANSI token corruption troubleshooting
d6734bc docs: update CLAUDE.md with token paste bug and sed findings
f4f0a31 fix: sanitise token input to strip ANSI escape sequences on paste
ef9f090 fix: show --force token prompt in dry-run output
e2908b3 fix: --help sed pattern for macOS BRE compatibility
49d19cb feat: support --uninstall --dry-run combined flag
e8f5b5f docs: add README with full setup guide
eaaf12c docs: add CLAUDE.md session memory file
997af57 feat: add Homebrew formula for local tap install
427dd6f fix: distinct ok/warn sigils, accurate uninstall log messages
4d346ac feat: add install.sh with --dry-run, --uninstall, --force flags
6f0f161 feat: add launchd wrapper script
7f7aae0 chore: scaffold repo with .gitignore and MIT license
```

## Repository

- GitHub: https://github.com/oliguo/claude-code-copliot-connect
- License: MIT
- Maintainer: oliguo
