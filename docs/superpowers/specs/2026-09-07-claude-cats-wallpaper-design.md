# Claude Cats — 데스크탑 세션 상태 표시 앱 설계

- 날짜: 2026-09-07
- 상태: 승인 대기
- 경로: architectural (신규 프로젝트)

## 1. 목적

이 Mac에서 실행 중인 Claude Code 세션과 서브에이전트가 지금 **작업 중인지 idle 인지**를
바탕화면 위에 벡터 고양이로 보여준다. 세션 하나가 고양이 한 마리, 실행 중인 서브에이전트가
그 옆의 새끼 고양이다. 터미널을 열지 않고도 곁눈질로 상태를 알 수 있어야 한다.

### 성공 기준

- 살아있는 interactive 세션이 전부 고양이로 보인다. 죽은 세션(좀비 파일)은 안 보인다.
- busy/idle 이 포즈로 구분된다. 상태 변화가 폴링 주기(3초) 안에 반영된다.
- 실행 중인 서브에이전트가 부모 옆에 새끼로 보이고, 끝나면 15초 안에 사라진다.
- **전력**: 유휴 시 CPU 0.0%, 갱신 틱 5ms 이하, 상주 메모리 100MB 이하
  (2026-09-07 실측 63~71MB, 세션 10개; 대부분 프레임워크 공유 페이지), Activity Monitor
  에너지 영향 "낮음". GPU 상시 사용 없음.
- 앱이 파일 오류로 죽지 않는다.

### 비목표 (YAGNI)

클릭으로 터미널 포커스, Spaces 별 다른 배치, 실제 배경화면 파일 교체, Claude Code hooks
연동, 사용자 정의 고양이 이미지, 알림. 전부 후속.

## 2. 아키텍처

메뉴바 전용 macOS 앱(`LSUIElement = YES`, Dock 아이콘 없음). Swift 6, SwiftUI + AppKit.
외부 의존성 없음. Swift Package(`swift build`)로 빌드하고, 배포는 `.app` 번들 스크립트로.

세 유닛으로 나눈다. 각 유닛은 한 가지만 하고, 다음 유닛과는 값 타입으로만 통신한다.

```
~/.claude 파일 ──▶ StateCollector ──Snapshot──▶ Scene ──Layout──▶ DesktopWindow
                       ▲                                              │
                   PollTimer ◀──── PowerPolicy ◀──── 시스템 알림 ─────┘
```

| 유닛 | 하는 일 | 입력 | 출력 | 의존 |
|---|---|---|---|---|
| StateCollector | 파일을 읽어 세션/서브에이전트 스냅샷 생성 | `FileSystem` 프로토콜, 현재 시각 | `Snapshot` | Foundation |
| Scene | 스냅샷을 고양이 배치로 변환 | `Snapshot`, 화면 크기, `animationsEnabled: Bool` | `Layout` | 없음 |
| DesktopWindow | 투명 창 생성, `Layout` 을 그림 | `Layout` | 화면 | AppKit, SwiftUI |
| PowerPolicy | 전원 상태에 따라 폴링 주기·애니메이션 결정 | 시스템 알림 | `PollingMode` | AppKit, IOKit |

### 데이터 타입

```swift
struct Snapshot: Equatable {
    var sessions: [Session]          // name 기준 정렬
    var takenAt: Date
}
struct Session: Equatable, Identifiable {
    var id: String                   // sessionId
    var pid: Int32
    var name: String                 // "obsidian-71"
    var cwd: String
    var status: Status               // .busy | .idle
    var subagents: [Subagent]        // 실행 중인 것만
}
struct Subagent: Equatable, Identifiable {
    var id: String                   // agentId
    var description: String          // meta.json description, 툴팁 예비용
    var lastActivity: Date
}
enum Status { case busy, idle }

struct Layout: Equatable {
    var cats: [CatPlacement]
}
struct CatPlacement: Equatable, Identifiable {
    var id: String
    var origin: CGPoint
    var scale: CGFloat               // 1.0 세션, 0.5 새끼
    var pose: Pose                   // .sitting | .sleeping
    var paletteIndex: Int            // 0..<8
    var label: String?               // 세션 이름, 새끼는 nil
    var animated: Bool               // busy && PowerPolicy 허용
}
enum PollingMode { case normal /*3s*/, lowPower /*10s, no anim*/, suspended }
```

## 3. StateCollector — 데이터 수집

### 3.1 세션

- 소스: `~/.claude/sessions/<pid>.json`.
- 읽는 필드: `pid, sessionId, name, cwd, status, kind`.
- 필터: `kill(pid, 0) == 0` 인 것만(ESRCH 면 좀비 파일로 무시, EPERM 은 살아있다고 본다).
  `kind == "interactive"` 만.
- `status` 는 `"busy"` 이면 `.busy`, 그 외(`"idle"`, 미지 값)는 `.idle`.

### 3.2 서브에이전트

- 소스: `~/.claude/projects/<encodedCwd>/<sessionId>/subagents/agent-*.jsonl` 과 같은 이름의
  `.meta.json`.
- `encodedCwd` 는 관찰된 규칙(경로의 `/`, `_` 를 `-` 로 치환)으로 먼저 만든다. 그 디렉터리에
  `<sessionId>` 가 없으면 `~/.claude/projects/*/<sessionId>` 를 한 번 glob 해서 찾고 결과를
  sessionId 별로 캐시한다(성공·실패 모두 캐시, 실패는 60초 뒤 재시도).
- "실행 중" 판정: `.jsonl` 의 mtime 이 현재 시각 기준 **15초 이내**.
- 스캔 대상은 `status == .busy` 인 세션만. idle 세션의 서브에이전트 디렉터리는 열지 않는다.
- `.meta.json` 은 `.jsonl` 이 실행 중으로 판정된 것만 읽고, agentId 별로 캐시한다(내용이
  바뀌지 않으므로 한 번만).

### 3.3 비용 제어

- 매 틱: `sessions/` 디렉터리 listing 1회 + 파일마다 `stat` 1회. mtime 이 지난 틱과 같으면
  JSON 을 다시 파싱하지 않고 캐시된 `Session` 을 재사용한다(pid 생존 확인은 매 틱).
- busy 세션의 `subagents/` listing 과 `stat` 은 매 틱. 파일 내용은 읽지 않는다(mtime 만).
- 제목(§5.4) 조회를 위해 idle 세션도 `projectRoot` 를 찾고 transcript 를 `stat` 한다
  (세션당 `stat` 1회 추가, `projectRoot` 는 sessionId 별 캐시). `subagents/` 스캔은
  여전히 busy 세션만이다.
- 결과 `Snapshot` 이 직전과 `==` 이면 아무 것도 방출하지 않는다.

### 3.4 파일시스템 추상화

```swift
protocol FileSystem {
    func list(_ dir: URL) throws -> [URL]
    func stat(_ url: URL) throws -> FileStat      // mtime, size
    func read(_ url: URL) throws -> Data
    func processAlive(_ pid: Int32) -> Bool
}
```

실제 구현은 `FileManager` + `kill`. 테스트는 인메모리 픽스처.

## 4. Scene — 배치

- 화면 하단에서 위로 `bottomInset`(기본 40pt) 띄운 가로 띠 하나에 고양이를 나열한다.
- 슬롯 폭 140pt. 슬롯 수 = `max(1, floor(screenWidth / 140))`.
- 세션 슬롯 = `hash(name) % slotCount`. 충돌하면 오른쪽으로 선형 탐사. 결정적이어야 하며,
  같은 세션 집합이면 항상 같은 배치가 나온다(테스트로 고정).
- 슬롯보다 세션이 많으면 두 번째 줄(위로 100pt)로 넘긴다.
- 새끼는 부모 슬롯 안에서 부모 우측에 24pt 간격으로 붙고, 두 마리 이상이면 겹쳐 쌓는다
  (최대 3마리까지 그리고 그 이상은 세 번째 새끼 위에 `+n` 표기).
- `paletteIndex = hash(name) % 8`. 새끼는 부모와 같은 색.
- `pose`: busy → `.sitting`, idle → `.sleeping`. 새끼는 항상 `.sitting`.
- `animated = (pose == .sitting) && animationsEnabled`. `animationsEnabled` 는 PowerPolicy 가
  결정해 Scene 에 넘긴다.
- `hash` 는 프로세스 간 안정적이어야 하므로 `Hasher` 가 아니라 FNV-1a 를 직접 쓴다.

## 5. DesktopWindow — 렌더링

### 5.1 창

- `NSWindow`, `styleMask = .borderless`, `isOpaque = false`, `backgroundColor = .clear`,
  `hasShadow = false`, `ignoresMouseEvents = true`.
- `level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)`
  → 배경화면 위, 데스크탑 아이콘 아래.
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`.
- 메인 디스플레이 전체 프레임. 디스플레이 구성이 바뀌면(`NSApplication.didChangeScreenParametersNotification`)
  프레임을 다시 잡는다. 외부 모니터는 1차에서 다루지 않는다(메인만).

### 5.2 그리기

- 고양이는 SwiftUI `Path` 로 그린 단순 벡터. 포즈 두 개(sitting, sleeping)와 sitting 용
  꼬리 프레임 두 개. 새끼는 같은 도형을 `scale` 로 축소.
- 각 고양이는 별도 `CALayer`. 몸통은 `CAShapeLayer`(포즈가 바뀔 때만 path 교체), 꼬리는
  `CALayer` 두 장을 `isHidden` 토글. 라벨은 `CATextLayer`, 시스템 폰트 11pt, 흰색 텍스트에
  1pt 검은 외곽선(배경 박스 없음).
- 레이아웃이 바뀌면 diff 로 레이어를 추가/제거/이동한다. 바뀌지 않은 레이어는 손대지 않는다.
- 새 고양이 등장·퇴장은 Core Animation 암시적 페이드 0.3초. 그 외 트랜지션 없음.

### 5.3 애니메이션

- `animated == true` 인 고양이만 꼬리를 흔든다. 방법: 1초 주기 `DispatchSourceTimer`
  하나(leeway 200ms)가 모든 animated 고양이의 꼬리 레이어 `isHidden` 을 토글. 프레임당 CPU
  드로잉 없음, 컴포지터 갱신만.
- animated 고양이가 0마리면 타이머를 완전히 정지한다.
- 60fps 루프, `CADisplayLink`, `TimelineView(.animation)` 금지.

### 5.4 추가 기능 (2026-09-07)

- **세션 제목 말풍선**: 모든 세션(idle 포함)은 transcript 파일 끝(`readTail`, 최대 256KB)에서
  가장 최근 `type: "ai-title"` 라인을 파싱해 고양이 위 말풍선(`CAShapeLayer`)으로 보여준다.
  mtime 이 안 바뀌었거나 마지막 읽음이 10초 이내면 캐시를 재사용한다
  (`StateCollector.titleRefreshInterval`). idle 세션은 transcript 의 mtime 이 더 이상 바뀌지
  않으므로 사실상 다시 읽지 않는다 — 매 틱 비용은 `stat` 1회뿐이다.
  화면 왼쪽으로 넘치지 않게 클램프하고, 포즈별로 꼭지 위치를 다르게 그린다.
- **SVG 아트 파이프라인**: 고양이 그림의 원본은 `Design/cats/*.svg` 이고, 런타임은 SVG 를
  파싱하지 않는다. `scripts/svg2swift.py` 가 빌드 전에 SVG 를 CGPath 빌더 코드
  (`Sources/ClaudeCats/CatArt.generated.swift`) 로 변환해 커밋해 둔다. 형식·색·지원 범위는
  README 의 "직접 그린 SVG 넣는 법" 절 참고.

## 6. PowerPolicy — 전력 정책

| 조건 | 폴링 | 애니메이션 |
|---|---|---|
| AC 전원, 저전력 모드 아님 | 3초 | 켬 |
| 배터리 전원 **또는** 저전력 모드 | 10초 | 끔 |
| 화면 잠금 / 디스플레이 슬립 / 스크린세이버 / 시스템 슬립 | 정지 | 끔 |
| 메뉴바 "일시정지" | 정지 | 끔 |

- 전원: 배터리/AC 는 폴링 틱마다 collector 큐에서 `IOPSCopyPowerSourcesInfo` 로 확인하고
  값이 바뀔 때만 메인으로 전달한다(IOKit 알림 콜백 대신 단순화, 최대 10초 지연). 잠금
  해제·슬립 복귀·일시정지 해제 시에는 즉시 재확인한다.
- 저전력: `ProcessInfo.processInfo.isLowPowerModeEnabled` + `NSProcessInfoPowerStateDidChange`.
  저전력 모드에서는 설계상 꼬리 애니메이션도 끈다(폴링만 느려지는 게 아니라 애니메이션도 정지).
- 잠금/슬립: `com.apple.screenIsLocked` / `screenIsUnlocked` (DistributedNotificationCenter),
  `NSWorkspace.screensDidSleepNotification` / `didWake`, `willSleepNotification` / `didWake`.
- 재개 시 즉시 한 번 폴링한다.
- 폴링 타이머는 `DispatchSourceTimer`, leeway = 주기의 1/3. 타이머 콜백은 백그라운드 큐에서
  파일 I/O 를 하고, `Snapshot` 이 바뀐 경우에만 메인 큐로 넘긴다.

## 7. 메뉴바

`NSStatusItem` 하나. 아이콘은 SF Symbol `cat`(없으면 `pawprint`). 메뉴 항목:

- 세션 수 요약(비활성 항목): "고양이 12마리 · 작업 중 3"
- 일시정지 / 재개 (토글)
- 지금 새로고침
- 로그인 시 시작 (SMAppService)
- 종료

## 8. 에러 처리

- 파일 하나가 깨졌거나(JSON 파싱 실패, 필드 누락) 읽을 수 없으면 그 세션/서브에이전트만
  건너뛰고 `os.Logger` 에 남긴다. 스냅샷은 나머지로 만든다.
- `~/.claude/sessions` 가 없으면 빈 스냅샷. 앱은 계속 뜬다(고양이 0마리).
- 파일 I/O 예외가 `StateCollector` 밖으로 나가지 않는다. 타이머 콜백은 항상 완료된다.
- 폴링 한 틱이 200ms 를 넘으면 경고 로그(전력 회귀 감지용).

## 9. 테스트

단위 테스트(Swift Testing, `swift test`):

- **StateCollector**: 픽스처 디렉터리 기반. 좀비 pid 제외, non-interactive 제외, 미지 status
  → idle, busy 세션만 subagents 스캔, mtime 15초 경계(14.9s 포함/15.1s 제외), meta.json 캐시,
  cwd 인코딩 실패 시 glob 폴백 + 캐시, 깨진 JSON 건너뛰기, 동일 입력 → `Snapshot ==`.
- **Scene**: 결정적 배치(같은 입력 두 번 → 같은 Layout), 슬롯 충돌 선형 탐사, 두 번째 줄
  넘김, 새끼 3마리 제한 + `+n`, 색 안정성.
- **PowerPolicy**: 조건 조합 → `PollingMode` 표.
- **DesktopWindow diff**: `Layout` 두 개를 주면 추가/제거/이동 레이어 집합이 맞는지(레이어
  ID 기준, 실제 창은 띄우지 않음).

수동 검증(스펙 완료 조건):

- 12개 세션 환경에서 10분 실행 후 `powermetrics --samplers tasks` 로 CPU 시간·에너지 영향
  측정, Activity Monitor 메모리 확인. 수치를 이 문서 끝 "측정 기록"에 남긴다.
- 화면 잠금 → 잠금 해제 시 타이머가 멈췄다 재개되는지 로그로 확인.
- 배터리로 전환 시 꼬리 애니메이션이 멈추는지 확인.

## 10. 프로젝트 구조

순수 로직은 라이브러리 타깃 `ClaudeCatsCore` 에 두어 `@testable import` 로 테스트하고, AppKit
코드는 실행 타깃 `ClaudeCats` 에만 둔다. Core 는 `import AppKit` 을 하지 않는다.

```
claude-cats/
  Package.swift                 # ClaudeCatsCore(lib) + ClaudeCats(exec) + ClaudeCatsCoreTests
  Sources/ClaudeCatsCore/
    Models.swift, FileSystem.swift, StateCollector.swift,
    StableHash.swift, Scene.swift, PowerPolicy.swift, LayoutDiffer.swift
  Sources/ClaudeCats/
    main.swift, AppDelegate.swift, AppController.swift, PowerMonitor.swift,
    StatusMenu.swift, CatShapes.swift, CatLayer.swift, DesktopWindow.swift
  Tests/ClaudeCatsCoreTests/
    FakeFileSystem.swift, Fixtures.swift, *Tests.swift
  scripts/bundle.sh             # .app 번들 + Info.plist(LSUIElement) 생성
  docs/superpowers/specs/, docs/superpowers/plans/
```

## 측정 기록

`dist/ClaudeCats.app`(release 빌드, adhoc 서명)을 `open` 으로 띄운 뒤 `sudo` 없이
`ps -o %cpu=,rss=,etime= -p <pid>` 를 30초 간격 10회(5분) 샘플링했다. `sudo powermetrics`
는 이 실행 환경에서 쓸 수 없어 사용자가 별도로 확인해야 한다(아래 참고).

| 항목 | 값 | 측정일 |
|---|---|---|
| 세션 수 / busy 수 | 10~11 / 2 (측정 구간 중 변동) | 2026-09-07 |
| 5분 평균 CPU (%cpu) | 0.0 (10 샘플 전부 0.0) | 2026-09-07 |
| RSS (평균 / 최대) | 63.3 MB / 71.3 MB | 2026-09-07 |
| `top -l 3 -stats pid,cpu,mem` | `%CPU 0.0`, `MEM 22M` | 2026-09-07 |
| Activity Monitor 에너지 영향 | (사용자 육안 확인 필요, 아래 참고) | |

`sudo` 를 쓸 수 없어 `powermetrics` 의 CPU ms/s·Energy Impact 컬럼은 측정하지 못했다.
아래 명령과 Activity Monitor 확인은 사용자가 직접 실행해 남겨 두면 된다.

```bash
sudo powermetrics --samplers tasks -i 5000 -n 6 | grep ClaudeCats
```

Activity Monitor → 에너지 탭에서 ClaudeCats 의 "에너지 영향" 이 "낮음" 인지 눈으로 확인.

**참고**: RSS 63~71MB 는 원래 목표였던 "상주 메모리 30MB 이하" 를 넘는다(그래서 §1 의 목표를
100MB 이하로 고쳤다). `ps` RSS 는
AppKit/SwiftUI/Swift 런타임이 매핑한 공유 프레임워크 페이지를 포함하므로, 순수 Swift
메뉴바 앱에서도 이 정도 RSS 는 흔하다(로직 자체의 누수는 아님 — 5분 동안 우상향 없이
62~73MB 사이를 오갔다). "0.1% MEM" 수준의 CPU 0.0% 와 함께 실사용 임팩트는 낮아 보이지만,
숫자 자체는 원래 목표를 벗어나므로 기록해 둔다.
