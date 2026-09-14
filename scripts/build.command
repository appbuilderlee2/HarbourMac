#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'This build requires macOS with Xcode Command Line Tools.'; exit 1
fi
export MACOSX_DEPLOYMENT_TARGET=12.0
engine_path="$PWD/Sources/HarbourMac/Resources/Engine"
if [[ ! -x "$engine_path/bin/analyze-go" || ! -x "$engine_path/bin/status-go" ]]; then
  command -v go >/dev/null || { echo 'Building the engine requires Go 1.25+ (https://go.dev/dl/).'; exit 1; }
  (
    cd "$engine_path"
    GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 go build -buildvcs=false -trimpath -ldflags='-s -w' -o bin/analyze-go ./cmd/analyze
    GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 go build -buildvcs=false -trimpath -ldflags='-s -w' -o bin/status-go ./cmd/status
  )
fi
file "$engine_path/bin/analyze-go" "$engine_path/bin/status-go"
swift build -c release --arch x86_64
binary_dir="$(swift build -c release --arch x86_64 --show-bin-path)"
build_stage="$(mktemp -d "$PWD/Harbour-build.XXXXXX")"
app_path="$build_stage/Harbour.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$PWD/dist"
cp "$binary_dir/HarbourMac" "$app_path/Contents/MacOS/HarbourMac"
cp "$binary_dir/HarbourWorker" "$app_path/Contents/MacOS/HarbourWorker"
cp -R "$binary_dir/HarbourMac_HarbourMac.bundle" "$app_path/Contents/Resources/"
chmod +x "$app_path/Contents/Resources/HarbourMac_HarbourMac.bundle/Resources/askpass.sh"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>HarbourMac</string>
<key>CFBundleIdentifier</key><string>local.harbour.mac</string>
<key>CFBundleName</key><string>Harbour</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.0</string>
<key>CFBundleVersion</key><string>40</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSAppleEventsUsageDescription</key><string>Harbour 只會讀取登入項目的名稱、位置及隱藏狀態，供你在系統設定管理。</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app_path/Contents/MacOS/HarbourWorker"
codesign --force --sign - "$app_path/Contents/Resources/HarbourMac_HarbourMac.bundle/Resources/Engine/bin/analyze-go"
codesign --force --sign - "$app_path/Contents/Resources/HarbourMac_HarbourMac.bundle/Resources/Engine/bin/status-go"
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
ln -s /Applications "$build_stage/Applications"
hdiutil create -volname Harbour -srcfolder "$build_stage" -ov -format UDZO "$PWD/dist/Harbour-Intel.dmg"
echo "Built: $app_path"
