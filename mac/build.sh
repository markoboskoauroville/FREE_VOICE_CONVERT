#!/bin/sh
# build.sh: Free Voice Convert Equalizer (Mantra).app, swiftc straight, no Xcode (MANTRA_MANIFEST swift-apps.md).
# Signed "Mantra Apps" on Marko's Mac and installed in /Applications; ad-hoc signed on GitHub (no key there).
# The engine (../engine) is copied into Resources/engine. Apple Silicon only: torch 2.5 has no Intel Mac build.
set -e
cd "$(dirname "$0")"
V=$(sed -n 's/^let VERSION = \([0-9]*\)/\1/p' App.swift)
NAME="Free Voice Convert Equalizer (Mantra)"
APP="build/$NAME.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 -o "$APP/Contents/MacOS/FreeVoiceConvert" App.swift Meters.swift
(cd icon && swift make_icon.swift "$V" >/dev/null)
I=build/AppIcon.iconset; rm -rf $I; mkdir -p $I
for s in 16 32 128 256 512; do
  sips -z $s $s icon/icon_1024.png --out $I/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) icon/icon_1024.png --out $I/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $I -o "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Resources/engine"
cp ../engine/*.py ../engine/setup.sh ../engine/requirements.txt ../engine/PINS "$APP/Contents/Resources/engine/"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>$NAME</string>
<key>CFBundleDisplayName</key><string>$NAME</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>community.auroville.freevoiceconvert</string>
<key>CFBundleExecutable</key><string>FreeVoiceConvert</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$V</string>
<key>CFBundleVersion</key><string>$V</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSArchitecturePriority</key><array><string>arm64</string></array>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PL
if [ -n "$CI" ] || ! security find-identity -p codesigning 2>/dev/null | grep -q "Mantra Apps"; then
  codesign --force --deep -s - "$APP"; echo "ad-hoc signed"
else
  codesign --force --deep -s "Mantra Apps" "$APP"
  rm -rf "/Applications/$NAME.app"; cp -R "$APP" /Applications/; echo "installed in /Applications"
fi
echo "built $APP (v$V)"
