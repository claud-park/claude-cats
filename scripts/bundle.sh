#!/usr/bin/env bash
# release 빌드 후 ClaudeCats.app 번들을 만든다. 출력: dist/ClaudeCats.app
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release 2>&1 | tail -1
BIN=".build/release/ClaudeCats"
APP="dist/ClaudeCats.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClaudeCats"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.claudecats.app</string>
  <key>CFBundleName</key><string>Claude Cats</string>
  <key>CFBundleExecutable</key><string>ClaudeCats</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "built $APP"
