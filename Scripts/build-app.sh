#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
swift build --product AndorrDesktop "$@"
binary_dir="$(swift build --show-bin-path "$@")"
app_dir="$PWD/build/Andorr.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/AndorrDesktop" "$app_dir/Contents/MacOS/Andorr"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Andorr</string>
<key>CFBundleDisplayName</key><string>Andorr</string>
<key>CFBundleIdentifier</key><string>org.andorr.notes</string>
<key>CFBundleExecutable</key><string>Andorr</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleDevelopmentRegion</key><string>fr</string>
<key>CFBundleLocalizations</key><array><string>fr</string></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.education</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --timestamp=none --options runtime \
    --entitlements Resources/Andorr.entitlements "$app_dir"
echo "Application créée : $app_dir"
