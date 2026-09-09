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

# 번들에 "이 앱이 어느 소스에서 나왔는지"를 박는다. 앱의 자체 업데이트(Updater.swift)가
# 이 값만 보고 저장소를 찾아 `git fetch` 하고 `scripts/install.sh --self-update` 를 부른다.
# git 저장소가 아니면(내려받은 tarball 등) 전부 unknown 이고, 앱은 업데이트 항목을 잠근다.
REPO_ROOT="$(pwd -P)"
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 &&
   git -C "$REPO_ROOT" rev-parse HEAD >/dev/null 2>&1; then
  # 스크립트 위치가 아니라 git 이 말하는 최상위를 쓴다 — 심볼릭 링크를 타고 들어왔거나
  # 서브디렉터리에서 불렸을 때 `pwd -P` 와 갈릴 수 있고, 앱은 이 경로에 대고 pull 한다.
  REPO_ROOT="$(git -C "$REPO_ROOT" rev-parse --show-toplevel)"
  COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
  COMMIT_DATE="$(git -C "$REPO_ROOT" log -1 --format=%cd --date=short)"
  BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
  # 커밋 수를 빌드 번호로 쓴다. 태그를 안 쓰는 저장소라 이게 유일하게 단조 증가하는 수다.
  BUILD="$(git -C "$REPO_ROOT" rev-list --count HEAD)"
else
  REPO_ROOT="unknown"
  COMMIT="unknown"
  COMMIT_DATE="unknown"
  BRANCH="unknown"
  BUILD="0"
fi
SHORT_VERSION="0.1.$BUILD"

# 서명 방식을 미리 정한다 — Info.plist 에 그 결과(stable|adhoc)를 박아, 앱이
# "지금 도는 번들이 ad-hoc 이라 업데이트마다 파일 접근 권한이 풀린다"를 알 수 있게 한다.
#
# "ClaudeCats Self-Signed" ID 가 (search list 의) 키체인에 있으면 그걸로 서명한다.
# 그 ID 는 빌드마다 같은 인증서라 지정 요구사항(designated requirement)이 안정적이고,
# 그래서 한 번 받은 TCC 파일 접근 권한이 self-update 재빌드 뒤에도 유지된다.
# ID 가 없으면 예전처럼 ad-hoc 으로 물러선다(경고와 함께).
SIGN_IDENTITY_NAME="ClaudeCats Self-Signed"
# `-v`(valid only)를 쓰지 않는다 — self-signed 인증서는 신뢰 앵커가 아니라
# CSSMERR_TP_NOT_TRUSTED 로 "invalid" 취급돼 `-v` 에서 빠진다. codesign 은 그 인증서로도
# 잘 서명하고(로컬 서명엔 신뢰 불필요), TCC 가 보는 지정 요구사항도 안정적이다.
# `|| true`: ID 가 없으면 grep 이 1 로 끝나는데, 이 스크립트의 pipefail+set -e 에서
# 그게 여기서 빌드를 죽인다(ID 없는 지금 머신이 그렇다). 빈 결과를 정상으로 받는다.
SIGN_SHA="$(security find-identity -p codesigning 2>/dev/null \
  | grep -F "\"$SIGN_IDENTITY_NAME\"" | head -1 | awk '{print $2}' || true)"
if [ -n "$SIGN_SHA" ]; then
  SIGNED_STAMP="stable"
else
  SIGNED_STAMP="adhoc"
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
  <key>CFBundleShortVersionString</key><string>$SHORT_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>ClaudeCatsSourceRepo</key><string>$REPO_ROOT</string>
  <key>ClaudeCatsCommit</key><string>$COMMIT</string>
  <key>ClaudeCatsCommitDate</key><string>$COMMIT_DATE</string>
  <key>ClaudeCatsBranch</key><string>$BRANCH</string>
  <key>ClaudeCatsSigned</key><string>$SIGNED_STAMP</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

if [ "$SIGNED_STAMP" = "stable" ]; then
  # --identifier 를 못 박는다. CFBundleIdentifier 와 같지만 명시해 둬야 지정 요구사항이
  # `identifier "com.claudecats.app" and certificate leaf = H"…"` 로 안정적으로 나온다.
  codesign --force --sign "$SIGN_SHA" --identifier com.claudecats.app "$APP" >/dev/null
  echo "서명: $SIGN_IDENTITY_NAME ($SIGN_SHA)"
else
  codesign --force --sign - "$APP" >/dev/null
  echo "경고: '$SIGN_IDENTITY_NAME' 서명 ID가 없어 ad-hoc 으로 서명했습니다." >&2
  echo "      업데이트할 때마다 파일 접근 권한(TCC)을 다시 부여해야 합니다." >&2
  echo "      scripts/make-signing-identity.sh 를 한 번 실행하면 그 권한이 유지됩니다." >&2
fi
echo "built $APP ($SHORT_VERSION · $COMMIT · $COMMIT_DATE · $BRANCH · $SIGNED_STAMP)"
