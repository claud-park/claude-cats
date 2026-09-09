#!/usr/bin/env bash
# 번들을 만들어 /Applications 에 설치한다.
#
# ~/Applications 가 아니라 /Applications 인 이유: Finder 사이드바의 "응용 프로그램"·
# Launchpad·Spotlight 는 /Applications 를 본다. 홈 폴더 쪽 ~/Applications 에 두면
# 앱이 그 목록 어디에도 안 나온다.
#
# 사용법: ./scripts/install.sh
#         ./scripts/install.sh --self-update <설치 디렉터리> <실행 중인 pid>
#             앱이 스스로 부르는 모드. 소스를 당겨 다시 빌드하고, 새 인스턴스를 띄운 뒤에야
#             기존 pid 를 내린다. 자세한 건 self_update() 주석 참고.
#
# 환경 변수:
#   DESTDIR  설치할 디렉터리(기본 /Applications). 기본값이 아니면 lsregister 는 건너뛴다
#            — Launch Services 에 임시 경로를 등록해 둘 이유가 없다.
#   CLAUDE_CATS_SELF_UPDATE_SKIP_LAUNCH=1
#            --self-update 에서 복사까지만 하고 새 인스턴스 실행·기존 pid 종료를 건너뛴다.
#            테스트 전용 — 진짜 앱을 띄우지 않고 pull·빌드·복사까지를 확인할 때 쓴다.
set -euo pipefail
cd "$(dirname "$0")/.."

DESTDIR="${DESTDIR:-/Applications}"
APP="dist/ClaudeCats.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

# 심볼릭 링크까지 풀어서 비교한다. realpath 가 없거나 경로가 아직 없으면 준 값 그대로.
resolve_path() {
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1" 2>/dev/null || printf '%s\n' "$1"
  else
    printf '%s\n' "$1"
  fi
}

# 이 번들 경로에서 돌고 있는 pid 들. 이름이 아니라 **경로**로 고른다 — `pkill -x ClaudeCats`
# 는 다른 자리(개발용 dist/ 등)에서 띄워 둔 인스턴스까지 같이 죽인다. pgrep 이 준 pid 를 전부
# 훑어야 하는 이유도 같다: 첫 pid 만 보면 그게 다른 경로일 때 정작 찾던 인스턴스를 놓친다.
pids_at_bundle() {
  wanted="$(resolve_path "$1/Contents/MacOS/ClaudeCats")"
  skip="${2:-}"
  found=""
  for pid in $(pgrep -x ClaudeCats 2>/dev/null || true); do
    [ "$pid" = "$skip" ] && continue
    running_bin="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
    [ -n "$running_bin" ] || continue
    if [ "$(resolve_path "$running_bin")" = "$wanted" ]; then
      found="$found $pid"
    elif [ -z "$skip" ]; then
      echo "참고: ClaudeCats(pid $pid) 가 $running_bin 에서 돌고 있다 — 건드리지 않는다"
    fi
  done
  printf '%s' "$found"
}

# 앱이 메뉴에서 "업데이트 설치"를 눌렀을 때 도는 자리.
#
# 순서가 전부다. **기존 인스턴스는 새 인스턴스가 실제로 뜬 걸 확인한 다음에만** 내린다.
# 그 전에 실패하면 non-zero 로 나가고, 사용자는 쓰던 앱을 그대로 쓴다 — 실패한 업데이트가
# 앱을 없애 버리는 게 제일 나쁜 결과다.
self_update() {
  target_dir="${1:-}"
  old_pid="${2:-}"
  if [ -z "$target_dir" ] || [ -z "$old_pid" ]; then
    echo "사용법: install.sh --self-update <설치 디렉터리> <실행 중인 pid>" >&2
    exit 2
  fi

  echo "== self-update $(date '+%Y-%m-%d %H:%M:%S')"
  echo "저장소: $(pwd -P) / 대상: $target_dir / 기존 pid: $old_pid"

  git rev-parse --git-dir >/dev/null 2>&1 || {
    echo "여기는 git 저장소가 아니다 — 아무것도 하지 않는다" >&2; exit 1; }

  branch="$(git rev-parse --abbrev-ref HEAD)"
  [ "$branch" != "HEAD" ] || {
    echo "detached HEAD 라 어느 브랜치를 당길지 알 수 없다" >&2; exit 1; }

  # 로컬 변경 위로는 절대 당기지 않는다. 앱도 미리 막지만(UpdateCheck.status → dirtyTree)
  # 확인과 설치 사이에 손댔을 수 있으니 여기서 한 번 더 본다.
  if [ -n "$(git status --porcelain)" ]; then
    echo "작업 트리가 더럽다 — 로컬 변경을 덮어쓰지 않으려고 여기서 멈춘다:" >&2
    git status --short >&2
    exit 1
  fi

  echo "== git pull --ff-only origin $branch"
  git pull --ff-only origin "$branch" || {
    echo "pull 실패 — fast-forward 가 아니거나 origin 에 $branch 가 없다. 앱은 그대로 둔다" >&2
    exit 1; }

  echo "== 빌드"
  ./scripts/bundle.sh

  target="$target_dir/ClaudeCats.app"
  if [ "$(resolve_path "$target")" = "$(resolve_path "$APP")" ]; then
    # dist/ 에서 그대로 돌고 있던 경우. 방금 bundle.sh 가 그 자리를 새로 만들었다.
    echo "대상이 빌드 산출물과 같은 자리다 — 복사를 건너뛴다"
  else
    mkdir -p "$target_dir"
    rm -rf "$target"
    cp -R "$APP" "$target"
    echo "설치 $target"
  fi

  if [ "${CLAUDE_CATS_SELF_UPDATE_SKIP_LAUNCH:-}" = "1" ]; then
    echo "SKIP_LAUNCH=1 — 새 인스턴스 실행과 기존 pid 종료를 건너뛴다"
    echo "== self-update 완료 (실행 생략)"
    return 0
  fi

  # -n 이 필요하다. 같은 번들이 이미 돌고 있으면 `open` 은 그걸 앞으로 끌어올 뿐 새 프로세스를
  # 만들지 않는다 — 자기 자신을 갱신하는 지금은 항상 그 상황이다.
  echo "== 새 인스턴스 실행"
  open -n "$target"

  new_pid=""
  for _ in $(seq 1 100); do
    new_pid="$(pids_at_bundle "$target" "$old_pid" | awk '{print $1}')"
    [ -n "$new_pid" ] && break
    /bin/sleep 0.1
  done
  if [ -z "$new_pid" ]; then
    echo "새 인스턴스를 10초 안에 확인하지 못했다 — 기존 인스턴스를 그대로 둔다" >&2
    exit 1
  fi
  echo "새 인스턴스 pid $new_pid"

  kill "$old_pid" 2>/dev/null || true
  echo "기존 pid $old_pid 에 종료 요청"
  echo "== self-update 완료"
}

if [ "${1:-}" = "--self-update" ]; then
  shift
  self_update "$@"
  exit 0
fi

TARGET="$DESTDIR/ClaudeCats.app"

./scripts/bundle.sh

# 실행 중인 인스턴스가 **설치 대상 자리에서** 돌고 있으면 먼저 내린다. 돌고 있는 번들을
# 덮어쓰면 앱이 자기 밑동을 잃는다. 고르는 규칙은 pids_at_bundle() 주석 참고.
MATCHED_PIDS="$(pids_at_bundle "$TARGET")"

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
