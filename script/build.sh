#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK_PATH="${FITNESS_APP_SDK:-$(xcrun --show-sdk-path)}"
if [[ -z "${FITNESS_APP_SDK:-}" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk; fi
SDK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :Version' "$SDK_PATH/SDKSettings.plist")"
CONFIGURATION="${BUMPPUMP_CONFIGURATION:-release}"
FLAGS=(--arch arm64 -c "$CONFIGURATION" --sdk "$SDK_PATH" -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$SDK_VERSION")
swift build --product BumpPump "${FLAGS[@]}"
BIN="$(swift build "${FLAGS[@]}" --show-bin-path)/BumpPump"
APP="$PWD/dist/BumpPump.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BumpPump"
if [[ "$CONFIGURATION" == release ]]; then strip -S "$APP/Contents/MacOS/BumpPump"; fi
cp Resources/AppIcon.icns LICENSE "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>BumpPump</string>
<key>CFBundleIdentifier</key><string>app.bumppump.mac</string>
<key>CFBundleName</key><string>BumpPump</string>
<key>CFBundleDisplayName</key><string>BumpPump</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "$APP"
if [[ "${1:-}" == --run ]]; then open -n "$APP"; fi
