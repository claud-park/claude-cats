#!/usr/bin/env bash
# `swift test` 래퍼. Xcode 없이 Command Line Tools 만 있는 맥에서도 돌게 한다.
#
# CLT 안에서는 swift-driver 는 6.3 인데 런타임 검색 경로는 usr/lib/swift-6.2/ 를 보고,
# Testing.framework 와 lib_TestingInterop.dylib 가 서로 다른 디렉터리에 흩어져 있다.
# 그래서 `swift test` 가 `no such module 'Testing'` → `Library not loaded: @rpath/...` 로
# 무너진다. DYLD_FRAMEWORK_PATH 는 안 먹는다 — swiftpm-testing-helper 가 SIP 보호
# 바이너리라 DYLD_* 를 버린다. rpath 를 두 군데 다 박아야 통과한다.
#
# Package.swift 에 unsafeFlags 로 넣지 않는 이유: unsafeFlags 가 붙은 패키지는 다른
# 패키지가 의존할 수 없게 되고, Xcode 가 있는 대다수 환경에는 필요 없는 경로다.
#
# 사용법: ./scripts/test.sh [swift test 에 그대로 넘길 인자...]
#   예: ./scripts/test.sh --filter StateCollector
#
# 환경 변수:
#   XCODE_SELECT_OVERRIDE  `xcode-select -p` 대신 쓸 경로(테스트용).
set -euo pipefail
cd "$(dirname "$0")/.."

DEVELOPER_DIR_PATH="${XCODE_SELECT_OVERRIDE:-$(xcode-select -p 2>/dev/null || true)}"

case "$DEVELOPER_DIR_PATH" in
  *CommandLineTools*)
    F="$DEVELOPER_DIR_PATH/Library/Developer/Frameworks"
    L="$DEVELOPER_DIR_PATH/Library/Developer/usr/lib"
    echo "CommandLineTools 감지 ($DEVELOPER_DIR_PATH) — Testing.framework rpath 를 붙여 실행한다"
    exec swift test \
      -Xswiftc -F -Xswiftc "$F" \
      -Xlinker -F -Xlinker "$F" \
      -Xlinker -rpath -Xlinker "$F" \
      -Xlinker -rpath -Xlinker "$L" \
      "$@"
    ;;
  *)
    exec swift test "$@"
    ;;
esac
