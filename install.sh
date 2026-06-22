#!/usr/bin/env bash
#
# install.sh — interactive installer for meow-claude-code.
#
# Installs meow.sh into the user Application Support folder, optionally adds a
# `meow` command to your PATH, and optionally schedules the daily MEOW. Every
# step asks for permission first; pass --yes to accept all defaults.
#
# Usage:
#   ./install.sh             # interactive install (asks before each step)
#   ./install.sh --yes       # non-interactive install (accept defaults, time 07:00)
#   ./install.sh --uninstall # interactive removal (asks before each step)
#   ./install.sh --help

set -euo pipefail

LAUNCHD_LABEL="com.meow-claude-code"
APP_SUPPORT_DIR="$HOME/Library/Application Support/meow-claude-code"
DEST="$APP_SUPPORT_DIR/meow.sh"
PLIST="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"
BIN_DIR="$HOME/.local/bin"
LINK="$BIN_DIR/meow"
DEFAULT_TIME="07:00"

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/meow.sh"
ASSUME_YES=0
MODE=install

usage() {
  cat <<EOF
install.sh — install or remove meow-claude-code for the current user.

Install steps (each asks permission first):
  1. Copy meow.sh -> $APP_SUPPORT_DIR
  2. Link a 'meow' command -> $LINK
  3. Start the daily MEOW (launchd, default $DEFAULT_TIME)

Usage:
  ./install.sh             Interactive install
  ./install.sh --yes       Accept all defaults, no prompts (time $DEFAULT_TIME)
  ./install.sh --uninstall Interactive removal (schedule, command, files)
  -h, --help               Show this help
EOF
}

# Yes/no prompt, defaulting to Yes. Honors --yes (always Yes). Reads from the
# terminal so it still works if stdin is piped.
confirm() {
  local reply
  if [ "$ASSUME_YES" = "1" ]; then return 0; fi
  read -r -p "$1 [Y/n] " reply </dev/tty || reply=""
  case "$reply" in
    [nN] | [nN][oO]) return 1 ;;
    *) return 0 ;;
  esac
}

do_install() {
  if [ ! -f "$SRC" ]; then
    echo "install: cannot find meow.sh next to this script ($SRC)." >&2
    exit 1
  fi

  echo "meow-claude-code installer"
  echo "  source: $SRC"
  echo

  # 1. Install into Application Support (required for the rest).
  if ! confirm "Install meow.sh to $APP_SUPPORT_DIR ?"; then
    echo "Nothing installed. Bye! 🐾"
    exit 0
  fi
  mkdir -p "$APP_SUPPORT_DIR"
  cp "$SRC" "$DEST"
  chmod +x "$DEST"
  echo "  ✓ installed: $DEST"
  echo

  # 2. Optionally expose a `meow` command on PATH.
  local run="$DEST"
  if confirm "Add a 'meow' command to $BIN_DIR (on your PATH)?"; then
    mkdir -p "$BIN_DIR"
    ln -sf "$DEST" "$LINK"
    echo "  ✓ linked: $LINK -> $DEST"
    case ":$PATH:" in
      *":$BIN_DIR:"*) echo "    you can now run: meow"; run="meow" ;;
      *) echo "    note: $BIN_DIR is not on your PATH — add this to your shell profile:"
         echo "          export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
    esac
  fi
  echo

  # 3. Optionally start the daily MEOW (delegates to meow.sh).
  if confirm "Start the daily MEOW now?"; then
    local time="$DEFAULT_TIME"
    if [ "$ASSUME_YES" != "1" ]; then
      read -r -p "  Time to run daily (HH:MM) [$DEFAULT_TIME]: " time </dev/tty || time=""
      time="${time:-$DEFAULT_TIME}"
    fi
    "$DEST" --start "$time"
  else
    echo "  Skipped. Start later with:  $run --start"
  fi

  echo
  echo "Done! 🐾  Try it now:  $run"
}

do_uninstall() {
  echo "meow-claude-code uninstaller"
  echo

  # 1. Stop the daily schedule.
  if [ -f "$PLIST" ]; then
    if confirm "Stop the daily MEOW schedule?"; then
      launchctl bootout "gui/$(id -u)/$LAUNCHD_LABEL" 2>/dev/null || true
      rm -f "$PLIST"
      echo "  ✓ schedule removed"
    fi
  else
    echo "  (no daily MEOW schedule found)"
  fi
  echo

  # 2. Remove the `meow` command.
  if [ -L "$LINK" ] || [ -e "$LINK" ]; then
    if confirm "Remove the 'meow' command ($LINK)?"; then
      rm -f "$LINK"
      echo "  ✓ 'meow' command removed"
    fi
  else
    echo "  (no 'meow' command found)"
  fi
  echo

  # 3. Remove the installed files.
  if [ -d "$APP_SUPPORT_DIR" ]; then
    if confirm "Remove the installed files ($APP_SUPPORT_DIR)?"; then
      rm -rf "$APP_SUPPORT_DIR"
      echo "  ✓ installed files removed"
    fi
  else
    echo "  (no installed files found)"
  fi

  echo
  echo "Uninstall complete. The log at ~/.meow-claude.log was left untouched. 🐾"
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    -y | --yes)  ASSUME_YES=1 ;;
    --uninstall) MODE=uninstall ;;
    *) echo "install: unknown option '$1'" >&2; echo >&2; usage >&2; exit 1 ;;
  esac
  shift
done

if [ "$(uname)" != "Darwin" ]; then
  echo "install: this helper targets macOS (Application Support + launchd)." >&2
  echo "         On Linux, run ./meow.sh --install-cron instead." >&2
  exit 1
fi

if [ "$MODE" = "uninstall" ]; then
  do_uninstall
else
  do_install
fi
