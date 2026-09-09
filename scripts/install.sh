#!/usr/bin/env bash
# 번들을 만들어 /Applications 에 설치한다.
#
# ~/Applications 가 아니라 /Applications 인 이유: Finder 사이드바의 "응용 프로그램"·
# Launchpad·Spotlight 는 /Applications 를 본다. 홈 폴더 쪽 ~/Applications 에 두면
# 앱이 그 목록 어디에도 안 나온다.
#
# 사용법: ./scripts/install.sh
#
# 환경 변수:
#   DESTDIR  설치할 디렉터리(기본 /Applications). 기본값이 아니면 lsregister 는 건너뛴다
#            — Launch Services 에 임시 경로를 등록해 둘 이유가 없다.
set -euo pipefail
cd "$(dirname "$0")/.."

DESTDIR="${DESTDIR:-/Applications}"
APP="dist/ClaudeCats.app"
TARGET="$DESTDIR/ClaudeCats.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

./scripts/bundle.sh

# 심볼릭 링크까지 풀어서 비교한다. realpath 가 없거나 경로가 아직 없으면 준 값 그대로.
resolve_path() {
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1" 2>/dev/null || printf '%s\n' "$1"
  else
    printf '%s\n' "$1"
  fi
}

# 실행 중인 인스턴스가 **설치 대상 자리에서** 돌고 있으면 먼저 내린다. 돌고 있는 번들을
# 덮어쓰면 앱이 자기 밑동을 잃는다.
#
# 이름이 아니라 **경로**로 고른다. `pkill -x ClaudeCats` 는 dist/ 에서 개발용으로 띄워
# 둔 인스턴스까지 같이 죽인다 — 설치가 멋대로 죽이면 곤란하다. pgrep 이 준 pid 를 전부
# 훑어야 하는 이유도 같다. 첫 pid 만 보면 그게 다른 경로일 때 설치 대상 인스턴스를
# 놓치고, 반대로 그게 설치 대상일 때 나머지를 싸잡아 죽인다.
WANTED_BIN="$(resolve_path "$TARGET/Contents/MacOS/ClaudeCats")"
MATCHED_PIDS=""
for pid in $(pgrep -x ClaudeCats 2>/dev/null || true); do
  running_bin="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
  [ -n "$running_bin" ] || continue
  if [ "$(resolve_path "$running_bin")" = "$WANTED_BIN" ]; then
    MATCHED_PIDS="$MATCHED_PIDS $pid"
  else
    echo "참고: ClaudeCats(pid $pid) 가 $running_bin 에서 돌고 있다 — 건드리지 않는다"
  fi
done

RELAUNCH=0
if [ -n "$MATCHED_PIDS" ]; then
  echo "실행 중인 $TARGET 를 종료한다 (pid$MATCHED_PIDS)"
  # shellcheck disable=SC2086
  kill $MATCHED_PIDS 2>/dev/null || true
  RELAUNCH=1
  # 고른 pid 가 실제로 빠질 때까지 기다린다(최대 5초). 다른 인스턴스는 안 본다.
  for _ in $(seq 1 50); do
    still_running=0
    for pid in $MATCHED_PIDS; do
      kill -0 "$pid" 2>/dev/null && still_running=1
    done
    [ "$still_running" = "0" ] && break
    /bin/sleep 0.1
  done
fi

mkdir -p "$DESTDIR"
rm -rf "$TARGET"
# -R 로 번들 통째. ditto 가 아니라 cp 인 이유는 특별할 게 없다 — ad-hoc 서명뿐이라
# 확장 속성을 보존할 필요가 없다.
cp -R "$APP" "$TARGET"
echo "설치 $TARGET"

if [ "$DESTDIR" = "/Applications" ]; then
  if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$TARGET"
    echo "Launch Services 등록 완료 (Spotlight·Launchpad 반영)"
  else
    echo "경고: lsregister 를 못 찾았다 — Spotlight 반영이 늦을 수 있다" >&2
  fi
  if [ "$RELAUNCH" = "1" ]; then
    open "$TARGET"
    echo "재실행 $TARGET"
  fi
else
  echo "DESTDIR 가 기본값이 아니라 lsregister·재실행을 건너뛴다"
fi
