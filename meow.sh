#!/usr/bin/env bash
#
# meow.sh — send a tiny "MEOW" to Claude Code (haiku model) to kick-start the
# rolling usage window at a predictable time each day.
#
# Claude Pro/Max usage limits run on a rolling ~5h window that starts at your
# FIRST prompt. Firing one cheap message every morning anchors that window to a
# time you choose (default 07:00) instead of whenever you happen to start.
#
# Usage:
#   ./meow.sh                         # print cat art + send MEOW now (haiku), log result
#   ./meow.sh --status                # show install/schedule/last-run status
#   ./meow.sh --start [HH:MM]         # macOS: start the daily MEOW (default 07:00)
#   ./meow.sh --stop                  # macOS: stop the daily MEOW
#   ./meow.sh --install-cron [HH:MM]  # (Linux) schedule a daily MEOW via cron
#   ./meow.sh --uninstall-cron        # remove the cron job
#   ./meow.sh --help
#
# Scheduling on macOS: prefer launchd. A LaunchAgent runs inside your logged-in
# user session, so it can read auth from the login keychain. Plain cron jobs run
# outside that session and often CAN'T reach the keychain, so a scheduled MEOW
# may fail with "Not logged in". Either way, results are recorded in the log
# below — check it if a scheduled run doesn't seem to fire.

set -euo pipefail

PROMPT="MEOW"
MODEL="haiku"
LOG="$HOME/.meow-claude.log"
CRON_MARKER="# meow-claude-code"
LAUNCHD_LABEL="com.meow-claude-code"
APP_SUPPORT_DIR="$HOME/Library/Application Support/meow-claude-code"
DEFAULT_TIME="07:00"

# Absolute path to this script (needed so a scheduler can find it).
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

# ---------------------------------------------------------------------------

# Locate the claude binary. cron has a minimal PATH, so fall back to the
# default install location if it isn't on PATH.
resolve_claude() {
  if command -v claude >/dev/null 2>&1; then
    command -v claude
  elif [ -x "$HOME/.local/bin/claude" ]; then
    printf '%s\n' "$HOME/.local/bin/claude"
  else
    echo "meow: could not find the 'claude' CLI on PATH or in ~/.local/bin." >&2
    echo "      Install Claude Code, or add it to your PATH." >&2
    return 1
  fi
}

# Return the path a scheduler should execute. On macOS, copy this script into
# Application Support first: schedulers (cron/launchd) can't read TCC-protected
# folders like ~/Documents, ~/Desktop or ~/Downloads, and would fail with
# "Operation not permitted". The copy also keeps the scheduled job working if
# the repo is later moved. (No copy needed on Linux.) Re-run an installer after
# editing this script to refresh the copy.
scheduler_target() {
  if [ "$(uname)" = "Darwin" ]; then
    local dest="$APP_SUPPORT_DIR/meow.sh"
    mkdir -p "$APP_SUPPORT_DIR"
    # Skip the copy when we're already running the installed copy (directly or
    # via the `meow` symlink) — `-ef` matches the same file even through a
    # symlink, avoiding a `cp X X` "are identical" error under `set -e`.
    if ! [ "$SCRIPT_PATH" -ef "$dest" ]; then
      cp "$SCRIPT_PATH" "$dest"
      chmod +x "$dest"
    fi
    printf '%s\n' "$dest"
  else
    printf '%s\n' "$SCRIPT_PATH"
  fi
}

print_art() {
  cat <<'EOF'

███╗   ███╗███████╗ ██████╗ ██╗    ██╗
████╗ ████║██╔════╝██╔═══██╗██║    ██║
██╔████╔██║█████╗  ██║   ██║██║ █╗ ██║
██║╚██╔╝██║██╔══╝  ██║   ██║██║███╗██║
██║ ╚═╝ ██║███████╗╚██████╔╝╚███╔███╔╝
╚═╝     ╚═╝╚══════╝ ╚═════╝  ╚══╝╚══╝

   /\_/\   < meow! >  poking Claude Code awake...
  ( o.o )
   > ^ <
  (")_(")

EOF
}

# Send the MEOW, print the reply, and append a timestamped line to the log.
run_meow() {
  print_art

  local claude reply ts first rc
  claude="$(resolve_claude)"
  ts="$(date '+%Y-%m-%d %H:%M:%S')"

  if reply="$("$claude" -p "$PROMPT" --model "$MODEL" 2>&1)"; then
    printf '%s\n' "$reply"
    first="$(printf '%s' "$reply" | head -n1)"
    printf '[%s] MEOW sent (%s) -> %s\n' "$ts" "$MODEL" "$first" >>"$LOG"
    echo
    echo "meow: logged to $LOG"
  else
    rc=$?
    first="$(printf '%s' "$reply" | head -n1)"
    printf 'meow: MEOW failed (exit %s):\n%s\n' "$rc" "$reply" >&2
    printf '[%s] MEOW FAILED (exit %s) -> %s\n' "$ts" "$rc" "$first" >>"$LOG"
    return "$rc"
  fi
}

# Replace any existing meow cron line, then add a daily entry at HH:MM.
install_cron() {
  local time="${1:-$DEFAULT_TIME}" hour min cron_line

  if [[ ! "$time" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    echo "meow: invalid time '$time' (expected HH:MM, 24-hour, e.g. 07:00 or 09:30)." >&2
    return 1
  fi

  # Strip leading zeros (force base-10 so 08/09 don't read as octal).
  hour=$((10#${time%%:*}))
  min=$((10#${time##*:}))

  local target
  target="$(scheduler_target)"
  # stdout (art + reply) -> /dev/null; the script self-logs a structured line.
  # Keep stderr in the log so unexpected failures are still captured.
  cron_line="$min $hour * * * \"$target\" >/dev/null 2>>\"$LOG\" $CRON_MARKER"

  # Keep all non-meow lines, then append our (single) line. `|| true` tolerates
  # an empty/absent crontab where grep would otherwise exit non-zero.
  {
    crontab -l 2>/dev/null | grep -vF "$CRON_MARKER" || true
    printf '%s\n' "$cron_line"
  } | crontab -

  printf 'meow: daily MEOW scheduled at %02d:%02d.\n' "$hour" "$min"
  echo "      (run './meow.sh --uninstall-cron' to remove it)"
}

uninstall_cron() {
  if ! crontab -l 2>/dev/null | grep -qF "$CRON_MARKER"; then
    echo "meow: no scheduled MEOW found; nothing to remove."
    return 0
  fi
  { crontab -l 2>/dev/null | grep -vF "$CRON_MARKER" || true; } | crontab -
  echo "meow: scheduled MEOW (cron) removed."
}

# macOS: install a LaunchAgent that fires daily at HH:MM. Runs in the user's
# login session, so it can reach the keychain (unlike plain cron).
install_launchd() {
  local time="${1:-$DEFAULT_TIME}" hour min uid plist

  if [ "$(uname)" != "Darwin" ]; then
    echo "meow: --start is macOS-only; use --install-cron instead." >&2
    return 1
  fi
  if [[ ! "$time" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    echo "meow: invalid time '$time' (expected HH:MM, 24-hour, e.g. 07:00 or 09:30)." >&2
    return 1
  fi

  hour=$((10#${time%%:*}))
  min=$((10#${time##*:}))
  uid="$(id -u)"
  plist="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"

  local target
  target="$(scheduler_target)"

  mkdir -p "$(dirname "$plist")"
  cat >"$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LAUNCHD_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$target</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$hour</integer>
        <key>Minute</key>
        <integer>$min</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/dev/null</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
PLIST

  # Reload: remove any prior copy, then bootstrap the fresh plist.
  launchctl bootout "gui/$uid/$LAUNCHD_LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$uid" "$plist"

  printf 'meow: daily MEOW started — runs at %02d:%02d every day.\n' "$hour" "$min"
  echo "      plist:  $plist"
  echo "      runs:   $target"
  echo "      (run 'meow --stop' to stop it)"
}

uninstall_launchd() {
  local uid plist
  uid="$(id -u)"
  plist="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"

  if [ ! -f "$plist" ]; then
    echo "meow: no daily MEOW running; nothing to stop."
    return 0
  fi
  launchctl bootout "gui/$uid/$LAUNCHD_LABEL" 2>/dev/null || true
  rm -f "$plist"
  echo "meow: daily MEOW stopped."
  # Note: the installed copy in Application Support is left in place; use
  # './install.sh --uninstall' to remove the installed files and 'meow' command.
}

# Report the current state: CLI, install, PATH command, schedules, last run.
status() {
  local uid plist link line claude_path
  uid="$(id -u)"
  plist="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"
  link="$HOME/.local/bin/meow"

  echo "meow-claude-code — status"
  echo

  # claude CLI
  if claude_path="$(resolve_claude 2>/dev/null)"; then
    echo "  claude CLI     ✓  $claude_path"
  else
    echo "  claude CLI     ✗  not found (install Claude Code or add it to PATH)"
  fi

  # installed copy
  if [ -f "$APP_SUPPORT_DIR/meow.sh" ]; then
    echo "  installed      ✓  $APP_SUPPORT_DIR/meow.sh"
  else
    echo "  installed      ✗  not installed (run ./install.sh)"
  fi

  # meow command on PATH
  if [ -L "$link" ] || [ -e "$link" ]; then
    if command -v meow >/dev/null 2>&1; then
      echo "  meow command   ✓  $link (on PATH)"
    else
      echo "  meow command   ~  $link (exists, but ~/.local/bin is not on PATH)"
    fi
  else
    echo "  meow command   ✗  not linked"
  fi

  # launchd schedule (macOS)
  if [ "$(uname)" = "Darwin" ]; then
    if [ -f "$plist" ]; then
      local h m loaded
      h="$(/usr/libexec/PlistBuddy -c 'Print :StartCalendarInterval:Hour' "$plist" 2>/dev/null)" || h=""
      m="$(/usr/libexec/PlistBuddy -c 'Print :StartCalendarInterval:Minute' "$plist" 2>/dev/null)" || m=""
      if launchctl print "gui/$uid/$LAUNCHD_LABEL" >/dev/null 2>&1; then loaded="active"; else loaded="inactive"; fi
      if [[ "$h" =~ ^[0-9]+$ && "$m" =~ ^[0-9]+$ ]]; then
        printf '  schedule       ✓  daily at %02d:%02d (%s)\n' "$h" "$m" "$loaded"
      else
        echo "  schedule       ✓  started ($loaded)"
      fi
    else
      echo "  schedule       ✗  not started (run: meow --start)"
    fi
  fi

  # cron schedule
  if line="$(crontab -l 2>/dev/null | grep -F "$CRON_MARKER")" && [ -n "$line" ]; then
    local cm ch
    cm="$(printf '%s' "$line" | awk '{print $1}')"
    ch="$(printf '%s' "$line" | awk '{print $2}')"
    if [[ "$ch" =~ ^[0-9]+$ && "$cm" =~ ^[0-9]+$ ]]; then
      printf '  cron           ✓  daily at %02d:%02d\n' "$ch" "$cm"
    else
      echo "  cron           ✓  scheduled"
    fi
  else
    echo "  cron           -  not scheduled"
  fi

  # last recorded run
  echo
  line="$(grep -E 'MEOW (sent|FAILED)' "$LOG" 2>/dev/null | tail -n1 || true)"
  if [ -n "$line" ]; then
    echo "  last run:  $line"
  else
    echo "  last run:  (none recorded yet)"
  fi
  echo "  log:       $LOG"
}

usage() {
  cat <<EOF
meow.sh — daily MEOW ping to kick-start your Claude usage window.

Usage:
  ./meow.sh                         Send MEOW now (haiku) and print the art
  ./meow.sh --status                Show status (install, schedule, last run)
  ./meow.sh --start [HH:MM]         Start the daily MEOW (macOS, default $DEFAULT_TIME)
  ./meow.sh --stop                  Stop the daily MEOW (macOS)
  ./meow.sh --install-cron [HH:MM]  Schedule via cron instead (Linux)
  ./meow.sh --uninstall-cron        Remove the cron job
  -h, --help                        Show this help

On macOS, --start uses launchd so it can reach your login keychain; cron jobs
often can't and fail to authenticate. Log file: $LOG
EOF
}

main() {
  case "${1:-}" in
    "")               run_meow ;;
    --status|status)  status ;;
    --start|start)    install_launchd "${2:-$DEFAULT_TIME}" ;;
    --stop|stop)      uninstall_launchd ;;
    --install-cron)   install_cron "${2:-$DEFAULT_TIME}" ;;
    --uninstall-cron) uninstall_cron ;;
    -h|--help)        usage ;;
    *)
      echo "meow: unknown option '$1'" >&2
      echo >&2
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
