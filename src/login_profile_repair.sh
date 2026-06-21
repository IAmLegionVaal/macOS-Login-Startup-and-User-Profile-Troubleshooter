#!/bin/bash
set -u

DO_REPAIR=false
DRY_RUN=false
ASSUME_YES=false
RESET_PERMISSIONS=false
REBUILD_LAUNCHSERVICES=false
DISABLE_AGENT=""
OUTPUT_DIR=""
FAILURES=0
ACTIONS=0

usage() {
  cat <<'EOF'
Usage: login_profile_repair.sh [options]

  --repair                    Restart user-profile and login-item helper services.
  --reset-user-permissions    Run diskutil resetUserPermissions for the target user.
  --rebuild-launchservices    Rebuild Launch Services application registration.
  --disable-agent PATH        Back up and disable one user LaunchAgent plist.
  --dry-run                   Show actions without changing the Mac.
  --yes                       Skip confirmation prompts.
  --output DIR                Save logs, backup and verification output in DIR.
  -h, --help                  Show help.

The target user is SUDO_USER when available, otherwise the current user.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repair) DO_REPAIR=true; shift ;;
    --reset-user-permissions) RESET_PERMISSIONS=true; DO_REPAIR=true; shift ;;
    --rebuild-launchservices) REBUILD_LAUNCHSERVICES=true; DO_REPAIR=true; shift ;;
    --disable-agent) DISABLE_AGENT="${2:-}"; DO_REPAIR=true; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || { echo "This tool must run on macOS." >&2; exit 1; }

TARGET_USER="${SUDO_USER:-$(id -un)}"
if [ "$TARGET_USER" = "root" ]; then
  CONSOLE_USER=$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || true)
  [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ] || TARGET_USER="$CONSOLE_USER"
fi
TARGET_UID=$(id -u "$TARGET_USER" 2>/dev/null) || { echo "Target user not found: $TARGET_USER" >&2; exit 2; }
TARGET_HOME=$(/usr/bin/dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
[ -n "$TARGET_HOME" ] || TARGET_HOME=$(eval echo "~$TARGET_USER")

if [ -n "$DISABLE_AGENT" ]; then
  case "$DISABLE_AGENT" in
    "$TARGET_HOME/Library/LaunchAgents/"*.plist) : ;;
    *) echo "--disable-agent must point to a plist in $TARGET_HOME/Library/LaunchAgents" >&2; exit 2 ;;
  esac
  [ -f "$DISABLE_AGENT" ] || { echo "LaunchAgent not found: $DISABLE_AGENT" >&2; exit 2; }
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${OUTPUT_DIR:-./login-profile-repair-$STAMP}"
BACKUP_DIR="$OUTPUT_DIR/backup"
mkdir -p "$OUTPUT_DIR" "$BACKUP_DIR"
LOG="$OUTPUT_DIR/repair.log"
VERIFY="$OUTPUT_DIR/verification.txt"
: > "$LOG"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
confirm() {
  $ASSUME_YES && return 0
  printf '%s [y/N]: ' "$1"
  read -r answer
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
run_action() {
  description="$1"; shift
  ACTIONS=$((ACTIONS + 1)); log "$description"
  if $DRY_RUN; then
    printf 'DRY-RUN:' >> "$LOG"; for arg in "$@"; do printf ' %q' "$arg" >> "$LOG"; done; printf '\n' >> "$LOG"; return 0
  fi
  if "$@" >> "$LOG" 2>&1; then log "SUCCESS: $description"; return 0; fi
  FAILURES=$((FAILURES + 1)); log "WARNING: $description failed"; return 1
}
run_admin() {
  description="$1"; shift
  if [ "$(id -u)" -eq 0 ]; then run_action "$description" "$@"; else run_action "$description" /usr/bin/sudo "$@"; fi
}
run_as_target() {
  description="$1"; shift
  if [ "$(id -un)" = "$TARGET_USER" ]; then run_action "$description" "$@"; else run_admin "$description" /usr/bin/sudo -u "$TARGET_USER" "$@"; fi
}
verify() {
  {
    echo "Collected: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Target user: $TARGET_USER ($TARGET_UID)"
    echo "Target home: $TARGET_HOME"
    echo
    echo "Home folder:"
    /bin/ls -ldeO "$TARGET_HOME" 2>&1 || true
    /usr/bin/du -sh "$TARGET_HOME/Library/Caches" "$TARGET_HOME/Library/Preferences" 2>/dev/null || true
    echo
    echo "User LaunchAgents:"
    find "$TARGET_HOME/Library/LaunchAgents" -maxdepth 1 -type f -name '*.plist' -print 2>/dev/null | sort || true
    echo
    echo "Profile helper processes:"
    ps -Ao pid,user,etime,comm,args | grep -Ei 'cfprefsd|sharedfilelistd|backgroundtaskmanagementagent|loginwindow|Dock' | grep -v grep || true
    echo
    echo "Background task management state:"
    /usr/bin/sfltool dumpbtm 2>/dev/null | head -n 300 || true
  } > "$VERIFY" 2>&1
}

verify
if ! $DO_REPAIR; then log "Verification-only mode completed. Use --repair to apply repairs."; exit 0; fi
if ! confirm "Apply login, startup and user-profile repairs for $TARGET_USER?"; then log "Repair cancelled by user."; exit 0; fi

for process_name in cfprefsd sharedfilelistd backgroundtaskmanagementagent Dock; do
  if pgrep -u "$TARGET_UID" -x "$process_name" >/dev/null 2>&1; then
    if [ "$(id -u)" -eq "$TARGET_UID" ]; then
      run_action "Restarting $process_name for $TARGET_USER" /usr/bin/killall "$process_name" || true
    else
      run_admin "Restarting $process_name for $TARGET_USER" /usr/bin/killall -u "$TARGET_USER" "$process_name" || true
    fi
  fi
done

if $RESET_PERMISSIONS; then
  if confirm "Reset standard home-folder permissions for $TARGET_USER using diskutil?"; then
    run_admin "Resetting user permissions for UID $TARGET_UID" /usr/sbin/diskutil resetUserPermissions / "$TARGET_UID" || true
  fi
fi

if $REBUILD_LAUNCHSERVICES; then
  LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  if [ -x "$LSREGISTER" ] && confirm "Rebuild Launch Services registration for $TARGET_USER?"; then
    run_as_target "Rebuilding Launch Services registration" "$LSREGISTER" -kill -r -domain local -domain system -domain user || true
    if [ "$(id -u)" -eq "$TARGET_UID" ]; then run_action "Restarting Dock after Launch Services rebuild" /usr/bin/killall Dock || true; fi
  fi
fi

if [ -n "$DISABLE_AGENT" ]; then
  if /usr/bin/plutil -lint "$DISABLE_AGENT" >> "$LOG" 2>&1; then
    if confirm "Back up and disable $DISABLE_AGENT?"; then
      AGENT_NAME=$(basename "$DISABLE_AGENT")
      run_as_target "Unloading user LaunchAgent $AGENT_NAME" /bin/launchctl bootout "gui/$TARGET_UID" "$DISABLE_AGENT" || true
      run_action "Backing up and disabling $AGENT_NAME" /bin/mv "$DISABLE_AGENT" "$BACKUP_DIR/$AGENT_NAME" || true
    fi
  else
    FAILURES=$((FAILURES + 1)); log "WARNING: LaunchAgent plist failed validation and was not changed."
  fi
fi

if ! $DRY_RUN; then sleep 5; fi
verify

if [ "$FAILURES" -gt 0 ]; then log "Repair completed with $FAILURES warning(s). Backup: $BACKUP_DIR"; exit 1; fi
log "Repair completed successfully. Actions performed: $ACTIONS. Backup: $BACKUP_DIR"
exit 0
