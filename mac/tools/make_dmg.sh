#!/bin/sh
# make_dmg.sh: the disk image: the app, a shortcut to Applications, the first-launch note. Run after build.sh.
set -e
cd "$(dirname "$0")/.."
V=$(sed -n 's/^let VERSION = \([0-9]*\)/\1/p' App.swift)
NAME="Free Voice Convert Equalizer (Mantra)"
STAGE=build/dmg; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "build/$NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read me first.txt" <<TXT
Free Voice Convert Equalizer $V  —  https://freevoiceconvert.pages.dev

1. Drag "Free Voice Convert Equalizer (Mantra)" onto the Applications folder. (Apple Silicon Macs: M1 or newer.)
2. Open it from Applications. The first time, macOS says it cannot check the app, because it is signed by its author
   and not through Apple's paid program. Open System Settings > Privacy & Security, scroll down, and press
   "Open Anyway". (On older macOS: right-click the app > Open > Open.)
3. At the first start it installs the voice models by itself: about 3 GB (Python, torch, Seed-VC). After that it works
   offline. Everything stays on your Mac.
4. SOURCE VOICE: a clean recording of the voice every clip should have. ADD FILES: your clips. CONVERT.

Free, GPL-3.0. Voice conversion by Seed-VC (Plachtaa). If it helps you, put something in the bowl on the website.
TXT
cp "build/$NAME.app/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
OUT="build/FreeVoiceConvert-$V.dmg"; rm -f "$OUT" build/tmp.dmg
hdiutil create -quiet -volname "Free Voice Convert $V" -srcfolder "$STAGE" -fs HFS+ -format UDRW build/tmp.dmg
D=$(hdiutil attach -nobrowse -noverify -noautoopen build/tmp.dmg | awk -F'\t' '/\/Volumes\//{print $NF}')
command -v SetFile >/dev/null && SetFile -a C "$D" || true
hdiutil detach -quiet "$D"
hdiutil convert -quiet build/tmp.dmg -format UDZO -imagekey zlib-level=9 -o "$OUT"; rm -f build/tmp.dmg
ls -l "$OUT"
