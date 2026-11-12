#!/bin/bash
#
# BOLD: LAWNICONS, REBRANDED, IN EVERY DISTRO COLOUR, ONE COMMAND.
#
#   bash tools/icons/ship-bold.sh
#   ./tools/icons/ship-bold.sh --set <a Lawnicons clone>   default iconlab/sources
#   ./tools/icons/ship-bold.sh --skip-base     reuse out/g-bold as built
#   ./tools/icons/ship-bold.sh --dry-run       build and sign, upload nothing
#
# ─── WHAT IT DOES ────────────────────────────────────────────────────────────
#
#   1. build g-bold from a Lawnicons clone (10,504 drawings, 14,332 apps)
#   2. check the wire contract
#   3. build the fourteen colour packs from distros.json
#   4. render each colour's store preview.png
#   5. publish g-bold, then each colour, all under the ONE sku icons_bold
#
# ─── LICENCE ────────────────────────────────────────────────────────────────
#
# Lawnicons is Apache-2.0: we may rename, recolour and sell it with no
# share-alike. Every pack.json carries the attribution, the Licences screen
# carries the licence text, and the Lawnicons and Lawnchair names are never
# used as our brand.
#
# ─── BEFORE THE FIRST RUN ───────────────────────────────────────────────────
#
# Create the one-time product `icons_bold` in the Play console. Until it exists
# the store shows Bold with a Buy label and no price, and a tap does nothing.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="$HERE/out"
TABLE="$ROOT/../../admin/src/lib/g-launcher/distros.json"

SET="$ROOT/../../iconlab/sources/lawnicons-develop"
SKIP_BASE=0
DRY=""
SKU="icons_bold"
BASE_ID="g-bold"

die() { printf '\nship-bold: %s\n\n' "$1" >&2; exit 1; }
step() { printf '\n\033[1m── %s ──\033[0m\n' "$1"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --set)       SET="$2"; shift 2;;
    --skip-base) SKIP_BASE=1; shift;;
    --dry-run)   DRY="--dry-run"; shift;;
    *)           die "unknown flag $1";;
  esac
done

command -v node >/dev/null 2>&1 || die 'node is not on PATH'
command -v python3 >/dev/null 2>&1 || die 'python3 is not on PATH'
[ -f "$TABLE" ] || die "no distros.json at $TABLE"
cd "$ROOT"

if [ "$SKIP_BASE" = "0" ]; then
  [ -d "$SET" ] || die "no Lawnicons clone at $SET (pass --set)"
  step "1. build $BASE_ID"
  node "$HERE/build-vector-pack.mjs" --source lawnicons --set "$SET" \
    --id "$BASE_ID" --name "Bold" | grep -E "drawings|packages mapped|gzipped|wrote"
else
  step "1. reusing out/$BASE_ID"
  [ -f "$OUT/$BASE_ID/pack.json" ] || die "out/$BASE_ID was never built; drop --skip-base"
fi

step "2. wire contract"
node "$HERE/pack-shape.test.mjs" "$OUT/$BASE_ID/pack.json" | tail -3

step "3. build the fourteen"
node "$HERE/build-official-packs.mjs" --family bold | tail -18

step "4. store previews"
bash "$HERE/py.sh" "$HERE/render-previews.py" "$OUT"/*-bold

step "5. publish"
VERSION="$(date +%s)"
MIN_APP="$(node -e "process.stdout.write(String(require('$TABLE').minAppVersion))")"
printf '   %s ' "$BASE_ID"
"$HERE/publish-pack.sh" "$OUT/$BASE_ID" --version "$VERSION" --sku "$SKU" \
  --min-app "$MIN_APP" $DRY >/dev/null
printf 'ok\n'
for dir in "$OUT"/*-bold; do
  id="$(basename "$dir")"
  [ "$id" = "$BASE_ID" ] && continue
  printf '   %s ' "$id"
  "$HERE/publish-pack.sh" "$dir" --version "$VERSION" --sku "$SKU" \
    --min-app "$MIN_APP" --requires "$BASE_ID" $DRY >/dev/null
  printf 'ok\n'
done

if [ -n "$DRY" ]; then
  printf '\ndry run. Nothing was uploaded.\n\n'
else
  printf '\n\033[1mdone.\033[0m 15 Bold packs live under %s.\n\n' "$SKU"
fi
