# Claude Cats

실행 중인 Claude Code 세션을 바탕화면 위(아이콘 아래) 고양이로 보여주는 macOS 앱.
세션마다 고양이 한 마리, 서브에이전트마다 새끼 고양이 한 마리가 붙는다.
busy 세션은 앉은 자세(꼬리가 1초마다 흔들린다), idle 세션은 웅크려 자는 자세다.
[알림 연동](#알림-연동)을 켜면 사용자를 기다리는 세션은 세 번째 자세 + 노란 말풍선이 된다.

<img width="455" height="148" alt="image" src="https://github.com/user-attachments/assets/17b9f98c-4ecb-4c4d-a30d-8c46edf44b02" />



```bash
swift build               # 빌드
.build/debug/ClaudeCats   # 실행 (창 없이 바탕화면에 그린다)
./scripts/test.sh         # 테스트 (Xcode 없이 CLT 만 있어도 돈다 — 아래 각주)

./scripts/bundle.sh       # release 빌드 + dist/ClaudeCats.app 생성 (앱 아이콘 포함)
open dist/ClaudeCats.app  # 번들 실행 (메뉴바 앱, Dock 아이콘 없음)

./scripts/install.sh      # 번들 생성 + /Applications 설치 + Launch Services 등록
```

### 설치

`./scripts/install.sh` (= `./scripts/bundle.sh --install`) 이 번들을 만들어
`/Applications/ClaudeCats.app` 로 넣고 `lsregister -f` 까지 돌린다. 그 자리에서
돌고 있던 인스턴스가 있으면 먼저 내리고 설치 후 다시 띄운다(다른 경로 —
`dist/` 에서 개발용으로 띄워 둔 것 — 은 건드리지 않는다).

**`~/Applications` 는 안 된다.** Finder 사이드바의 "응용 프로그램"·Launchpad·
Spotlight 는 `/Applications` 를 본다. 홈 폴더 쪽 `~/Applications` 에 넣으면 그 목록
어디에도 안 뜬다.

설치 위치를 바꾸려면 `DESTDIR=/원하는/경로 ./scripts/install.sh`. 기본값이 아니면
`lsregister` 와 재실행은 건너뛴다.

### 코드 서명

**왜 필요한가 — 업데이트가 파일 접근 권한을 잃지 않게.** 이 앱의 자체 업데이트는
소스에서 다시 빌드해 번들을 갈아끼운다([업데이트](#업데이트) 참고). 그런데 저장소가
`~/Documents` 처럼 TCC 가 지키는 위치에 있으면, 앱은 그 저장소를 읽기 위해 한 번
**파일 접근 권한**을 받아 둬야 한다. 문제는 macOS 가 그 권한을 앱의 코드 서명
**지정 요구사항**(designated requirement)에 묶는다는 점이다.

ad-hoc 서명(`codesign --sign -`)은 빌드마다 코드 해시(cdhash)가 바뀌므로 지정
요구사항도 매번 달라진다. 그래서 self-update 로 다시 빌드할 때마다 예전 권한이 새
번들과 안 맞아 풀리고, 백그라운드 앱이라 다시 묻는 창도 못 띄운 채 업데이트 확인이
막힌다(메뉴에 "소스 저장소에 접근하지 못했습니다"가 뜬다).

안정적인 **self-signed 서명 ID** 로 서명하면 인증서가 그대로인 한 지정 요구사항이
빌드마다 **동일**하다 — `identifier "com.claudecats.app" and certificate leaf = H"…"`.
그래서 한 번 허용한 파일 접근 권한이 이후 업데이트에도 그대로 유지된다.

**한 번만 실행한다.**

```bash
./scripts/make-signing-identity.sh   # 로그인 키체인에 "ClaudeCats Self-Signed" 생성
./scripts/install.sh                 # 이제 이 ID 로 서명해 설치한다
```

- `make-signing-identity.sh` 는 `openssl` 로 코드 서명용 self-signed 인증서를 만들어
  로그인 키체인에 넣는다. 애플 계정도, 네트워크도 필요 없다. 이미 있으면 아무것도 하지
  않는다(idempotent).
- 마지막 `security set-key-partition-list` 단계는 로그인 키체인 암호가 필요할 수 있다.
  실패하면 스크립트가 정확한 다음 명령을 알려 주므로, 로그인 암호를 넣어 한 번 실행하면
  된다(또는 codesign 이 처음 뜨는 "항상 허용" 창을 한 번 눌러도 된다).
- 그 뒤 `bundle.sh`/`install.sh` 는 이 ID 를 자동으로 찾아 서명하고, Info.plist 에
  `ClaudeCatsSigned=stable` 을 박는다. ID 가 없으면 예전처럼 ad-hoc 으로 물러서고
  (`ClaudeCatsSigned=adhoc`), 그때는 업데이트 안내가 "이 ID 를 만들라"고 짚어 준다.
- **처음 한 번의 파일 접근 허용은 여전히 필요하다.** 그 첫 허용 이후로는 재빌드해도
  유지된다는 게 이 서명의 요점이다.

이 ID 는 **로컬 전용**이다. 자기 맥에서 codesign 이 쓸, 매번 같은 인증서일 뿐이다.

### 배포

self-signed 든 ad-hoc 이든 이 서명은 **자기 맥에 직접 빌드해 설치**하기 위한 것이다 —
둘 다 `TeamIdentifier=not set` 이라 남에게 `.app`·`.dmg` 를 건네면 Gatekeeper 가 막는다.
배포하려면 Developer ID 인증서로 서명하고 공증(notarization)까지 받아야 한다 —
**아직 구현돼 있지 않다.**

앱 아이콘은 `scripts/make-icon.swift` 가 `Design/cats/sitting.svg` 에서 만든다 —
`#FUR` 계열 플레이스홀더를 팔레트 0번 색으로 채우고, 알파 경계상자를 재서 고양이를
가운데·8% 여백으로 10가지 크기에 렌더한 뒤 `iconutil` 로 `dist/AppIcon.icns` 를
굽는다. 그림이 그대로면 다시 굽지 않고, `iconutil` 이 없으면 경고만 남기고
아이콘 없이 번들을 만든다.

> **`swift test` 대신 `./scripts/test.sh` 를 쓰는 이유** — Xcode 없이 Command Line Tools
> 만 깔린 맥에서는 `swift test` 가 `no such module 'Testing'` →
> `Library not loaded: @rpath/Testing.framework/...` 로 실패한다. CLT 안에서
> `Testing.framework` 와 `lib_TestingInterop.dylib` 가 런타임 검색 경로에 없는 서로 다른
> 디렉터리에 있기 때문이고, `swiftpm-testing-helper` 가 SIP 보호 바이너리라
> `DYLD_FRAMEWORK_PATH` 로는 못 고친다. `scripts/test.sh` 는 `xcode-select -p` 가
> CommandLineTools 를 가리킬 때만 rpath 두 개를 붙여 주고, Xcode 가 있으면 그냥
> `swift test` 를 부른다. (`Package.swift` 에 `unsafeFlags` 로 넣지 않는 이유는
> 스크립트 주석에 적어 뒀다.)

## 메뉴바 항목

| 항목 | 하는 일 |
| --- | --- |
| `고양이 N마리 · 작업 중 N` | 읽기 전용 요약 |
| `⚠️ 세션 파일 …` | 세션 파일을 못 읽었을 때만 나오는 경고 ([아래](#문제가-생겼을-때)) |
| `일시정지` / `재개` | 폴링·그리기 정지 |
| `지금 새로고침` | 즉시 한 번 폴링 |
| `버전 0.1.N · <sha> · <날짜>` | 읽기 전용. 지금 도는 번들이 어느 커밋에서 나왔는지 ([아래](#업데이트)) |
| `업데이트 확인…` / `업데이트 설치 (N개 커밋)` | 소스에서 다시 빌드해 갈아끼운다 ([아래](#업데이트)) |
| `자동으로 업데이트 확인` | 자동 확인 켜기/끄기 (기본 켜짐) |
| `디스플레이` | 고양이를 그릴 화면 선택 |
| `표시 위치` | 창 레벨 선택 — 바탕화면 / 창 아래 / 항상 위 ([아래](#표시-위치)) |
| `고양이 종류` | 그림 선택 — 푹신캣 / 동글캣 ([아래](#고양이-종류)) |
| `알림 연동` | Claude Code 훅 설치/해제 (아래 참고) |
| `로그인 시 시작` | 로그인 항목 등록/해제 |
| `종료` | 앱 종료 |

`디스플레이` 하위 메뉴는 `자동 (메인 디스플레이)` 와 지금 연결된 화면 이름들을 보여주고, 고른
항목에 체크가 붙는다(한 번에 한 화면). 선택은 화면 **이름**으로 `UserDefaults`
(`preferredDisplayName`) 에 저장한다 — 디스플레이 ID 는 재부팅·재연결마다 바뀌기 때문이다.
고른 모니터를 뽑으면 자동으로 메인 디스플레이에 그리고, 메뉴에는 `<이름> (연결 안 됨)` 항목이
체크된 채 남아 다시 꽂으면 그 화면으로 돌아간다. 하위 메뉴는 열 때마다 다시 만든다.

## 표시 위치

기본값(`바탕화면`)은 이름 그대로 바탕화면 레이어라, 터미널·에디터가 떠 있으면 고양이가 보이지
않는다. 창을 다 치우기 싫으면 `표시 위치` 하위 메뉴에서 세 가지 중에 고른다(한 번에 하나,
고른 항목에 체크가 붙는다).

| 항목 | 창 레벨 | 이럴 때 |
| --- | --- | --- |
| `바탕화면 (아이콘 아래)` | `desktopIconWindow − 1` | 기본값. 바탕화면 아이콘에도 가린다 |
| `창 아래 (아이콘 위)` | `desktopIconWindow + 1` | 아이콘 위로 올라오되 앱 창에는 여전히 가린다 |
| `항상 위` | `NSWindow.Level.floating` | 작업하면서 곁눈질로 본다. **고양이가 다른 창 위에 겹쳐 보인다** |

`항상 위` 여도 창은 `ignoresMouseEvents` 라 클릭·드래그·스크롤이 전부 뒤 창으로 통과한다 —
고양이가 가리기는 해도 막지는 않는다. 앱이 `LSUIElement` 라 포커스를 뺏지도 않는다.
이 모드에서만 `collectionBehavior` 에 `.fullScreenAuxiliary` 를 더해 전체화면 앱 위에도 뜬다
(나머지 `.canJoinAllSpaces` · `.stationary` · `.ignoresCycle` 은 세 모드 공통이다).

선택은 `UserDefaults` (`windowPlacement`) 에 raw value(`desktop` / `aboveIcons` /
`alwaysOnTop`)로 저장한다. 키가 없거나 모르는 값이면 `바탕화면` 이다. 바꿔도 창을 다시 만들지
않고 레벨만 갈아 끼우므로 고양이가 깜빡이지 않는다.

## 고양이 종류

`고양이 종류` 하위 메뉴에서 두 그림 중에 고른다(한 번에 하나, 고른 항목에 체크가 붙는다).
모든 고양이가 같은 종류로 함께 바뀐다.

| 항목 | 그림 | 색 |
| --- | --- | --- |
| `푹신캣` | 기본 팀 고양이. 앉기·자기·알림 세 포즈에 꼬리를 흔든다 | 세션마다 8색 팔레트 중 하나 |
| `동글캣` | 회색 스코티시폴드풍 고양이. 접힌 귀·동그란 몸통 | 세션마다 팔레트로 몸통색이 갈린다 |

두 종류 다 세션 이름 해시로 색이 정해져 세션마다 몸통색이 다르다. 다만 **동글캣은 몸통 주색과
그 음영(`FUR`/`FURDARK`)만** 팔레트로 바뀌고, 눈·코 윤곽·코·얼굴 크림색·수염은 고정이다
(원본에 그 색만 있고 하이라이트 `FURLIGHT` 색은 없다).

**동글캣은 꼬리를 흔들지 않는다.** 원본 SVG(`kenji-*-figma.svg`)에 꼬리 프레임
(`tail-a`/`tail-b`)이 없어서다 — 꼬리는 몸통에 붙은 정지 그림으로 들어간다. 흔들게 하려면
Figma 에서 꼬리 프레임을 `tail-a`/`tail-b` 로 이름 붙여 다시 내보내고
(`고양이 종류`·[직접 그린 SVG](#직접-그린-svg-넣는-법) 참고), `generate-cat-art.sh` 의 켄지 import 에서
`--pose sitting` 으로 바꾸면 된다. 알림(`alert`) 포즈도 원본이 없어 앉은 그림을 그대로 쓴다.

선택은 `UserDefaults` (`catConcept`) 에 raw value(`team` = 푹신캣 / `kenji` = 동글캣)로 저장한다
— 내부 식별자는 소스·생성 파일 이름과 묶여 있어 표시 이름과 다르다. 키가 없거나 모르는 값이면
`푹신캣` 이다. 바꿔도 창·배치는 그대로 두고 각 고양이의 그림만 갈아끼우므로 깜빡이지 않는다.

## 업데이트

이 앱은 릴리스 바이너리를 배포하지 않는다 — 다들 저장소를 clone 해서 직접 빌드해 쓴다.
그래서 업데이트도 "새 `.app` 을 내려받기"가 아니라 **원래 빌드했던 그 저장소에서 다시
빌드하기**다. 메뉴에서 `업데이트 확인…` 을 누르면 그 자리에서 받아 빌드하고 앱을 새로 띄운다.

### 어떻게 도나

`scripts/bundle.sh` 가 번들을 만들 때 Info.plist 에 **어느 소스에서 나왔는지**를 박는다.

| 키 | 값 |
| --- | --- |
| `ClaudeCatsSourceRepo` | 빌드한 저장소의 절대 경로 |
| `ClaudeCatsCommit` · `ClaudeCatsCommitDate` · `ClaudeCatsBranch` | 그때의 HEAD |
| `CFBundleVersion` · `CFBundleShortVersionString` | `git rev-list --count HEAD` 와 `0.1.<그 수>` |

git 저장소가 아닌 곳에서 빌드했으면 전부 `unknown` 이고, 메뉴는
`업데이트: 소스 저장소를 모름` 으로 잠긴다(저장소에서 `./scripts/install.sh` 로 다시 깔면
풀린다). detached HEAD 에서 빌드했으면 브랜치 자리에 `HEAD` 가 박히고, 어느 브랜치를
따라갈지 알 수 없으므로 `업데이트 불가 (detached HEAD)` 로 잠긴다.

확인은 그 경로에 대고 `git fetch --quiet origin <브랜치>` → `rev-list --count HEAD..origin/<브랜치>`
→ `log -1 --format=%s` → `status --porcelain` 넷을 돌리는 게 전부다. 백그라운드 큐에서 돌고
(fetch 20초, 나머지 10초 타임아웃) 결과만 메인으로 올라오므로 메뉴가 멈추지 않는다.
**폴링 틱에는 아무것도 얹지 않는다** — 네트워크는 확인할 때만 쓴다.

뒤처짐을 세는 기준은 저장소 HEAD 가 아니라 **지금 도는 번들이 박고 나온 커밋**이다
(`<스탬프 커밋>..origin/<브랜치>`). 둘은 갈라질 수 있다 — pull 은 됐는데 빌드가 깨져서 앱만
옛 커밋에 남는 경우가 그렇다. HEAD 를 기준으로 세면 그때 "최신"이라고 말해 버리고 사용자는
낡은 앱을 든 채 다시는 안내를 못 받는다. 스탬프 커밋이 저장소에서 사라졌으면(리베이스·강제
푸시) HEAD 기준으로 물러선다.

설치를 누르면 `scripts/install.sh --self-update <설치 디렉터리> <지금 pid> <브랜치>` 가 돈다.
순서가 전부다.

1. 받은 값 검증 — pid 가 숫자이고 실제로 `ClaudeCats` 여야 하고, 설치 디렉터리가 있어야 하고,
   그 자리의 `ClaudeCats.app` 은 실행 파일을 갖고 있어야 한다. **`rm` 도 `kill` 도 이 뒤에만
   있다**
2. 저장소가 앱이 나온 그 브랜치에 서 있는지 확인 — 다르면 멈춘다(작업하려고 옮겨 둔 브랜치를
   앱이 멋대로 빌드해 설치하면 안 된다)
3. 작업 트리가 더러우면 **여기서 멈춘다**
4. `git pull --ff-only origin <브랜치>` — fast-forward 가 아니면 멈춘다
5. 당겨온 스크립트로 한 번 다시 `exec` — pull 이 이 스크립트 자신을 바꿨을 수 있는데, git 은
   파일을 unlink 하고 새로 만들기 때문에 돌고 있는 bash 는 옛 내용을 계속 읽는다
6. `./scripts/bundle.sh` 로 다시 빌드
7. 지금 돌고 있는 자리(`/Applications` 든 `dist/` 든)에 **갈아끼우기** — 같은 디렉터리 안에
   staging 으로 복사한 뒤 rename 두 번(`기존 → .old`, `staging → 제자리`)으로 바꾸고, 바꾸다
   실패하면 `.old` 를 되돌린다. 먼저 지우고 나중에 복사하면 복사가 실패하는 순간 사용자에게
   아무 앱도 안 남는다
8. `open -n` 으로 새 인스턴스를 띄우고, **그게 실제로 뜬 걸 확인한 다음에야** 기존 pid 에
   `kill` — "새로 떴다"는 판정은 `open` **전에** 적어 둔 pid 목록에 없는 pid 여야 한다

어디서 실패해도 non-zero 로 끝나고 쓰던 앱은 그대로 남는다. 실패한 업데이트가 앱을 없애
버리는 게 제일 나쁜 결과라, 기존 인스턴스는 항상 마지막에 내린다(내린 뒤 5초까지 실제로
내려갔는지 보고 아니면 로그에 남긴다).

### 필요한 것

- **git 과 Swift 툴체인.** 확인은 `git` 만, 설치는 `swift build -c release` 까지 쓴다.
- **`origin` 에 붙을 수 있는 권한.** 앱 번들은 Finder 가 띄우므로 PATH 가 거의 비어 있다 —
  `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin` 을 직접 깔아 준다. SSH 는 `BatchMode=yes`
  로 돌리므로 열쇠가 ssh-agent(키체인)에 없으면 **묻지 않고 그냥 실패**한다. 매달려 있느니
  실패하는 편이 낫다. git 은 `LC_ALL=C` 로 돌린다 — 우리가 git 의 메시지를 읽고 "고장"과
  "아직 push 안 한 브랜치"를 가르기 때문에 그 글자가 지역화되면 안 된다.
- 빌드는 1~2분쯤 걸린다. 그동안 메뉴 요약 줄이 `업데이트 중… (빌드)` 로 바뀌고 업데이트
  항목이 잠긴다.

### 로컬 변경이 있으면

**아무것도 하지 않는다.** `git status --porcelain` 이 비어 있지 않으면 메뉴가
`업데이트: 로컬 변경 있음` 이 되고, 설치를 눌러도 스크립트가 pull 전에 멈춘다(확인과 설치
사이에 손댔을 수 있어 양쪽에서 본다). 커밋하거나 치운 뒤 다시 확인하면 된다.

단, **당길 게 없으면** 더러워도 조용하다 — 평소 작업 중인 저장소에서 늘 켜져 있는 경고는
아무도 안 읽는다.

`origin` 에 그 브랜치가 아직 없으면(작업 브랜치에서 번들을 만든 경우) 고장이 아니라
"당길 게 없다"로 보고 `최신 버전입니다` 라고 한다. 이유는 로그에 남는다.

### 언제 확인하나

반복 타이머는 없다.

| 언제 | 조건 |
| --- | --- |
| 실행 30초 뒤 한 번 | `자동으로 업데이트 확인` 이 켜져 있을 때 |
| 메뉴를 열 때 | 마지막 확인이 **24시간**보다 오래됐을 때만 |
| `업데이트 확인…` 을 눌렀을 때 | 항상 (결과를 창으로 알린다) |

자동 확인은 조용히 메뉴만 바꾼다 — 받을 게 있으면 메뉴바 아이콘 옆에 점(`•`)이 붙고 항목
제목이 `업데이트 설치 (N개 커밋)` 이 된다. 끄려면 메뉴에서 `자동으로 업데이트 확인` 을 다시
누른다(`UserDefaults` 의 `autoUpdateCheck`, 마지막 확인 시각은 `lastUpdateCheck`).

### 로그

`~/Library/Logs/ClaudeCats/update.log` 에 확인·설치 출력이 그대로 쌓인다(1MB 를 넘으면 앞을
자른다). 설치가 실패하면 마지막 20줄을 창으로 보여주고 `로그 열기` 버튼을 준다.

## 알림 연동

`~/.claude` 를 훑는 것만으로는 알 수 없는 두 가지가 있다 — **Claude 가 사용자를 기다리는 중인지**
(권한 요청·입력 대기)와 **서브에이전트가 정확히 몇 개 도는지**다. 둘 다 Claude Code 훅이
알려준다. 메뉴바의 `알림 연동` 을 켜면 앱이 훅을 깔고, 끄면 되돌린다.

켜면 이렇게 된다.

- 알림이 있는 세션은 **세 번째 자세(`alert`)** 로 바뀌고(자던 고양이도 깬다) 머리 위에 **노란
  말풍선**이 뜬다: `권한 요청: <무엇을 하려는지>` / `입력 기다리는 중` / `에이전트 입력 대기`.
  세션 제목 말풍선은 그동안 가려진다.
- 새끼 고양이를 훅이 센 값과 합친다. idle 세션이어도 백그라운드 에이전트가 돌면 새끼가 붙고,
  `SubagentStop` 을 받으면 파일 mtime 이 아무리 싱싱해도 사라진다. 새끼 id 는 훅 페이로드의
  `agent_transcript_path`(`agent-<id>.jsonl`)에서 뽑는다 — mtime 휴리스틱이 쓰는 id 와 같아야
  한 에이전트가 두 마리로 보이지 않는다. `agent_id` 는 경로가 없을 때의 대비책이다.

알림이 사라지는 경우는 다섯이다.

| 신호 | 왜 |
| --- | --- |
| `UserPromptSubmit` | 사용자가 답했다 |
| **transcript mtime 이 알림 시각 + 5초를 지나갔다** | 권한을 승인하면 Claude 가 도구를 돌리고 transcript 에 append 한다. 제일 정확한 신호이고, 제목 조회가 이미 `stat` 하고 있어서 공짜다. 5초 유예를 두는 이유는 아래 |
| idle → busy 전이 | 새 작업이 시작됐다 |
| 세션 소멸 | 고양이 자체가 사라진다 |
| 30분 TTL | 훅이 죽어 위 신호가 영영 안 올 때의 안전망 |

busy → idle 은 **지우지 않는다**. 권한 프롬프트가 떠 있는 동안 세션이 idle 로 넘어가는 건
정상이고, 그걸로 지우면 알림이 뜨자마자 사라진다. 서브에이전트가 입력을 기다리는
(`agent_needs_input`) 동안 본 대화가 끝나는 경우도 마찬가지다.

transcript 규칙에 5초 유예(`alertClearGrace`)를 두는 것도 같은 이유다 — 알림을 띄운 그 턴이
직후에 자기 기록을 한두 줄 마저 쓴다. 그걸 "사용자가 답했다"로 읽으면 알림이 뜨자마자
사라진다. 알림 시각은 폴링 틱이 아니라 **이벤트 파일의 mtime**(= 훅이 실제로 터진 때)이라,
폴링 간격이나 앱이 꺼져 있던 시간만큼 시계가 밀리지 않는다.

`SubagentStop` 을 놓쳤을 때(Claude 가 죽거나 훅이 실패하거나)를 대비해 훅이 센 서브에이전트에도
4시간 TTL 이 있다. 서브에이전트는 몇 시간씩 돌기도 해서 넉넉하게 잡았다.

### 무엇을 어디에 쓰나

| 경로 | 내용 |
| --- | --- |
| `~/Library/Application Support/ClaudeCats/claude-cats-hook.sh` | 훅 스크립트(755). stdin 을 파일 하나로 옮기고 끝난다 |
| `~/.claude/settings.json` | 위 스크립트를 `Notification` · `SubagentStart` · `SubagentStop` · `UserPromptSubmit` 네 이벤트에 등록 (`timeout: 5`) |
| `~/.claude/settings.json.claude-cats.bak` | 이 앱이 처음 쓰기 전 원본 백업(앱 실행당 한 번) |
| `~/.claude/claude-cats/events/` | 훅이 떨구는 이벤트 파일. 앱이 읽자마자 지운다 |

`Notification` 만 matcher 가 붙는다(`permission_prompt|idle_prompt|agent_needs_input`). 나머지
셋은 빈 matcher(=전부)다. 훅 스크립트는 파일 하나 쓰고 **항상 exit 0** 이라 Claude 를 막지
않는다. 임시 이름으로 받아 같은 디렉터리에서 rename 하므로 앱이 반쯤 쓰인 파일을 읽지 않는다.

앱이 꺼져 있으면 이벤트 파일을 아무도 치우지 않는다. 양쪽에서 막는다 — 훅은 파일이 5000개를
넘으면 쓰지 않고 나가고(세는 비용은 디렉터리 크기와 무관하다), 앱은 한 틱에 오래된 것부터
200개까지만 삼키고 나머지는 다음 틱으로 넘긴다.

이미 우리 스크립트가 **다른 matcher** 로 걸려 있으면 그 항목을 인정하고 새로 넣지 않는다.
같은 command 를 두 번 걸면 이벤트마다 파일이 두 개씩 생겨 손해가 더 크다. 기본 matcher 로
되돌리려면 껐다가 다시 켜면 된다.

### 끄기

메뉴에서 `알림 연동` 을 다시 누르면 된다 — `settings.json` 에서 **우리 command 를 가진 훅만**
빼고, 그 때문에 비게 된 항목·이벤트 키도 정리한다. 다른 훅과 한 그룹에 섞여 있으면 우리 훅만
빠지고 나머지는 그대로 남는다. 스크립트 파일과 이벤트 디렉터리는 지우지 않으므로, 지우고
싶으면 위 두 경로를 직접 지운다.

직접 손으로 되돌리려면 `settings.json` 의 네 이벤트에서 `claude-cats-hook.sh` 가 든 항목을
지우거나, 백업(`settings.json.claude-cats.bak`)을 되돌리면 된다.

### 서식 주의

앱은 `settings.json` 을 JSON 으로 읽고 다시 쓴다. **내용(의미)은 그대로지만 서식은 다시
짜진다** — 최상위 키가 알파벳 순으로 정렬되고, 들여쓰기는 2칸이 되며, 주석 없는 순수 JSON 이
된다(원래도 JSON 이므로 주석은 애초에 못 쓴다). 값·배열 순서·중첩 구조는 바뀌지 않는다.
설정 파일을 손으로 예쁘게 관리하고 있다면 이 점만 알고 켜면 된다. 파일이 JSON 으로 안 읽히면
앱은 **아무것도 고치지 않고** 경고창만 띄운다.

바뀔 게 없으면 아예 쓰지 않는다(이미 켜져 있는데 또 켜거나, 안 켜져 있는데 끄는 경우).
끄기인데 `settings.json` 이 없으면 만들지도 않는다.

`settings.json` 이 **심볼릭 링크**(dotfiles 저장소로 링크를 건 경우)여도 안전하다 — 링크를
따라간 실제 파일에 쓰므로 링크가 죽지 않는다. 아직 **대상이 없는 링크**면 대상을 만들어 준다
(필요하면 그 디렉터리까지).

쓰기는 임시 파일을 만들어 바꿔치기하는 방식(atomic)이다. 그래서 **파일 inode 가 새로 생긴다** —
POSIX 권한은 읽어 뒀다가 되돌리지만 **ACL·확장 속성(xattr)·하드 링크는 따라오지 않는다**.
`settings.json` 에 ACL 을 걸었거나 하드 링크로 공유하고 있다면 알림 연동을 켜기 전에 확인하자
(심볼릭 링크는 위처럼 안전하다).
백업(`settings.json.claude-cats.bak`)은 **그 자리가 비어 있을 때만** 만든다. 앱을 다시 켤
때마다 덮어쓰면 두 번째 실행에서 "이미 훅이 든 파일"이 백업 자리에 들어가 원본이 사라진다.

## 동작 원리

`~/.claude/sessions/*.json` 을 3초마다 stat 폴링(내용은 mtime 이 바뀐 파일만 파싱)해서 살아있는
interactive 세션마다 고양이 한 마리를 배치한다. busy 세션의
`~/.claude/projects/<cwd>/<sessionId>/subagents/*.jsonl` mtime 이 15초 이내면 새끼 고양이로
표시한다. 모든 세션(idle 포함)의 transcript 끝에서 최근 `ai-title` 을 읽어 고양이 위 말풍선으로도
보여준다. idle 세션은 transcript mtime 이 더 이상 바뀌지 않으므로 다시 읽지 않는다(매 틱 `stat` 만).
화면 잠금/슬립 시 정지, 배터리/저전력 시 10초 폴링 + 애니메이션 끔.

창은 선택한 디스플레이(기본값은 원점을 포함한 주 디스플레이 `NSScreen.screens.first`) 전체를
덮는다. `NSScreen.main` 은 키보드 포커스가 있는 화면이라 쓰지 않는다 — 포커스를 따라 고양이가
옮겨다닌다. 디스플레이 구성이 바뀌면(`didChangeScreenParameters`) 창을 다시 맞추고 배치를
새 화면 크기로 다시 계산한다.

창은 `visibleFrame`(메뉴바·Dock 을 뺀 영역)이 아니라 `frame`(화면 전체)을 덮는다 — 바탕화면
레이어라 좌표계가 흔들리지 않는 편이 낫고, Dock 이 숨었다 나타날 때마다 창을 다시 잡지 않아도
된다. 대신 **배치**를 Dock 위로 올린다: `LayoutInsets.bottomInset(frame:visibleFrame:base:)`
이 `visibleFrame.minY − frame.minY`(하단 Dock 이 먹은 높이, 없으면 0)에 기본 여백
`SceneConfig.bottomInset`(40pt)을 더해 `Scene.layout` 에 넘긴다. Dock 이 좌·우에 있거나
자동 숨김이면 두 `minY` 가 같아 40pt 그대로다. Dock 크기·위치·자동 숨김을 바꾸면 macOS 가
`didChangeScreenParameters` 를 보내고, 거기서 `refitToScreen()` 이 여백을 다시 잰다.

## 문제가 생겼을 때

이 앱은 Claude Code 의 **문서화되지 않은 내부 파일 구조**에 직접 기댄다 —
`~/.claude/sessions/*.json` 의 `pid`/`sessionId`/`kind`/`status`/`cwd`/`name`,
`~/.claude/projects/<cwd>/<sessionId>/subagents/*.jsonl` 의 mtime, transcript 끝의
`ai-title` 줄. 전부 공개 API 가 아니라서 Claude Code 업데이트로 조용히 깨질 수 있다.

그래서 매 틱 세션 파일을 몇 개 봤고 몇 개를 받아들였는지, 못 받아들인 건 왜인지
(`unreadable` / `malformed` / `nonInteractive` / `deadPid`) 세서, 문제가 있을 때만
메뉴바 요약 아래에 한 줄이 더 붙는다.

| 메뉴 줄 | 뜻 | 볼 곳 |
| --- | --- | --- |
| (없음) | 정상 | — |
| `⚠️ 세션 파일 N개를 읽지 못함 — Claude Code 구조가 바뀌었을 수 있음` | 파일은 N개 있는데 **하나도** 못 받아들였고 그 이유가 읽기·파싱 실패다. `sessions/*.json` 스키마가 바뀌었을 가능성이 크다 | `ls ~/.claude/sessions` 로 파일이 있는지, 그 JSON 에 `sessionId`·`kind`·`pid` 가 그대로 있는지 |
| `⚠️ 세션 파일 M개 읽기 실패` | 일부는 읽었는데 M개는 못 읽었다(권한·경합·깨진 파일) | 아래 로그 |

`kind` 가 `interactive` 가 아닌 파일과 프로세스가 이미 죽은 세션 파일은 정상이라
경고에 세지 않는다. 남은 파일이 **전부** 그 둘이라 고양이가 0마리여도 아무 줄도 안 뜬다 —
그게 맞는 상황이고, 늘 떠 있는 경고는 아무도 안 읽는다. 읽기·파싱 실패가 하나라도
섞여야 경고가 나온다.

자세한 경로는 통합 로그에 남는다:

```bash
log stream --predicate 'subsystem == "claude-cats"' --level info
```

## 직접 그린 SVG 넣는 법

파이프라인은 두 단계다.

```
Design/cats/source/<컨셉>-<포즈>-figma.svg  ← Figma 에서 내보낸 원본(사람이 관리하는 유일한 그림)
  └ scripts/import-cat-svg.py               ← 껍데기 벗기기 · 64 상자 맞추기 · 털색 치환
Design/cats/<포즈>.svg | kenji-<포즈>.svg    ← 생성물. 손으로 고치지 말 것
  └ scripts/svg2swift.py                    ← 경로 데이터로 변환
Sources/ClaudeCats/CatArt.generated.swift                 ← 생성물. 커밋은 한다
Sources/ClaudeCats/CatArt.<컨셉>.<포즈>.generated.swift    ← 생성물. 커밋은 한다 (컨셉·포즈마다 하나)
```

기본 컨셉(팀 = 푹신캣)의 원본은 `<포즈>-figma.svg`(접두어 없음), 켄지(동글캣)는
`kenji-<포즈>-figma.svg` 다. 런타임에 SVG 를 파싱하지 않으므로 그림을 바꾸면 스크립트를 다시
돌려야 한다.

### 생성 파일

| 파일 | 내용 |
| --- | --- |
| `CatArt.generated.swift` | `CatArtColor` · `CatArtLayer` · `CatArtSet` 타입과, 컨셉별 `CatArtSet`(`CatArt.team`/`CatArt.kenji`) · `CatArt.set(_:)` 스위치. 좌표는 한 개도 없다. 꼬리 프레임이나 `alert` 원본이 없는 컨셉은 여기서 빈 배열·sitting 폴백으로 채운다 |
| `CatArt.<컨셉>.<포즈>.generated.swift` | 그 컨셉·포즈의 `<컨셉><포즈>Top` · `<컨셉><포즈>TailAboveBody` · `<컨셉><포즈>Body/TailA/TailB` 와 경로 데이터 |

컨셉(고양이 종류)은 `CatConcept`(Core) 로 정하고 `UserDefaults` 의 `catConcept` 에 저장한다.
`CatArtSet.recolorable` 이 true 인 컨셉만 팔레트로 색을 입힌다(두 컨셉 다 true — 향후 색이
완전히 고정인 컨셉을 위해 필드는 남겨 둔다).

**경로는 코드가 아니라 데이터로 싣는다.** 예전에는 `p.addCurve(to:control1:control2:)`
문장을 도형마다 수천 개 펼쳤는데, 타입체커가 그 호출식을 전부 씹느라
`swift build` 가 **208초**나 걸렸다([issue #4]). 지금은 경로 하나를
`[명령코드, 좌표...]` 가 이어 붙은 평평한 `[Float]` 리터럴 하나로 내보내고,
런타임이 `ClaudeCatsCore.PathData.build` 로 처음 쓸 때 한 번 `CGPath` 로 편다.

| 명령코드 | 명령 | 뒤따르는 좌표 |
| --- | --- | --- |
| 0 | move | x, y |
| 1 | line | x, y |
| 2 | cubic | c1x, c1y, c2x, c2y, x, y |
| 3 | close | (없음) |

issue #4 는 세 방향을 적어 뒀다 — ① 좌표 정밀도를 1자리로 줄이기 ② 경로를
데이터로 내보내기 ③ 포즈별로 파일 쪼개기. **②와 ③을 같이 골랐다.**
①은 64pt 상자에서 눈에 보이는 손실이라 뺐다(2자리는 2x 화면의 0.02px 이고,
1자리면 0.2px 라 곡선이 각진다). 결과는 아래와 같다.

| | 전 | 후 |
| --- | --- | --- |
| 콜드 `swift build` (debug) | 207.9초 | 19.2초 |
| 증분(debug): `CatArt.sitting.generated.swift` 만 고쳤을 때 | 207.0초 | 1.8초 |
| 생성물 크기 합계 | 1,480,679 B (1 파일) | 522,328 B (4 파일) |
| 런타임 비용 | 0 | 세 포즈 전부 디코드해도 0.18 ms(한 번) |

②만으로도 컴파일 부담은 사라지지만, ③이 있어야 포즈 하나를 고쳤을 때 나머지
두 포즈가 다시 컴파일되지 않는다. 좌표는 그대로 소수 2자리이고, 한 줄에 명령
하나씩 찍어서 그림을 고쳤을 때 diff 가 명령 단위로 남는다.

증분 이득은 **debug 에만** 해당한다 — `swift build -c release` 는 모듈 전체를 한
번에 최적화(WMO)하므로 어느 파일을 고치든 `ClaudeCats` 모듈이 통째로 다시
컴파일된다. 포즈별 분리가 release 증분 빌드를 빠르게 해 주지는 않는다 — 어느
파일을 고쳐도 5.5초로 같다. release 가 빨라진 건 순전히 ②데이터화 덕이다
(콜드 14.5초).

메모리는 좌표 74,758개 × 4바이트 ≈ **292KB** 다. 포즈를 처음 쓸 때 그 포즈 것만
올라오고, `CGPath` 로 편 뒤에도 원본 `[Float]` 은 전역이라 그대로 남는다.
64pt 상자에 세 포즈뿐이라 지금은 문제가 아니지만, 포즈가 훨씬 늘면 그때는
디코드 후 배열을 놓아주는 구조를 생각해야 한다.

[issue #4]: https://github.com/claud-park/claude-cats/issues/4

### 권장 흐름 (Figma)

1. Figma 에서 고양이를 그린다. 꼬리는 **프레임 이름을 `tail-a`** 로 둔다. 흔드는 두 번째
   프레임을 직접 그렸다면 그 이름은 `tail-b` 다(`<path>` 든 `<g>` 든 상관없다).
2. Export SVG 에서 **"Include id attribute"** 를 켠다(이게 꺼져 있으면 꼬리를 못 찾는다).
3. 파일을 `Design/cats/source/sitting-figma.svg` / `sleeping-figma.svg` /
   `alert-figma.svg` 로 떨군다.
4. 아래를 돌린다.

```bash
scripts/generate-cat-art.sh                       # import + 생성 + swift build
python3 -m unittest scripts/test_import_cat_svg.py scripts/test_svg2swift.py
```

털색 세 가지(`FUR` / `FUR_DARK` / `FUR_LIGHT`)의 **정본은 `scripts/generate-cat-art.sh`**
맨 위에 있다. Figma 파일의 색을 바꾸면 거기만 고치면 된다.

`alert.svg` 는 아직 없어도 된다 — 그러면 그 컨셉의 `CatArtSet` 이 `alert*` 자리에 앉은 자세를
그대로 쓴다(폴백). 그래서 런타임(`CatLayer`)이 참조하는 아트가 항상 존재한다.

### 고양이 종류(컨셉) 추가하기

새 종류를 더하려면:

1. Figma 원본을 `Design/cats/source/<컨셉>-sitting-figma.svg` /
   `<컨셉>-sleeping-figma.svg`(꼬리·alert 가 있으면 그 원본도)로 떨군다.
2. `scripts/generate-cat-art.sh` 에 그 컨셉의 import 줄과 `svg2swift` 입력
   (`<컨셉>:<포즈>=<svg>`)을 더한다. 색이 팔레트로 바뀌길 원하면 몸통색을 `--fur`(음영은
   `--fur-dark`, 하이라이트는 `--fur-light`)로 넘겨 플레이스홀더로 치환하고, 색을 그대로
   두려면 `--fur*` 를 생략한다.
3. `Sources/ClaudeCatsCore/CatConcept.swift` 의 `enum CatConcept` 에 case 를 더하고
   `title`(메뉴 표기)을 정한다. 그러면 `CatArt.set(_:)` 스위치가 exhaustive 하지 않아
   컴파일이 막히므로, 생성기(2번)를 돌려 그 컨셉의 `CatArtSet` 을 만들면 맞아 떨어진다.
4. rawValue(case 이름)는 `UserDefaults`·소스/생성 파일 이름과 묶이므로 한 번 정하면 바꾸지
   않는다.

`generate-cat-art.sh` 는 `Design/cats/source/<포즈>-figma.svg` 가 있을 때만 import 를 돌린다.
원본 없이 `Design/cats/*.svg` 를 손으로 그려 쓰는 예전 방식도 되지만, 그때
`sitting.svg` 에는 `<g id="tail-a">` 와 `<g id="tail-b">` 가 **반드시** 있어야 한다 —
런타임(`CatLayer`)이 `CatArt.sittingTailA` / `sittingTailB` / `sittingTailAboveBody` 를
참조하므로, 없으면 생성된 Swift 가 컴파일되지 않는다.

### import-cat-svg.py 가 하는 일

| 단계 | 내용 |
| --- | --- |
| 껍데기 벗기기 | `<defs>`, viewBox 전체를 덮는 배경 `<rect>`, viewBox 전체를 덮는 `<clipPath>` 를 건 `<g>` 를 벗긴다. 그 밖의 클립·마스크·그라디언트·텍스트·이미지는 이름을 찍고 **중단**한다 |
| 꼬리 뽑기 | `tail-a` / `tail-b` id 를 가진 요소를 꼬리 프레임으로 뽑는다. id 가 없으면 `--tail-paths 12,13,14`(1-based path 순번). 둘 다 없으면 중단 |
| 두 번째 프레임 | 원본에 `tail-b` 가 있으면 **그대로 쓴다**. `tail-a` 만 있으면 꼬리 밑동(bbox 의 minX·maxY)을 축으로 `--tail-angle`(기본 −8°) 만큼 돌린 프레임을 만든다 |
| 상자 맞추기 | 그림 전체 bbox 를 64×64 상자에 균일 스케일로 맞춘다. `scale = (64 − 2·pad) / max(폭, 높이)`, 가로는 가운데, 세로는 **바닥 정렬**(고양이가 바닥에 선다). `--pad` 기본 2 |
| 색 치환 | `--fur` / `--fur-dark` / `--fur-light` 로 **준 색만** `#FUR` / `#FURDARK` / `#FURLIGHT` 로 바꾼다(대소문자·3자리 축약 무시). 셋 다 생략하면 색을 그대로 둔다 — 그 컨셉은 색이 안 바뀌는(`recolorable == false`) 고양이가 된다 |
| stroke 정리 | 아래 표 참고 |

자는 자세는 런타임에 꼬리 토글이 없다. 그래서 `tail-a` 는 문서 순서 그대로 몸통에 접고
`tail-b` 는 버린다(있어도 에러는 아니고 그냥 쓰이지 않는다).

#### stroke 정리 규칙

Figma 는 한 도형의 fill 과 stroke 를 **자리가 같은 `<path>` 두 벌**로 내보낸다
(fill 조각 여러 개 + stroke 하나인 경우도 있다). 그래서 stroke 는 세 갈래로 나눈다.

| 경우 | 처리 |
| --- | --- |
| 한 `<path>` 에 같은 색 `fill` 과 `stroke` 가 같이 있다 | stroke 를 버린다 |
| stroke 만 있는데 같은 색 fill 도형과 자리(bbox)가 같다 | 이미 칠해져 있으니 그 도형을 통째로 버린다 |
| stroke 만 있는데 **다른 색** 도형과 자리가 같다 (눈 테두리 등) | 선으로 남긴다 |
| 남은 stroke 전부 (외곽선 · 수염 · 입 · 바닥선) | 축소 후 두께가 최소 0.6pt 가 되게 키운다 — 안 그러면 64pt 상자에서 사라진다 |

"자리가 같다"는 판정은 bbox 가 **도형 크기의 25%(최대 0.5) 안에서** 일치하고 path 명령
개수도 비슷할 때만 한다(작은 도형은 개수가 정확히 같아야 한다). 그래도 미심쩍으면
`--keep-stroke-twins` 로 이 정리를 통째로 끄고 비교해 보면 된다. 버린 stroke 는 하나씩
stderr 에 찍는다(`path 번호`, 색, bbox, `d` 앞 40자).

### 파일 규약

| 파일 | 쓰임 |
| --- | --- |
| `Design/cats/source/*-figma.svg` | 원본. 여기만 사람이 고친다 |
| `Design/cats/sitting.svg` | busy 포즈(생성물). `<g id="tail-a">`, `<g id="tail-b">` 는 1초마다 번갈아 보이는 꼬리 두 프레임, 그 외 전부 몸통 |
| `Design/cats/sleeping.svg` | idle 포즈(생성물). 꼬리를 포함해 전부 몸통(정지 그림) |
| `Design/cats/alert.svg` | 사용자 입력을 기다릴 때 쓰는 세 번째 포즈(생성물). 꼬리 처리는 `sitting.svg` 와 같다 |

- `viewBox` 는 필수다. `viewBox="0 0 64 64"` 를 권한다. 다른 크기를 주면 64×64 상자에
  균일 비율로 맞춰 가운데 정렬한다(선 두께도 같이 스케일된다).
- 좌표계는 변환기가 AppKit 방향(y 위로)으로 뒤집어 준다. SVG 는 평소대로 y 아래로 그린다.
- 문서 순서가 그대로 그리는 순서다(뒤에 오는 것이 위에 덮인다).
- 꼬리도 **문서 순서를 따른다**. `tail-a` 가 몸통보다 뒤에 있으면 꼬리를 몸통 위에 얹고,
  앞에 있으면 뒤에 깐다. 변환기가 `CatArt.sittingTailAboveBody` 로 내보내고 런타임이
  꼬리 그릇 레이어 순서를 거기에 맞춘다.
- 말풍선 꼭지 높이도 그림에서 잰다 — 변환기가 `CatArt.sittingTop` / `sleepingTop` / `alertTop`
  (그림 꼭대기 y)을 내보내고, 런타임은 그 2pt 위에 꼭지를 둔다.

### 색

| 값 | 뜻 |
| --- | --- |
| `#FUR` | 세션마다 다른 털색. 런타임 팔레트(`CatShapes.palette`) 에서 받는다 |
| `#FURDARK` | 같은 팔레트의 어두운 털색(귀 안쪽·목덜미 그림자 등) |
| `#FURLIGHT` | 같은 팔레트의 밝은 털색(하이라이트) |
| `#rgb` `#rgba` `#rrggbb` `#rrggbbaa`, 기본 색 이름 | 고정색. 흰 패치·눈·코·수염처럼 털색과 무관한 부분에 쓴다 |
| `none` | 칠하지 않음 |

`#FUR` 이 **주 털색**이고 나머지 둘은 거기서 파생된 톤이다 — `#FURDARK`(약 15% 어둡게)와
`#FURLIGHT`(흰색 쪽으로 약 27%)는 **선택 사항**이다. 안 써도 되고, 쓰면 팔레트를 바꿔도
명도 관계가 그대로 유지된다(`CatShapes.palette` 의 8쌍이 모두 이 관계로 만들어져 있다).
지금 원본 기준으로 `#FURLIGHT` 는 앉은 자세에서 한 군데 쓰이고, **`#FURDARK` 는 두 포즈
어디에도 쓰이지 않는다**(사용자가 마지막 내보내기에서 뺐다). 팔레트는 세 색을 다 지원하므로
다음 내보내기에서 다시 쓰면 그대로 살아난다. 세 색의 실제 값은
`scripts/generate-cat-art.sh` 에 있다.

털색은 팔레트를 갈아끼워도 경로를 다시 만들지 않고 색만 바꾼다. 그래서 `#FUR` 을 쓴
도형에는 `fill-opacity` / `stroke-opacity` 대신 `opacity` 를 쓰는 편이 결과가 깔끔하다.

### 지원 범위

- 요소: `g`(중첩 가능), `path`, `ellipse`, `circle`, `rect`, `line`, `polygon`, `polyline`
- 속성: `fill`, `fill-rule`(`nonzero` / `evenodd`), `stroke`, `stroke-width`,
  `stroke-linecap`, `stroke-linejoin`(기본 `round`), `opacity`, `fill-opacity`,
  `stroke-opacity`, `transform`(`translate` / `scale` / `rotate` / `matrix` / `skewX` / `skewY`,
  그룹에서 상속·합성), 인라인 `style="fill:...;stroke:..."`
- `path` 의 `d`: `M/m L/l H/h V/v C/c S/s Q/q T/t A/a Z/z` 전부. 호(`A`)는 90° 이하 조각의
  3차 베지어로 근사한다.
- 숫자 값은 사용자 단위와 `px` 만 받는다(`em`·`pt` 등은 에러). `opacity`·`fill-opacity`·
  `stroke-opacity` 는 `0.5` 와 `50%` 둘 다 된다.
- 그라디언트·필터·텍스트·이미지·`use` 등은 변환할 수 없다. `clip-path` / `mask` / `filter`
  **속성**(인라인 `style` 포함)도 마찬가지다 — 조용히 무시하면 그림이 달라지므로 요소 이름과
  속성 이름을 찍고 중단한다. Figma·Illustrator 에서 내보낼 때 "윤곽선으로 만들기 / flatten"
  을 먼저 하면 된다.

인접한 도형이 같은 스타일(fill·stroke·선 두께·캡·불투명도)이면 한 레이어로 합쳐 레이어 수를 줄인다.
합친 결과는 `CAShapeLayer` 기본 채우기 규칙인 **nonZero** 로 칠해지므로, 같은 스타일의 도형 안에
반대 방향으로 감긴 도형을 겹쳐 두면 원본 SVG 에서는 둘로 보이던 것이 구멍으로 뚫려 보인다.
구멍을 의도했다면 그대로 두고, 아니라면 두 도형의 스타일을 다르게 하거나 사이에 다른 스타일의
도형을 끼워 병합을 끊는다.

### 팔레트 바꾸기

털색 8쌍(`fur` / `furDark` / `furLight`)은 `Sources/ClaudeCats/CatShapes.swift` 의
`palette` 에 있다. 0번이 원본 그림의 색이고 나머지 7쌍은 같은 명도 관계로 만들었다.
세션 이름 해시로 `paletteIndex % 8` 을 고르므로 쌍 개수를 바꾸면 `SceneConfig.paletteSize`
도 같이 맞춘다.
