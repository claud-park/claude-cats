#!/usr/bin/env bash
# release 빌드 후 ClaudeCats.app 번들을 만든다. 출력: dist/ClaudeCats.app
#
# 사용법: ./scripts/bundle.sh            번들만 만든다
#         ./scripts/bundle.sh --install  만들고 /Applications 에 설치한다 (install.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

# `bundle.sh --install` 은 install.sh 로 넘긴다(그쪽이 다시 이 스크립트를 부른다).
if [ "${1:-}" = "--install" ]; then
  shift
  exec ./scripts/install.sh "$@"
fi

swift build -c release 2>&1 | tail -1
BIN=".build/release/ClaudeCats"
APP="dist/ClaudeCats.app"
ICNS="dist/AppIcon.icns"

# Design/cats/sitting.svg → dist/AppIcon.icns. 이미 최신이면 make-icon.swift 가 알아서
# 건너뛴다. iconutil 이 없는 환경(축소 설치된 CLT 등)에서는 아이콘만 빼고 계속 간다 —
# 번들 자체는 아이콘 없이도 돈다.
ICON_KEY=""
if command -v iconutil >/dev/null 2>&1; then
  swift scripts/make-icon.swift "$ICNS"
  ICON_KEY='  <key>CFBundleIconFile</key><string>AppIcon</string>'
else
  echo "경고: iconutil 이 없어 아이콘을 건너뛴다 (앱은 기본 아이콘으로 뜬다)" >&2
  rm -f "$ICNS"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ClaudeCats"
if [ -f "$ICNS" ]; then
  mkdir -p "$APP/Contents/Resources"
  cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.claudecats.app</string>
  <key>CFBundleName</key><string>Claude Cats</string>
  <key>CFBundleExecutable</key><string>ClaudeCats</string>
$ICON_KEY
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
