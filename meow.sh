#!/usr/bin/env bash
#
# meow.sh — send a tiny "MEOW" to Claude Code (haiku model) to kick-start the
# rolling usage window at a predictable time each day.
#
# Claude Pro/Max usage limits run on a rolling ~5h window that starts at your
# FIRST prompt. Firing a cheap message every 5 hours from a time you choose
# (default 07:00) keeps a fresh window open through the day.
#
# Usage:
#   ./meow.sh                         # print cat art + send MEOW now (haiku), log result
#   ./meow.sh --status                # show install/schedule/last-run status
#   ./meow.sh --start [HH:MM]         # macOS: MEOW every 5h from HH:MM (default 07:00)
#   ./meow.sh --stop                  # macOS: stop the MEOW schedule
#   ./meow.sh --install-cron [HH:MM]  # (Linux) same, via cron
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
PLIST="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"
DEFAULT_TIME="07:00"
# Claude's usage window is ~5h, so we re-MEOW every 5h to keep a fresh window
# open through the day (anchored to the chosen start time).
INTERVAL_HOURS=5

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

# Validate HH:MM (24-hour). On success echo "HOUR MINUTE" with leading zeros
# stripped; on bad input print an error and return 1.
parse_time() {
  if [[ ! "$1" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    echo "meow: invalid time '$1' (expected HH:MM, 24-hour, e.g. 07:00 or 09:30)." >&2
    return 1
  fi
  # 10# forces base-10 so 08/09 don't read as octal.
  printf '%d %d\n' "$((10#${1%%:*}))" "$((10#${1##*:}))"
}

# Echo the per-day run hours (space-separated) starting at hour $1 and repeating
# every INTERVAL_HOURS, wrapping within a 24h day. e.g. 7 -> "7 12 17 22 3".
run_hours() {
  local start="$1" k=0 out=""
  while [ "$k" -lt 24 ]; do
    out="$out $(( (start + k) % 24 ))"
    k=$(( k + INTERVAL_HOURS ))
  done
  printf '%s\n' "${out# }"
}

# Format the run times as a sorted "HH:MM HH:MM ..." string for a given hour
# list ($1, space-separated) and minute ($2).
run_times() {
  local h
  for h in $1; do printf '%02d:%02d\n' "$h" "$2"; done | sort | paste -sd' ' -
}

# Replace any existing meow cron line, then add an entry that fires every
# INTERVAL_HOURS from HH:MM (cron supports a comma-separated hour list).
install_cron() {
  local time="${1:-$DEFAULT_TIME}" hm hour min target hours hourlist cron_line
  hm="$(parse_time "$time")" || return 1
  hour="${hm%% *}"; min="${hm##* }"

  target="$(scheduler_target)"
  hours="$(run_hours "$hour")"
  hourlist="$(printf '%s' "$hours" | tr ' ' ',')"
  # stdout (art + reply) -> /dev/null; the script self-logs a structured line.
  # Keep stderr in the log so unexpected failures are still captured.
  cron_line="$min $hourlist * * * \"$target\" >/dev/null 2>>\"$LOG\" $CRON_MARKER"

  # Keep all non-meow lines, then append our (single) line. `|| true` tolerates
  # an empty/absent crontab where grep would otherwise exit non-zero.
  {
    crontab -l 2>/dev/null | grep -vF "$CRON_MARKER" || true
    printf '%s\n' "$cron_line"
  } | crontab -

  printf 'meow: MEOW scheduled every %dh from %02d:%02d via cron.\n' "$INTERVAL_HOURS" "$hour" "$min"
  echo "      times:  $(run_times "$hours" "$min")"
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

# macOS: install a LaunchAgent that fires every INTERVAL_HOURS from HH:MM. Runs
# in the user's login session, so it can reach the keychain (unlike plain cron).
install_launchd() {
  local time="${1:-$DEFAULT_TIME}" hm hour min uid target hours entries h

  if [ "$(uname)" != "Darwin" ]; then
    echo "meow: --start is macOS-only; use --install-cron instead." >&2
    return 1
  fi
  hm="$(parse_time "$time")" || return 1
  hour="${hm%% *}"; min="${hm##* }"
  uid="$(id -u)"
  target="$(scheduler_target)"

  # One <dict> per run time — launchd fires the job at each.
  hours="$(run_hours "$hour")"
  entries=""
  for h in $hours; do
    entries="$entries
        <dict>
            <key>Hour</key>
            <integer>$h</integer>
            <key>Minute</key>
            <integer>$min</integer>
        </dict>"
  done

  mkdir -p "$(dirname "$PLIST")"
  cat >"$PLIST" <<PLIST_XML
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
    <array>$entries
    </array>
    <key>StandardOutPath</key>
    <string>/dev/null</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
PLIST_XML

  # Reload: remove any prior copy, then bootstrap the fresh plist.
  launchctl bootout "gui/$uid/$LAUNCHD_LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$uid" "$PLIST"

  printf 'meow: MEOW started — every %dh from %02d:%02d.\n' "$INTERVAL_HOURS" "$hour" "$min"
  echo "      times:  $(run_times "$hours" "$min")"
  echo "      plist:  $PLIST"
  echo "      runs:   $target"
  echo "      (run 'meow --stop' to stop it)"
}

uninstall_launchd() {
  local uid
  uid="$(id -u)"

  if [ ! -f "$PLIST" ]; then
    echo "meow: no MEOW schedule running; nothing to stop."
    return 0
  fi
  launchctl bootout "gui/$uid/$LAUNCHD_LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "meow: MEOW schedule stopped."
  # Note: the installed copy in Application Support is left in place; use
  # './install.sh --uninstall' to remove the installed files and 'meow' command.
}

# Report the current state: CLI, install, PATH command, schedules, last run.
status() {
  local uid link line claude_path
  uid="$(id -u)"
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

  # launchd schedule (macOS) — parse the run times back out of the plist.
  if [ "$(uname)" = "Darwin" ]; then
    if [ -f "$PLIST" ]; then
      local times loaded
      times="$(plutil -p "$PLIST" 2>/dev/null | awk '/"Hour" =>/{h=$NF} /"Minute" =>/{printf "%02d:%02d\n", h, $NF}' | sort | paste -sd' ' -)"
      if launchctl print "gui/$uid/$LAUNCHD_LABEL" >/dev/null 2>&1; then loaded="active"; else loaded="inactive"; fi
      if [ -n "$times" ]; then
        echo "  schedule       ✓  every ${INTERVAL_HOURS}h: $times ($loaded)"
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
    echo "  cron           ✓  every ${INTERVAL_HOURS}h (min $cm, hours $ch)"
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
meow.sh — MEOW ping (every few hours) to keep your Claude usage window fresh.

Usage:
  ./meow.sh                         Send MEOW now (haiku) and print the art
  ./meow.sh --status                Show status (install, schedule, last run)
  ./meow.sh --start [HH:MM]         MEOW every ${INTERVAL_HOURS}h from HH:MM (macOS, default $DEFAULT_TIME)
  ./meow.sh --stop                  Stop the MEOW schedule (macOS)
  ./meow.sh --install-cron [HH:MM]  Same via cron instead (Linux)
  ./meow.sh --uninstall-cron        Remove the cron job
  -h, --help                        Show this help

Claude's usage window is ~${INTERVAL_HOURS}h, so --start re-MEOWs every
${INTERVAL_HOURS}h from your chosen time to keep a fresh window open. On macOS it
uses launchd (reaches your login keychain; cron often can't). Log file: $LOG
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
