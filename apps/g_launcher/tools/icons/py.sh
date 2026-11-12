#!/bin/bash
#
# Python for the icon tools, in a private venv under tools/icons/.venv, so the
# system or Homebrew Python is never touched (macOS refuses a global pip
# install with "externally-managed-environment").
#
#   bash tools/icons/py.sh tools/icons/render-previews.py ...
#
# First run creates the venv and installs cairosvg and Pillow. cairosvg draws
# through the cairo C library, which comes from `brew install cairo` on macOS.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VENV="$HERE/.venv"

if [ "$(uname)" = "Darwin" ]; then
  command -v brew >/dev/null 2>&1 || { echo 'py.sh: Homebrew is needed for cairo' >&2; exit 1; }
  brew list cairo >/dev/null 2>&1 || brew install cairo
  # cairocffi looks the library up through dyld, which does not search
  # Homebrew's prefix on Apple silicon unless told to.
  export DYLD_FALLBACK_LIBRARY_PATH="$(brew --prefix)/lib${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
fi

if [ ! -x "$VENV/bin/python3" ]; then
  python3 -m venv "$VENV"
  "$VENV/bin/python3" -m pip install -q --upgrade pip
fi
"$VENV/bin/python3" -c 'import cairosvg, PIL' 2>/dev/null \
  || "$VENV/bin/python3" -m pip install -q cairosvg pillow

exec "$VENV/bin/python3" "$@"
