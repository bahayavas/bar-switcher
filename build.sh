#!/bin/bash
# Derle, .app paketle, imzala, /Applications'a kopyala.
#   ./build.sh            derle + kur
#   ./build.sh --no-install
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Bar Switcher"
BUNDLE_ID="com.bahayavas.bar-switcher"
VERSION="1.0"
OUT="build/$APP_NAME.app"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/BarSwitcher"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/BarSwitcher"

# İkon (bir kez üretilir; yeniden çizmek için build/AppIcon.icns'i sil)
if [[ ! -f build/AppIcon.icns ]]; then
    ICONSET=build/AppIcon.iconset
    mkdir -p "$ICONSET"
    swift tools/make-icon.swift build/icon-1024.png
    for s in 16 32 128 256 512; do
        sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"

cat > "$OUT/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>BarSwitcher</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Barları düzgünce kapatmak (Quit) ve Übersicht widget'larını açıp kapatmak için.</string>
</dict>
</plist>
EOF

codesign --force --sign - --identifier "$BUNDLE_ID" "$OUT"
echo "derlendi: $OUT"

[[ "${1:-}" == "--no-install" ]] && exit 0

# Çalışıyorsa kapat, kopyala, yeniden aç
osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
sleep 0.5
rm -rf "/Applications/$APP_NAME.app"
ditto "$OUT" "/Applications/$APP_NAME.app"
echo "kuruldu: /Applications/$APP_NAME.app"
