#!/usr/bin/env bash
# install.sh — Install copilot-api as a macOS LaunchAgent for Claude Code
#
# Usage:
#   ./install.sh              Install (prompts for token if not present)
#   ./install.sh --dry-run    Preview actions + preflight checks, no writes
#   ./install.sh --force      Overwrite existing token file
#   ./install.sh --uninstall  Remove all installed files and unload LaunchAgent
#   ./install.sh --help       Show this help
#
# What it installs:
#   ~/.local/bin/copilot-api-start          launchd wrapper script
#   ~/.config/copilot-api/token             GitHub OAuth token (chmod 600)
#   ~/Library/LaunchAgents/com.user.copilot-api.plist  launchd config (chmod 600)
#   ~/Library/Logs/copilot-api/             log directory
#
# MIT License — https://github.com/oliguo/claude-code-copliot-connect
set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────
LABEL="com.user.copilot-api"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
WRAPPER="$HOME/.local/bin/copilot-api-start"
TOKEN_FILE="$HOME/.config/copilot-api/token"
LOG_DIR="$HOME/Library/Logs/copilot-api"
COPILOT_BIN="${COPILOT_BIN:-/usr/local/bin/copilot-api}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER_SRC="$SCRIPT_DIR/scripts/copilot-api-start"

# ── Flags ────────────────────────────────────────────────────────────────────
DRY_RUN=false
UNINSTALL=false
FORCE=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=true ;;
    --uninstall) UNINSTALL=true ;;
    --force)     FORCE=true ;;
    --help|-h)
      sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo "[install] $*"; }
err()  { echo "[install] ERROR: $*" >&2; }
ok()   { echo "[install] ✓ $*"; }
warn() { echo "[install] ⚠ $*" >&2; }
plan() { echo "[dry-run]   $*"; }

# ── Uninstall ────────────────────────────────────────────────────────────────
if $UNINSTALL; then
  log "Uninstalling ${LABEL} LaunchAgent..."
  launchctl unload "$PLIST" 2>/dev/null && log "LaunchAgent unloaded." || log "LaunchAgent was not loaded."
  [[ -f "$PLIST" ]]   && { rm -f "$PLIST";   log "Removed $PLIST"; }   || log "Not found: $PLIST (skipped)"
  [[ -f "$WRAPPER" ]] && { rm -f "$WRAPPER"; log "Removed $WRAPPER"; } || log "Not found: $WRAPPER (skipped)"
  [[ -d "$(dirname "$TOKEN_FILE")" ]] && { rm -rf "$(dirname "$TOKEN_FILE")"; log "Removed $(dirname "$TOKEN_FILE")"; } || log "Not found: $(dirname "$TOKEN_FILE") (skipped)"
  log "Uninstall complete. Logs remain at $LOG_DIR — remove manually if desired."
  exit 0
fi

# ── Dry-run header ───────────────────────────────────────────────────────────
if $DRY_RUN; then
  echo ""
  echo "=========================================================="
  echo "  DRY RUN - no changes will be made"
  echo "=========================================================="
  echo ""
fi

# ── Preflight checks ─────────────────────────────────────────────────────────
log "Running preflight checks..."
PREFLIGHT_OK=true

if [[ -x "$COPILOT_BIN" ]]; then
  ok "copilot-api found at $COPILOT_BIN"
else
  err "copilot-api not found at $COPILOT_BIN"
  err "  Fix: npm install -g copilot-api"
  PREFLIGHT_OK=false
fi

if command -v osascript > /dev/null 2>&1; then
  ok "osascript found (macOS notifications available)"
else
  err "osascript not found — this installer requires macOS"
  PREFLIGHT_OK=false
fi

if command -v curl > /dev/null 2>&1; then
  ok "curl found"
else
  err "curl not found"
  PREFLIGHT_OK=false
fi

if [[ -f "$WRAPPER_SRC" ]]; then
  ok "scripts/copilot-api-start found"
else
  err "scripts/copilot-api-start not found at $WRAPPER_SRC"
  err "  Are you running install.sh from the repo root?"
  PREFLIGHT_OK=false
fi

if [[ -f "$TOKEN_FILE" ]]; then
  TOKEN_SIZE=$(wc -c < "$TOKEN_FILE" | tr -d ' ')
  TOKEN_PERMS=$(stat -f "%Sp" "$TOKEN_FILE")
  if [[ "$TOKEN_PERMS" == "-rw-------" ]]; then
    ok "Token file exists ($TOKEN_SIZE bytes, chmod 600)"
  else
    warn "Token file exists but has unsafe permissions: $TOKEN_PERMS (should be 600)"
  fi
elif $FORCE; then
  $DRY_RUN && plan "Would prompt for token (--force: overwrites existing)"
else
  warn "No token file — will prompt during install"
  $DRY_RUN && plan "Would run: read -r -s GITHUB_TOKEN"
fi

if [[ -f "$PLIST" ]]; then
  ok "Existing plist found (will be overwritten)"
  $DRY_RUN && plan "Would overwrite: $PLIST (chmod 600)"
else
  $DRY_RUN && plan "Would create: $PLIST (chmod 600)"
fi

# ── Dry-run: planned actions ─────────────────────────────────────────────────
if $DRY_RUN; then
  echo ""
  echo "── Planned actions ────────────────────────────────────────"
  plan "mkdir -p $(dirname "$TOKEN_FILE")"
  plan "mkdir -p $LOG_DIR"
  plan "mkdir -p $(dirname "$WRAPPER")"
  plan "cp scripts/copilot-api-start $WRAPPER && chmod 755 $WRAPPER"
  plan "Write plist to $PLIST (chmod 600)"
  plan "plutil -lint $PLIST"
  plan "launchctl unload $PLIST  (if already loaded)"
  plan "launchctl load $PLIST"
  echo ""
  if $PREFLIGHT_OK; then
    echo "PREFLIGHT PASSED - ready to install."
    echo "Run: ./install.sh"
  else
    echo "PREFLIGHT FAILED - fix errors above before installing."
    exit 1
  fi
  exit 0
fi

# ── Abort if preflight failed ─────────────────────────────────────────────────
if ! $PREFLIGHT_OK; then
  echo ""
  err "Preflight checks failed. Fix the errors above and re-run."
  exit 1
fi

# ── Directories ──────────────────────────────────────────────────────────────
log "Creating directories..."
mkdir -p "$(dirname "$TOKEN_FILE")"
mkdir -p "$LOG_DIR"
mkdir -p "$(dirname "$WRAPPER")"

# ── Token ────────────────────────────────────────────────────────────────────
if [[ -f "$TOKEN_FILE" ]] && ! $FORCE; then
  log "Token file already exists — skipping prompt. Use --force to overwrite."
else
  log "Enter your GitHub token from 'copilot-api auth' (input hidden):"
  read -r -s GITHUB_TOKEN
  echo
  [[ -z "$GITHUB_TOKEN" ]] && { err "Token cannot be empty."; exit 1; }
  printf '%s' "$GITHUB_TOKEN" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  unset GITHUB_TOKEN
  log "Token saved (chmod 600)."
fi

GITHUB_TOKEN_VALUE=$(cat "$TOKEN_FILE")

# ── Wrapper script ───────────────────────────────────────────────────────────
log "Installing wrapper script to $WRAPPER..."
cp "$WRAPPER_SRC" "$WRAPPER"
chmod 755 "$WRAPPER"
log "Wrapper installed."

# ── Plist ────────────────────────────────────────────────────────────────────
log "Writing LaunchAgent plist..."
cat > "$PLIST" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>${WRAPPER}</string>
  </array>

  <key>EnvironmentVariables</key>
  <dict>
    <key>GITHUB_PERSONAL_ACCESS_TOKEN</key>
    <string>${GITHUB_TOKEN_VALUE}</string>
    <key>PATH</key>
    <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <true/>

  <key>ThrottleInterval</key>
  <integer>10</integer>

  <key>StandardOutPath</key>
  <string>${LOG_DIR}/stdout.log</string>

  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/stderr.log</string>
</dict>
</plist>
PLIST_EOF

chmod 600 "$PLIST"
unset GITHUB_TOKEN_VALUE
plutil -lint "$PLIST" || { err "Plist validation failed."; exit 1; }
log "Plist written (chmod 600)."

# ── Load LaunchAgent ─────────────────────────────────────────────────────────
log "Loading LaunchAgent..."
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
log "LaunchAgent loaded."

# ── Verify ───────────────────────────────────────────────────────────────────
sleep 3
if launchctl list | grep -q "$LABEL"; then
  log "SUCCESS: $LABEL is running."
else
  log "LaunchAgent loaded — will appear in launchctl list once started."
fi

# ── Quick reference ───────────────────────────────────────────────────────────
echo ""
echo "==================================================="
echo "  copilot-api LaunchAgent installed successfully"
echo "==================================================="
echo "  Logs:      tail -f $LOG_DIR/stdout.log"
echo "  Status:    launchctl list | grep $LABEL"
echo "  Restart:   launchctl kickstart -k gui/\$(id -u)/$LABEL"
echo "  Stop:      launchctl unload $PLIST"
echo "  Uninstall: ./install.sh --uninstall"
echo "  Re-auth:   copilot-api auth && ./install.sh --force"
echo "==================================================="
