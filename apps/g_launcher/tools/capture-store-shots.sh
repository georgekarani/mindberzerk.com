#!/usr/bin/env bash
#
# Capture the three store screenshots for each distro from a connected phone.
#
#   tools/capture-store-shots.sh                 every distro
#   tools/capture-store-shots.sh kali-2024 pocket    only these
#
# Per distro it writes, under themes/g-launcher/store-shots/:
#   <distro>/shot_home.webp, shot_drawer.webp, shot_settings.webp
#       1080 wide, named for the three slots in the admin distro builder
#   _raw/<distro>/*.png
#       full-size originals, the source for the Play listing slides
#
# The launcher has no adb hook for switching distros, so the script waits
# while each screen is put up by hand, then captures it.
set -euo pipefail

DISTROS=(
  ubuntu-24-04 kde-plasma-6 terminal
  kali-2024 garuda-dr460nized pop-os-2204
  arch-linux deepin-23 elementary-os-8 endeavouros fedora-40
  linux-mint-22 manjaro-kde pocket zorin-os-17
)
SLOTS=(home drawer settings)
PROMPTS=(
  "the home screen"
  "the app drawer"
  "the launcher's Settings"
)

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(cd "$HERE/../../.." && pwd)/themes/g-launcher/store-shots"

command -v adb >/dev/null || { echo "adb is not on PATH" >&2; exit 1; }
if [ "$(adb devices | awk 'NR > 1 && $2 == "device"' | wc -l | tr -d ' ')" != "1" ]; then
  echo "Connect exactly one phone with USB debugging on" >&2
  exit 1
fi

[ "$#" -gt 0 ] && DISTROS=("$@")

demo() { adb shell am broadcast -a com.android.systemui.demo "$@" >/dev/null; }

# A fixed, anonymous status bar: 9:00, full battery, Wi-Fi only, no carrier
# name, no notification icons. Identical across every distro's shots.
demo_on() {
  adb shell settings put global sysui_demo_allowed 1
  demo -e command enter
  demo -e command clock -e hhmm 0900
  demo -e command battery -e level 100 -e plugged false
  demo -e command network -e wifi show -e level 4
  demo -e command network -e mobile hide
  demo -e command notifications -e visible false
}

demo_off() { demo -e command exit || true; }
trap demo_off EXIT

# Capture the current screen into both the raw and the store folders.
capture() {
  local distro="$1" slot="$2"
  local raw="$OUT/_raw/$distro/$slot.png"
  local shot="$OUT/$distro/shot_$slot"
  mkdir -p "$(dirname "$raw")" "$(dirname "$shot")"
  adb exec-out screencap -p > "$raw"
  if command -v cwebp >/dev/null; then
    cwebp -quiet -q 84 -resize 1080 0 "$raw" -o "$shot.webp"
  else
    # No cwebp (brew install webp): the admin accepts PNG too, only larger.
    cp "$raw" "$shot.png"
  fi
}

demo_on
for distro in "${DISTROS[@]}"; do
  echo
  echo "== $distro =="
  read -r -p "Apply $distro on the phone, then press Enter (s to skip) " answer
  [ "$answer" = "s" ] && continue
  for i in "${!SLOTS[@]}"; do
    read -r -p "  Show ${PROMPTS[$i]}, then press Enter " _
    capture "$distro" "${SLOTS[$i]}"
    echo "  saved shot_${SLOTS[$i]}"
  done
done

echo
echo "Done: $OUT"
