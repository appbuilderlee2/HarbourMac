#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'This build requires macOS with Xcode Command Line Tools.'; exit 1
fi
export MACOSX_DEPLOYMENT_TARGET=12.0
swift build -c release --arch x86_64
binary_dir="$(swift build -c release --arch x86_64 --show-bin-path)"
app_path="$PWD/dist/Harbour.app"
mkdir -p "$app_path/Contents/MacOS"
cp "$binary_dir/HarbourMac" "$app_path/Contents/MacOS/HarbourMac"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>HarbourMac</string>
<key>CFBundleIdentifier</key><string>local.harbour.mac</string>
<key>CFBundleName</key><string>Harbour</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.1</string>
<key>CFBundleVersion</key><string>31</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app_path"
hdiutil create -volname Harbour -srcfolder "$app_path" -ov -format UDZO "$PWD/dist/Harbour-Intel.dmg"
echo "Built: $app_path"
