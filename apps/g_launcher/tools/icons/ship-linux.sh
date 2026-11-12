#!/bin/bash
#
# THE FREE LINUX ICON THEMES: PAPIRUS TOPPED UP, NUMIX CIRCLE ADDED.
#
#   ./tools/icons/ship-linux.sh
#   ./tools/icons/ship-linux.sh --dry-run
#
# Both are desktop icon themes under GPL-3.0. They ship FREE, never sold: the
# licence lets anyone who receives them pass them on, so a price would buy
# nothing. Each pack.json carries its licence and source link, and the
# Licences screen carries both.
#
# Papirus keeps every icon the live version maps (`--merge-live`), so art that
# was picked by eye in the panel survives, and gains the alias table and the
# drawing-name match on top.
#
# Python comes from tools/icons/py.sh, which makes its own venv on first run.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SRC="$ROOT/../../iconlab/sources"
OUT="$HERE/out"
DRY=""
PAPIRUS_LIVE="${PAPIRUS_LIVE:-heropacks/papirus-icon-theme/12}"

die() { printf '\nship-linux: %s\n\n' "$1" >&2; exit 1; }
step() { printf '\n\033[1m── %s ──\033[0m\n' "$1"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY="--dry-run"; shift;;
    *)         die "unknown flag $1";;
  esac
done

cd "$ROOT"

step "1. Papirus"
bash "$HERE/py.sh" "$HERE/build-linux-hero.py" --all \
  --theme "$SRC/papirus-icon-theme-master/papirus-icon-theme-master/Papirus/64x64/apps" \
  --id papirus-icon-theme --name "Papirus Icon Theme" --license GPL-3.0 \
  --attribution "Papirus by the Papirus Development Team, GPL-3.0. Source: https://github.com/PapirusDevelopmentTeam/papirus-icon-theme" \
  --merge-live "$PAPIRUS_LIVE"

step "2. Numix Circle"
bash "$HERE/py.sh" "$HERE/build-linux-hero.py" --all \
  --theme "$SRC/numix-icon-theme-circle-master/Numix-Circle/48/apps" \
  --id numix-circle --name "Numix Circle" --license GPL-3.0 \
  --attribution "Numix Circle by the Numix Project, GPL-3.0. Source: https://github.com/numixproject/numix-icon-theme-circle"

step "3. publish"
VERSION="$(date +%s)"
for id in papirus-icon-theme numix-circle; do
  printf '   %s ' "$id"
  "$HERE/publish-pack.sh" "$OUT/$id" --type hero --version "$VERSION" --min-app 8 $DRY >/dev/null
  printf 'ok\n'
done

if [ -n "$DRY" ]; then
  printf '\ndry run. Nothing was uploaded.\n\n'
else
  printf '\n\033[1mdone.\033[0m\n\n'
fi
