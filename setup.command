#!/bin/sh
# ============================================================================
# dsh-boot-suite - macOS double-click entry: interactive setup menu
#
# Why a .command: Finder does not execute .sh files on double-click, but it
# does open .command files in Terminal. This file only exists to locate the
# repo root and hand over to the real script (tools/macos/setup.sh).
#
# ASCII-only on purpose: the first entry point a user double-clicks must never
# depend on terminal encoding. All Chinese user-facing text lives in setup.sh.
# ============================================================================

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P) || exit 1
# The repo root IS this script's directory; cd there so relative paths behave
# the same no matter where Finder/terminal started us.
cd "$SCRIPT_DIR" || exit 1

if [ ! -f "$SCRIPT_DIR/tools/macos/setup.sh" ]; then
  printf '[x] tools/macos/setup.sh not found in: %s\n' "$SCRIPT_DIR" >&2
  printf '    The package looks incomplete; please re-download the release.\n' >&2
  if [ -t 0 ]; then
    printf '\nPress Enter to close this window...'
    read -r _ || true
  fi
  exit 1
fi

exec sh "$SCRIPT_DIR/tools/macos/setup.sh" "$@"
