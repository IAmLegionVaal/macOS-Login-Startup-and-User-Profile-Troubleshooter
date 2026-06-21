#!/bin/bash
set -u

HOURS=24
OUTPUT_DIR=""

usage(){ echo "Usage: login_profile_troubleshooter.sh [--hours N] [--output DIR]"; }
while [ "$#" -gt 0 ]; do case "$1" in --hours) HOURS="${2:-24}"; shift 2;; --output) OUTPUT_DIR="${2:-}"; shift 2;; -h|--help) usage; exit 0;; *) echo "Unknown argument: $1" >&2; exit 2;; esac; done
case "$HOURS" in ''|*[!0-9]*) echo "--hours must be numeric" >&2; exit 2;; esac
[ "$(uname -s)" = Darwin ] || { echo "This tool must run on macOS." >&2; exit 1; }
STAMP=$(date +%Y%m%d_%H%M%S); OUTPUT_DIR="${OUTPUT_DIR:-./login-profile-$STAMP}"; mkdir -p "$OUTPUT_DIR"
REPORT="$OUTPUT_DIR/login-profile-report.txt"; CSV="$OUTPUT_DIR/startup-items.csv"; JSON="$OUTPUT_DIR/summary.json"; ERRORS="$OUTPUT_DIR/command-errors.log"; :>"$REPORT"; :>"$ERRORS"
echo 'path,owner,mode,type' > "$CSV"
section(){ t="$1"; shift; { printf '\n===== %s =====\n' "$t"; "$@"; } >>"$REPORT" 2>>"$ERRORS" || true; }
section "Metadata" /bin/bash -c 'date -u +%Y-%m-%dT%H:%M:%SZ; hostname; sw_vers; id; uptime'
section "Console user" /usr/bin/stat -f '%Su' /dev/console
section "Login history" /usr/bin/last -20
section "Home folder" /bin/bash -c 'ls -ldeO@ "$HOME"; df -h "$HOME"; dscl . -read "/Users/$USER" NFSHomeDirectory UserShell UniqueID PrimaryGroupID 2>/dev/null || true'
section "User storage" /bin/bash -c 'du -sh "$HOME/Library/Caches" "$HOME/Library/Preferences" "$HOME/Library/Saved Application State" 2>/dev/null || true'
section "Background task management" /bin/bash -c 'sfltool dumpbtm 2>/dev/null | head -n 3000 || true'
section "Launch items" /bin/bash -c 'find "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons -maxdepth 1 -type f -name "*.plist" -print -exec ls -l {} \; 2>/dev/null || true'
section "Login and startup processes" /bin/bash -c 'ps -Ao pid,user,etime,comm,args | grep -Ei "loginwindow|backgroundtaskmanagement|sharedfilelistd|runningboardd|launchservicesd" | grep -v grep || true'
section "Boot arguments and safe-mode indicators" /bin/bash -c 'nvram boot-args 2>/dev/null || true; sysctl kern.safeboot 2>/dev/null || true'
section "Recent login and profile events" /bin/bash -c "/usr/bin/log show --last ${HOURS}h --style compact --predicate '(process == \"loginwindow\") OR (process == \"launchservicesd\") OR (process == \"backgroundtaskmanagementagent\") OR (eventMessage CONTAINS[c] \"login item\") OR (eventMessage CONTAINS[c] \"home directory\")' 2>/dev/null | tail -n 4000"

ITEMS=0
REVIEW=0
for dir in "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons; do
  [ -d "$dir" ] || continue
  for file in "$dir"/*.plist; do
    [ -f "$file" ] || continue
    ITEMS=$((ITEMS+1))
    owner=$(stat -f '%Su:%Sg' "$file" 2>/dev/null || echo unknown)
    mode=$(stat -f '%Lp' "$file" 2>/dev/null || echo unknown)
    type=$(basename "$dir")
    status=OK
    /usr/bin/plutil -lint "$file" >/dev/null 2>&1 || { status=INVALID; REVIEW=$((REVIEW+1)); }
    printf '"%s","%s","%s","%s"\n' "$file" "$owner" "$mode" "$type" >> "$CSV"
  done
done
HOME_OWNER=$(stat -f '%Su' "$HOME" 2>/dev/null || echo unknown)
HOME_MODE=$(stat -f '%Lp' "$HOME" 2>/dev/null || echo unknown)
HOME_OK=false; [ "$HOME_OWNER" = "$USER" ] && HOME_OK=true
SAFE_MODE=false; sysctl -n kern.safeboot 2>/dev/null | grep -q '^1$' && SAFE_MODE=true
LOGINWINDOW_RUNNING=false; pgrep -x loginwindow >/dev/null 2>&1 && LOGINWINDOW_RUNNING=true
OVERALL="Healthy"; { ! $HOME_OK || ! $LOGINWINDOW_RUNNING || [ "$REVIEW" -gt 0 ]; } && OVERALL="Attention required"
cat > "$JSON" <<EOF
{"collected_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","hostname":"$(hostname)","user":"$USER","home_owner":"$HOME_OWNER","home_mode":"$HOME_MODE","home_owner_correct":$HOME_OK,"loginwindow_running":$LOGINWINDOW_RUNNING,"safe_mode":$SAFE_MODE,"startup_items":$ITEMS,"invalid_plists":$REVIEW,"overall_status":"$OVERALL"}
EOF
printf '\nLogin and profile diagnostics completed: %s\n' "$OUTPUT_DIR" | tee -a "$REPORT"
