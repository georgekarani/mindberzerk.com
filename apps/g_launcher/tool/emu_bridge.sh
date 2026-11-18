#!/bin/bash
# Lets Claude drive the Android emulator through files in tool/.emu-bridge.
#
#   bash tool/emu_bridge.sh          (from apps/g_launcher, Ctrl+C to stop)
#
# Claude writes tool/.emu-bridge/cmd.txt; this loop runs it with adb and
# writes screenshots back beside it. Only the verbs below are accepted, so
# nothing else can reach the shell:
#   tap X Y | hold X Y [ms] | swipe X1 Y1 X2 Y2 [ms] | key KEYCODE
#   text WORD | sleep SECONDS | shot NAME
#   analyze   flutter analyze, output in analyze.txt
#   install   debug build installed on the emulator and opened, output in build.txt
#   pigeon    regenerate the platform bridge from pigeons/launcher_api.dart, output in pigeon.txt
set -u
DIR="$(cd "$(dirname "$0")" && pwd)/.emu-bridge"
# The app this script lives in, for analyze and install.
APP="$(cd "$(dirname "$0")/.." && pwd)"
# adb from PATH, else the Android Studio SDK's own copy.
ADB="${ADB:-$(command -v adb || echo "$HOME/Library/Android/sdk/platform-tools/adb")}"
# The emulator, not a phone on USB or Wi-Fi: adb honours ANDROID_SERIAL.
export ANDROID_SERIAL="${ANDROID_SERIAL:-$("$ADB" devices | awk '/^emulator-/{print $1; exit}')}"
mkdir -p "$DIR"
# Every adb error lands in log.txt, so Claude can read why a step failed.
exec 2>>"$DIR/log.txt"
num='^[0-9]+$'
echo "Emulator bridge watching $DIR with $ADB on $ANDROID_SERIAL (Ctrl+C to stop)" >&1
"$ADB" devices >> "$DIR/log.txt"
while true; do
  if [ -f "$DIR/cmd.txt" ]; then
    mv -f "$DIR/cmd.txt" "$DIR/run.txt"
    # Read on fd 3: `adb shell` reads stdin and would swallow the rest of the
    # file after the first command.
    while read -r verb a b c d e <&3; do
      case "$verb" in
        tap)   [[ $a =~ $num && $b =~ $num ]] && $ADB shell input tap "$a" "$b" ;;
        hold)  [[ $a =~ $num && $b =~ $num ]] && $ADB shell input swipe "$a" "$b" "$a" "$b" "${c:-900}" ;;
        swipe) [[ $a =~ $num && $b =~ $num && $c =~ $num && $d =~ $num ]] && $ADB shell input swipe "$a" "$b" "$c" "$d" "${e:-300}" ;;
        # drag x1 y1 x2 y2 [holdms]: press, hold still, then move and release.
        # The hold is what a long-press recognizer needs before a move, which
        # a plain swipe never gives it.
        drag)  [[ $a =~ $num && $b =~ $num && $c =~ $num && $d =~ $num ]] && {
                 $ADB shell "input motionevent DOWN $a $b; sleep $(awk "BEGIN{print ${e:-700}/1000}"); \
                   for i in 1 2 3 4 5 6 7 8; do \
                     input motionevent MOVE \$(( $a + ($c - $a) * i / 8 )) \$(( $b + ($d - $b) * i / 8 )); \
                   done; sleep 0.4; input motionevent UP $c $d"
               } ;;
        # down/move/up x y: one pointer, step by step, so a screenshot can
        # land mid-drag.
        down|move|up) [[ $a =~ $num && $b =~ $num ]] && \
                 $ADB shell input motionevent "$(tr a-z A-Z <<< "$verb")" "$a" "$b" ;;
        key)   [[ $a =~ ^[A-Z_0-9]+$ ]] && $ADB shell input keyevent "$a" ;;
        text)  [[ $a =~ ^[A-Za-z0-9]+$ ]] && $ADB shell input text "$a" ;;
        sleep) [[ $a =~ ^[0-9.]+$ ]] && sleep "$a" ;;
        shot)  [[ $a =~ ^[A-Za-z0-9_-]+$ ]] && $ADB exec-out screencap -p > "$DIR/$a.png" ;;
        analyze) (cd "$APP" && flutter analyze > "$DIR/analyze.txt" 2>&1 < /dev/null) ;;
        test)  (cd "$APP" && flutter test > "$DIR/test.txt" 2>&1 < /dev/null) ;;
        pigeon) (cd "$APP" && dart run pigeon --input pigeons/launcher_api.dart > "$DIR/pigeon.txt" 2>&1 < /dev/null) ;;
        install) (cd "$APP" && flutter build apk --debug > "$DIR/build.txt" 2>&1 < /dev/null \
                   && "$ADB" install -r build/app/outputs/flutter-apk/app-debug.apk >> "$DIR/build.txt" 2>&1 < /dev/null \
                   && "$ADB" shell monkey -p com.mindhunter.g_launcher 1 >> "$DIR/build.txt" 2>&1 < /dev/null) ;;
        *)     echo "ignored: $verb" >> "$DIR/log.txt" ;;
      esac
    done 3< "$DIR/run.txt"
    date +%s > "$DIR/done.txt"
  fi
  sleep 0.5
done
