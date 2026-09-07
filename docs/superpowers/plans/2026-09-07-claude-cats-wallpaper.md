# Claude Cats Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 이 Mac의 Claude Code 세션(고양이)과 실행 중 서브에이전트(새끼 고양이)의 busy/idle 상태를 바탕화면 위·아이콘 아래 투명 창에 벡터로 그려주는 메뉴바 앱.

**Architecture:** `~/.claude` 파일을 3초 간격으로 `stat` 폴링해 `Snapshot` 을 만들고(StateCollector), 결정적 배치 `Layout` 으로 바꾼 뒤(Scene), `CALayer` diff 로 화면에 반영한다(DesktopWindow). 스냅샷이 같으면 아무 것도 그리지 않고, 전원 상태(PowerPolicy)에 따라 폴링 주기와 꼬리 애니메이션을 끈다.

**Tech Stack:** Swift 6.0 (swift-tools-version 6.0), macOS 14+, SwiftPM 패키지, AppKit + Core Animation, Swift Testing(`import Testing`). 외부 의존성 없음.

**Spec:** `docs/superpowers/specs/2026-09-07-claude-cats-wallpaper-design.md`

## Global Constraints

- 외부 패키지 의존성 0. `Package.swift` 의 `dependencies` 는 비어 있어야 한다.
- 순수 로직(`Collector`, `Scene`, `Power`, `LayoutDiffer`)은 `ClaudeCatsCore` 라이브러리 타깃. AppKit 을 쓰는 코드는 `ClaudeCats` 실행 타깃에만. Core 는 `import AppKit` 금지.
- 60fps 루프 금지: `CADisplayLink`, `TimelineView(.animation)`, `Timer` 1초 미만 주기 금지. 꼬리 애니메이션은 1초 주기 `DispatchSourceTimer` 하나.
- 폴링: 기본 3초, 저전력/배터리 10초, 잠금/슬립/일시정지 시 정지. leeway = 주기/3.
- 매 폴링 틱은 `stat` 만. mtime 이 바뀐 세션 파일만 JSON 재파싱. `subagents/` 는 busy 세션만 스캔. `.jsonl` 내용은 읽지 않는다.
- 서브에이전트 "실행 중" 판정: `.jsonl` mtime 이 현재 시각 기준 15초 이내(`<= 15`).
- 창: `hasShadow = false`, `ignoresMouseEvents = true`, level = desktopIconWindow − 1, `[.canJoinAllSpaces, .stationary, .ignoresCycle]`. 메인 디스플레이만.
- 앱은 `LSUIElement`(Dock 없음). 파일 오류로 죽지 않는다.
- 커밋 메시지 끝에 항상:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_017HYKXdeh9W7fUjTPkuXDn1
  ```
- 모든 명령은 저장소 루트 `~/Documents/flo/AX/claude-cats` 에서 실행한다.

---

## File Structure

```
Package.swift
Sources/ClaudeCatsCore/
  Models.swift          Status, Subagent, Session, Snapshot (+ 커스텀 ==)
  FileSystem.swift      FileStat, FileSystem 프로토콜, RealFileSystem
  StateCollector.swift  세션/서브에이전트 수집 + mtime 캐시
  StableHash.swift      FNV-1a
  Scene.swift           Pose, CatPlacement, Layout, SceneConfig, Scene.layout
  PowerPolicy.swift     PowerState, PollingMode, PowerPolicy.mode
  LayoutDiffer.swift    LayoutDiff, LayoutDiffer.diff
Sources/ClaudeCats/
  main.swift            NSApplication 부팅
  AppDelegate.swift     객체 조립, 화면 변경 알림
  AppController.swift   폴링 타이머 + Snapshot→Layout→창 반영
  PowerMonitor.swift    시스템 알림 → PowerState
  StatusMenu.swift      NSStatusItem 메뉴
  CatShapes.swift       CGPath 고양이 도형 + 팔레트
  CatLayer.swift        고양이 한 마리 = CALayer 트리
  DesktopWindow.swift   투명 창 + 레이어 diff 반영 + 꼬리 타이머
Tests/ClaudeCatsCoreTests/
  FakeFileSystem.swift  인메모리 FileSystem
  Fixtures.swift        JSON 문자열 생성 헬퍼
  ModelsTests.swift
  FakeFileSystemTests.swift
  StateCollectorSessionTests.swift
  StateCollectorSubagentTests.swift
  SceneTests.swift
  PowerPolicyTests.swift
  LayoutDifferTests.swift
scripts/bundle.sh
```

---

### Task 1: 패키지 스캐폴드 + 모델

**Files:**
- Create: `Package.swift`
- Create: `Sources/ClaudeCatsCore/Models.swift`
- Create: `Sources/ClaudeCats/main.swift` (빌드만 되는 최소 파일)
- Test: `Tests/ClaudeCatsCoreTests/ModelsTests.swift`

**Interfaces:**
- Produces: `Status`, `Subagent(id:description:lastActivity:)`, `Session(id:pid:name:cwd:status:subagents:)`, `Snapshot(sessions:takenAt:)`. `Snapshot ==` 는 `sessions` 만 비교(`takenAt` 무시). `Subagent ==` 는 `id`, `description` 만 비교(`lastActivity` 무시).

- [ ] **Step 1: Package.swift 작성**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeCats",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClaudeCatsCore"),
        .executableTarget(name: "ClaudeCats", dependencies: ["ClaudeCatsCore"]),
        .testTarget(name: "ClaudeCatsCoreTests", dependencies: ["ClaudeCatsCore"]),
    ]
)
```

- [ ] **Step 2: 최소 main.swift 작성**

`Sources/ClaudeCats/main.swift`:
```swift
import Foundation
import ClaudeCatsCore

print("claude-cats bootstrap")
```

- [ ] **Step 3: 실패하는 테스트 작성**

`Tests/ClaudeCatsCoreTests/ModelsTests.swift`:
```swift
import Testing
import Foundation
@testable import ClaudeCatsCore

@Suite struct ModelsTests {
    @Test func snapshotEqualityIgnoresTakenAt() {
        let s = Session(id: "a", pid: 1, name: "n", cwd: "/x", status: .busy, subagents: [])
        let a = Snapshot(sessions: [s], takenAt: Date(timeIntervalSince1970: 0))
        let b = Snapshot(sessions: [s], takenAt: Date(timeIntervalSince1970: 100))
        #expect(a == b)
    }

    @Test func snapshotEqualityComparesSessions() {
        let s1 = Session(id: "a", pid: 1, name: "n", cwd: "/x", status: .busy, subagents: [])
        var s2 = s1; s2.status = .idle
        #expect(Snapshot(sessions: [s1], takenAt: .now) != Snapshot(sessions: [s2], takenAt: .now))
    }

    @Test func subagentEqualityIgnoresLastActivity() {
        let a = Subagent(id: "x", description: "d", lastActivity: Date(timeIntervalSince1970: 0))
        let b = Subagent(id: "x", description: "d", lastActivity: Date(timeIntervalSince1970: 50))
        #expect(a == b)
        let c = Subagent(id: "y", description: "d", lastActivity: Date(timeIntervalSince1970: 0))
        #expect(a != c)
    }
}
```

- [ ] **Step 4: 실패 확인**

Run: `swift test 2>&1 | tail -20`
Expected: 컴파일 에러 — `cannot find 'Session' in scope`

- [ ] **Step 5: Models.swift 작성**

`Sources/ClaudeCatsCore/Models.swift`:
```swift
import Foundation

public enum Status: Sendable, Equatable {
    case busy
    case idle
}

public struct Subagent: Sendable, Identifiable {
    public var id: String
    public var description: String
    public var lastActivity: Date

    public init(id: String, description: String, lastActivity: Date) {
        self.id = id
        self.description = description
        self.lastActivity = lastActivity
    }
}

extension Subagent: Equatable {
    /// lastActivity 는 매 틱 바뀌므로 동등성에서 제외한다. 스냅샷 변경 감지용.
    public static func == (lhs: Subagent, rhs: Subagent) -> Bool {
        lhs.id == rhs.id && lhs.description == rhs.description
    }
}

public struct Session: Sendable, Equatable, Identifiable {
    public var id: String
    public var pid: Int32
    public var name: String
    public var cwd: String
    public var status: Status
    public var subagents: [Subagent]

    public init(id: String, pid: Int32, name: String, cwd: String, status: Status, subagents: [Subagent]) {
        self.id = id
        self.pid = pid
        self.name = name
        self.cwd = cwd
        self.status = status
        self.subagents = subagents
    }
}

public struct Snapshot: Sendable {
    public var sessions: [Session]
    public var takenAt: Date

    public init(sessions: [Session], takenAt: Date) {
        self.sessions = sessions
        self.takenAt = takenAt
    }
}

extension Snapshot: Equatable {
    /// takenAt 은 매 틱 바뀌므로 제외. 같으면 다시 그리지 않는다.
    public static func == (lhs: Snapshot, rhs: Snapshot) -> Bool {
        lhs.sessions == rhs.sessions
    }
}
```

- [ ] **Step 6: 통과 확인**

Run: `swift test 2>&1 | tail -5`
Expected: `Test run with 3 tests passed`

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: 패키지 스캐폴드와 세션/스냅샷 모델"
```

---

### Task 2: FileSystem 추상화 + 인메모리 구현

**Files:**
- Create: `Sources/ClaudeCatsCore/FileSystem.swift`
- Create: `Tests/ClaudeCatsCoreTests/FakeFileSystem.swift`
- Test: `Tests/ClaudeCatsCoreTests/FakeFileSystemTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct FileStat: Sendable, Equatable { public var modified: Date; public var size: Int }
  public protocol FileSystem: Sendable {
      func list(_ dir: URL) throws -> [URL]      // 직계 자식만, 숨김 파일 제외
      func stat(_ url: URL) throws -> FileStat   // 파일·디렉터리 모두, 없으면 throw
      func read(_ url: URL) throws -> Data
      func processAlive(_ pid: Int32) -> Bool
  }
  public struct RealFileSystem: FileSystem
  ```
  테스트용 `FakeFileSystem`: `add(path, text, modified:)`, `alivePids: Set<Int32>`, `readCount: [String: Int]`, `remove(path)`.

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/ClaudeCatsCoreTests/FakeFileSystemTests.swift`:
```swift
import Testing
import Foundation
@testable import ClaudeCatsCore

@Suite struct FakeFileSystemTests {
    @Test func listReturnsDirectChildrenOnly() throws {
        let fs = FakeFileSystem()
        fs.add("/root/a.json", "{}", modified: .now)
        fs.add("/root/sub/b.json", "{}", modified: .now)
        let names = try fs.list(URL(fileURLWithPath: "/root")).map(\.lastPathComponent)
        #expect(names == ["a.json", "sub"])
    }

    @Test func listMissingDirThrows() {
        let fs = FakeFileSystem()
        #expect(throws: (any Error).self) { try fs.list(URL(fileURLWithPath: "/nope")) }
    }

    @Test func statWorksForFilesAndDirectories() throws {
        let fs = FakeFileSystem()
        let t = Date(timeIntervalSince1970: 1000)
        fs.add("/root/sub/b.json", "{\"a\":1}", modified: t)
        #expect(try fs.stat(URL(fileURLWithPath: "/root/sub/b.json")) == FileStat(modified: t, size: 7))
        _ = try fs.stat(URL(fileURLWithPath: "/root/sub"))
        #expect(throws: (any Error).self) { try fs.stat(URL(fileURLWithPath: "/root/zzz")) }
    }

    @Test func readCountsReads() throws {
        let fs = FakeFileSystem()
        fs.add("/f", "hi", modified: .now)
        _ = try fs.read(URL(fileURLWithPath: "/f"))
        _ = try fs.read(URL(fileURLWithPath: "/f"))
        #expect(fs.readCount["/f"] == 2)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test 2>&1 | tail -20`
Expected: 컴파일 에러 — `cannot find 'FakeFileSystem' in scope`

- [ ] **Step 3: FileSystem.swift 작성**

`Sources/ClaudeCatsCore/FileSystem.swift`:
```swift
import Foundation

public struct FileStat: Sendable, Equatable {
    public var modified: Date
    public var size: Int

    public init(modified: Date, size: Int) {
        self.modified = modified
        self.size = size
    }
}

public protocol FileSystem: Sendable {
    /// 디렉터리의 직계 자식. 숨김 파일 제외. 디렉터리가 없으면 throw.
    func list(_ dir: URL) throws -> [URL]
    /// 파일·디렉터리 모두. 없으면 throw.
    func stat(_ url: URL) throws -> FileStat
    func read(_ url: URL) throws -> Data
    /// kill(pid, 0) 기준. EPERM 은 살아있는 것으로 본다.
    func processAlive(_ pid: Int32) -> Bool
}

public struct RealFileSystem: FileSystem {
    public init() {}

    public func list(_ dir: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
    }

    public func stat(_ url: URL) throws -> FileStat {
        var st = Darwin.stat()
        guard Darwin.stat(url.path, &st) == 0 else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let seconds = TimeInterval(st.st_mtimespec.tv_sec)
        let nanos = TimeInterval(st.st_mtimespec.tv_nsec) / 1_000_000_000
        return FileStat(modified: Date(timeIntervalSince1970: seconds + nanos), size: Int(st.st_size))
    }

    public func read(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func processAlive(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
```

- [ ] **Step 4: FakeFileSystem.swift 작성**

`Tests/ClaudeCatsCoreTests/FakeFileSystem.swift`:
```swift
import Foundation
@testable import ClaudeCatsCore

/// 테스트 전용 인메모리 파일시스템. 테스트 하나당 인스턴스 하나만 쓴다(동기화 없음).
final class FakeFileSystem: FileSystem, @unchecked Sendable {
    private var files: [String: (data: Data, modified: Date)] = [:]
    var alivePids: Set<Int32> = []
    var readCount: [String: Int] = [:]

    func add(_ path: String, _ text: String, modified: Date) {
        files[path] = (Data(text.utf8), modified)
    }

    func remove(_ path: String) {
        files[path] = nil
    }

    func touch(_ path: String, modified: Date) {
        guard let f = files[path] else { return }
        files[path] = (f.data, modified)
    }

    private func isDirectory(_ path: String) -> Bool {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        return files.keys.contains { $0.hasPrefix(prefix) }
    }

    func list(_ dir: URL) throws -> [URL] {
        let prefix = dir.path.hasSuffix("/") ? dir.path : dir.path + "/"
        guard isDirectory(dir.path) else { throw CocoaError(.fileReadNoSuchFile) }
        var children = Set<String>()
        for path in files.keys where path.hasPrefix(prefix) {
            let rest = path.dropFirst(prefix.count)
            if let first = rest.split(separator: "/", maxSplits: 1).first, !first.hasPrefix(".") {
                children.insert(prefix + first)
            }
        }
        return children.sorted().map { URL(fileURLWithPath: $0) }
    }

    func stat(_ url: URL) throws -> FileStat {
        if let f = files[url.path] { return FileStat(modified: f.modified, size: f.data.count) }
        if isDirectory(url.path) { return FileStat(modified: .distantPast, size: 0) }
        throw CocoaError(.fileReadNoSuchFile)
    }

    func read(_ url: URL) throws -> Data {
        readCount[url.path, default: 0] += 1
        guard let f = files[url.path] else { throw CocoaError(.fileReadNoSuchFile) }
        return f.data
    }

    func processAlive(_ pid: Int32) -> Bool {
        alivePids.contains(pid)
    }
}
```

- [ ] **Step 5: 통과 확인**

Run: `swift test 2>&1 | tail -5`
Expected: `Test run with 7 tests passed`

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeCatsCore/FileSystem.swift Tests/ClaudeCatsCoreTests/FakeFileSystem.swift Tests/ClaudeCatsCoreTests/FakeFileSystemTests.swift
git commit -m "feat: FileSystem 프로토콜과 실제/인메모리 구현"
```

---

### Task 3: StateCollector — 세션 수집

**Files:**
- Create: `Sources/ClaudeCatsCore/StateCollector.swift`
- Create: `Tests/ClaudeCatsCoreTests/Fixtures.swift`
- Test: `Tests/ClaudeCatsCoreTests/StateCollectorSessionTests.swift`

**Interfaces:**
- Consumes: `FileSystem`, `FakeFileSystem`, 모델(Task 1, 2).
- Produces:
  ```swift
  public final class StateCollector: @unchecked Sendable {
      public var subagentActiveWindow: TimeInterval   // 기본 15
      public var projectLookupRetry: TimeInterval     // 기본 60
      public init(fileSystem: any FileSystem, claudeDir: URL)
      public func collect(now: Date) -> Snapshot       // 단일 직렬 큐에서만 호출
      static func parseSession(_ data: Data) -> Session?
      static func encodeCwd(_ cwd: String) -> String
  }
  ```
  이 태스크에서는 서브에이전트를 항상 `[]` 로 둔다(Task 4 에서 채움).

- [ ] **Step 1: 픽스처 헬퍼 작성**

`Tests/ClaudeCatsCoreTests/Fixtures.swift`:
```swift
import Foundation

enum Fixtures {
    static let claudeDir = URL(fileURLWithPath: "/home/.claude")

    static func sessionJSON(
        pid: Int32, id: String, name: String, cwd: String,
        status: String = "idle", kind: String = "interactive"
    ) -> String {
        """
        {"pid":\(pid),"sessionId":"\(id)","cwd":"\(cwd)","startedAt":1788527779524,\
        "version":"2.1.260","kind":"\(kind)","entrypoint":"cli","name":"\(name)",\
        "status":"\(status)","updatedAt":1788756167866}
        """
    }

    static func sessionPath(pid: Int32) -> String {
        "/home/.claude/sessions/\(pid).json"
    }
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

`Tests/ClaudeCatsCoreTests/StateCollectorSessionTests.swift`:
```swift
import Testing
import Foundation
@testable import ClaudeCatsCore

@Suite struct StateCollectorSessionTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func makeCollector(_ fs: FakeFileSystem) -> StateCollector {
        StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
    }

    @Test func collectsLiveInteractiveSessionsSortedByName() {
        let fs = FakeFileSystem()
        fs.add(Fixtures.sessionPath(pid: 20), Fixtures.sessionJSON(pid: 20, id: "s2", name: "zeta", cwd: "/p/z", status: "busy"), modified: now)
        fs.add(Fixtures.sessionPath(pid: 10), Fixtures.sessionJSON(pid: 10, id: "s1", name: "alpha", cwd: "/p/a", status: "idle"), modified: now)
        fs.alivePids = [10, 20]
        let snap = makeCollector(fs).collect(now: now)
        #expect(snap.sessions.map(\.name) == ["alpha", "zeta"])
        #expect(snap.sessions[0].status == .idle)
        #expect(snap.sessions[1].status == .busy)
        #expect(snap.sessions[1].pid == 20)
        #expect(snap.sessions[1].cwd == "/p/z")
        #expect(snap.sessions[1].id == "s2")
    }

    @Test func skipsDeadPid() {
        let fs = FakeFileSystem()
        fs.add(Fixtures.sessionPath(pid: 10), Fixtures.sessionJSON(pid: 10, id: "s1", name: "a", cwd: "/p"), modified: now)
        fs.alivePids = []
        #expect(makeCollector(fs).collect(now: now).sessions.isEmpty)
    }

    @Test func skipsNonInteractive() {
        let fs = FakeFileSystem()
        fs.add(Fixtures.sessionPath(pid: 10), Fixtures.sessionJSON(pid: 10, id: "s1", name: "a", cwd: "/p", kind: "background"), modified: now)
        fs.alivePids = [10]
        #expect(makeCollector(fs).collect(now: now).sessions.isEmpty)
    }

    @Test func unknownStatusIsIdle() {
        let fs = FakeFileSystem()
        fs.add(Fixtures.sessionPath(pid: 10), Fixtures.sessionJSON(pid: 10, id: "s1", name: "a", cwd: "/p", status: "weird"), modified: now)
        fs.alivePids = [10]
        #expect(makeCollector(fs).collect(now: now).sessions.first?.status == .idle)
    }

    @Test func skipsBrokenJsonAndNonJsonFiles() {
        let fs = FakeFileSystem()
        fs.add(Fixtures.sessionPath(pid: 10), "{not json", modified: now)
        fs.add("/home/.claude/sessions/10.abc.key", "key", modified: now)
        fs.add(Fixtures.sessionPath(pid: 11), Fixtures.sessionJSON(pid: 11, id: "s1", name: "ok", cwd: "/p"), modified: now)
        fs.alivePids = [10, 11]
        #expect(makeCollector(fs).collect(now: now).sessions.map(\.name) == ["ok"])
    }

    @Test func missingSessionsDirYieldsEmptySnapshot() {
        let fs = FakeFileSystem()
        let snap = makeCollector(fs).collect(now: now)
        #expect(snap.sessions.isEmpty)
        #expect(snap.takenAt == now)
    }

    @Test func reusesParsedSessionWhenMtimeUnchanged() {
        let fs = FakeFileSystem()
        let path = Fixtures.sessionPath(pid: 10)
        fs.add(path, Fixtures.sessionJSON(pid: 10, id: "s1", name: "a", cwd: "/p"), modified: now)
        fs.alivePids = [10]
        let c = makeCollector(fs)
        _ = c.collect(now: now)
        _ = c.collect(now: now.addingTimeInterval(3))
        #expect(fs.readCount[path] == 1)
        fs.add(path, Fixtures.sessionJSON(pid: 10, id: "s1", name: "a", cwd: "/p", status: "busy"), modified: now.addingTimeInterval(2))
        let snap = c.collect(now: now.addingTimeInterval(6))
        #expect(fs.readCount[path] == 2)
        #expect(snap.sessions.first?.status == .busy)
    }

    @Test func pidLivenessRecheckedEvenWhenCached() {
        let fs = FakeFileSystem()
        fs.add(Fixtures.sessionPath(pid: 10), Fixtures.sessionJSON(pid: 10, id: "s1", name: "a", cwd: "/p"), modified: now)
        fs.alivePids = [10]
        let c = makeCollector(fs)
        #expect(c.collect(now: now).sessions.count == 1)
        fs.alivePids = []
        #expect(c.collect(now: now.addingTimeInterval(3)).sessions.isEmpty)
    }

    @Test func duplicateSessionIdKeptOnce() {
        let fs = FakeFileSystem()
        fs.add(Fixtures.sessionPath(pid: 10), Fixtures.sessionJSON(pid: 10, id: "same", name: "a", cwd: "/p"), modified: now)
        fs.add(Fixtures.sessionPath(pid: 11), Fixtures.sessionJSON(pid: 11, id: "same", name: "b", cwd: "/p"), modified: now)
        fs.alivePids = [10, 11]
        #expect(makeCollector(fs).collect(now: now).sessions.count == 1)
    }

    @Test func encodeCwdReplacesSlashAndUnderscore() {
        #expect(StateCollector.encodeCwd("/Users/me/Documents/flo/_obsidian") == "-Users-me-Documents-flo--obsidian")
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `swift test 2>&1 | tail -20`
Expected: 컴파일 에러 — `cannot find 'StateCollector' in scope`

- [ ] **Step 4: StateCollector.swift 작성 (세션 부분)**

`Sources/ClaudeCatsCore/StateCollector.swift`:
```swift
import Foundation
import os

/// ~/.claude 를 읽어 Snapshot 을 만든다.
/// 스레드 안전하지 않다. 항상 같은 직렬 큐에서 collect 를 호출할 것.
public final class StateCollector: @unchecked Sendable {
    public var subagentActiveWindow: TimeInterval = 15
    public var projectLookupRetry: TimeInterval = 60

    private let fs: any FileSystem
    private let claudeDir: URL
    private let log = Logger(subsystem: "claude-cats", category: "collector")

    /// key: sessions/<pid>.json 경로
    private var sessionCache: [String: (modified: Date, session: Session)] = [:]

    public init(fileSystem: any FileSystem, claudeDir: URL) {
        self.fs = fileSystem
        self.claudeDir = claudeDir
    }

    public func collect(now: Date) -> Snapshot {
        let sessionsDir = claudeDir.appendingPathComponent("sessions")
        let files = (try? fs.list(sessionsDir)) ?? []
        var sessions: [Session] = []
        var seenPaths = Set<String>()
        var seenIds = Set<String>()

        for file in files where file.pathExtension == "json" {
            guard let st = try? fs.stat(file) else { continue }
            seenPaths.insert(file.path)

            var session: Session
            if let cached = sessionCache[file.path], cached.modified == st.modified {
                session = cached.session
            } else {
                guard let data = try? fs.read(file) else {
                    log.warning("read failed: \(file.path, privacy: .public)")
                    continue
                }
                guard let parsed = Self.parseSession(data) else {
                    log.debug("skipped session file: \(file.path, privacy: .public)")
                    continue
                }
                session = parsed
                sessionCache[file.path] = (st.modified, parsed)
            }

            guard fs.processAlive(session.pid) else { continue }
            guard !seenIds.contains(session.id) else { continue }
            seenIds.insert(session.id)

            session.subagents = session.status == .busy ? activeSubagents(for: session, now: now) : []
            sessions.append(session)
        }

        sessionCache = sessionCache.filter { seenPaths.contains($0.key) }
        sessions.sort { $0.name < $1.name }
        return Snapshot(sessions: sessions, takenAt: now)
    }

    // MARK: - Sessions

    private struct SessionFile: Decodable {
        let pid: Int32
        let sessionId: String
        let name: String
        let cwd: String
        let status: String?
        let kind: String?
    }

    static func parseSession(_ data: Data) -> Session? {
        guard let f = try? JSONDecoder().decode(SessionFile.self, from: data) else { return nil }
        guard f.kind == "interactive" else { return nil }
        return Session(
            id: f.sessionId, pid: f.pid, name: f.name, cwd: f.cwd,
            status: f.status == "busy" ? .busy : .idle,
            subagents: []
        )
    }

    /// 관찰된 규칙: `/` 와 `_` 를 `-` 로. 맞지 않으면 projectDir 가 glob 으로 폴백한다.
    static func encodeCwd(_ cwd: String) -> String {
        String(cwd.map { $0 == "/" || $0 == "_" ? "-" : $0 })
    }

    // MARK: - Subagents (Task 4 에서 구현)

    private func activeSubagents(for session: Session, now: Date) -> [Subagent] {
        []
    }
}
```

- [ ] **Step 5: 통과 확인**

Run: `swift test 2>&1 | tail -5`
Expected: `Test run with 17 tests passed`

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeCatsCore/StateCollector.swift Tests/ClaudeCatsCoreTests/Fixtures.swift Tests/ClaudeCatsCoreTests/StateCollectorSessionTests.swift
git commit -m "feat: StateCollector 세션 수집과 mtime 캐시"
```

---

### Task 4: StateCollector — 서브에이전트 수집

**Files:**
- Modify: `Sources/ClaudeCatsCore/StateCollector.swift` (`activeSubagents` 구현, 캐시 추가)
- Modify: `Tests/ClaudeCatsCoreTests/Fixtures.swift` (서브에이전트 픽스처)
- Test: `Tests/ClaudeCatsCoreTests/StateCollectorSubagentTests.swift`

**Interfaces:**
- Consumes: Task 3 의 `StateCollector`.
- Produces: `Session.subagents` 가 busy 세션에 한해 실행 중 서브에이전트(`id` 정렬)로 채워진다. `id` 는 파일명 `agent-<id>.jsonl` 의 `<id>`.

- [ ] **Step 1: 픽스처 확장**

`Tests/ClaudeCatsCoreTests/Fixtures.swift` 의 `enum Fixtures` 안에 추가:
```swift
    static func subagentDir(encodedCwd: String, sessionId: String) -> String {
        "/home/.claude/projects/\(encodedCwd)/\(sessionId)/subagents"
    }

    static func metaJSON(description: String) -> String {
        """
        {"agentType":"fork","isFork":true,"description":"\(description)",\
        "toolUseId":"toolu_01","spawnDepth":1,"model":"inherit"}
        """
    }
```

- [ ] **Step 2: 실패하는 테스트 작성**

`Tests/ClaudeCatsCoreTests/StateCollectorSubagentTests.swift`:
```swift
import Testing
import Foundation
@testable import ClaudeCatsCore

@Suite struct StateCollectorSubagentTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let cwd = "/Users/me/proj_x"
    let encoded = "-Users-me-proj-x"

    /// busy 세션 하나(pid 10, id "sess") 를 가진 fs 를 만든다.
    func makeFS(status: String = "busy") -> FakeFileSystem {
        let fs = FakeFileSystem()
        fs.add(Fixtures.sessionPath(pid: 10), Fixtures.sessionJSON(pid: 10, id: "sess", name: "a", cwd: cwd, status: status), modified: now)
        fs.alivePids = [10]
        return fs
    }

    func addAgent(_ fs: FakeFileSystem, dir: String, id: String, ago: TimeInterval, description: String = "work") {
        fs.add("\(dir)/agent-\(id).jsonl", "{}\n", modified: now.addingTimeInterval(-ago))
        fs.add("\(dir)/agent-\(id).meta.json", Fixtures.metaJSON(description: description), modified: now.addingTimeInterval(-ago))
    }

    @Test func activeSubagentsWithin15Seconds() {
        let fs = makeFS()
        let dir = Fixtures.subagentDir(encodedCwd: encoded, sessionId: "sess")
        addAgent(fs, dir: dir, id: "b", ago: 14.9)
        addAgent(fs, dir: dir, id: "a", ago: 1)
        addAgent(fs, dir: dir, id: "old", ago: 15.1)
        let subs = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir).collect(now: now).sessions[0].subagents
        #expect(subs.map(\.id) == ["a", "b"])
        #expect(subs[0].description == "work")
        #expect(subs[0].lastActivity == now.addingTimeInterval(-1))
    }

    @Test func idleSessionDoesNotScanSubagents() {
        let fs = makeFS(status: "idle")
        let dir = Fixtures.subagentDir(encodedCwd: encoded, sessionId: "sess")
        addAgent(fs, dir: dir, id: "a", ago: 1)
        let snap = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir).collect(now: now)
        #expect(snap.sessions[0].subagents.isEmpty)
        #expect(fs.readCount["\(dir)/agent-a.meta.json"] == nil)
    }

    @Test func fallsBackToGlobWhenEncodedCwdMissingAndCachesResult() {
        let fs = makeFS()
        let dir = Fixtures.subagentDir(encodedCwd: "-weird-encoding", sessionId: "sess")
        addAgent(fs, dir: dir, id: "a", ago: 1)
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        #expect(c.collect(now: now).sessions[0].subagents.map(\.id) == ["a"])
        #expect(c.collect(now: now.addingTimeInterval(3)).sessions[0].subagents.map(\.id) == ["a"])
    }

    @Test func missingProjectDirRetriedAfter60Seconds() {
        let fs = makeFS()
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        #expect(c.collect(now: now).sessions[0].subagents.isEmpty)
        let dir = Fixtures.subagentDir(encodedCwd: encoded, sessionId: "sess")
        addAgent(fs, dir: dir, id: "a", ago: 0)
        // 30초 뒤: 아직 실패 캐시 유효 → 여전히 빈 배열
        #expect(c.collect(now: now.addingTimeInterval(30)).sessions[0].subagents.isEmpty)
        // 61초 뒤: 재시도 → 발견 (mtime 을 갱신해 15초 창 안으로)
        fs.touch("\(dir)/agent-a.jsonl", modified: now.addingTimeInterval(61))
        #expect(c.collect(now: now.addingTimeInterval(61)).sessions[0].subagents.map(\.id) == ["a"])
    }

    @Test func metaReadOnceAndMissingMetaGivesEmptyDescription() {
        let fs = makeFS()
        let dir = Fixtures.subagentDir(encodedCwd: encoded, sessionId: "sess")
        addAgent(fs, dir: dir, id: "a", ago: 1)
        fs.add("\(dir)/agent-nometa.jsonl", "{}\n", modified: now)
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        _ = c.collect(now: now)
        let subs = c.collect(now: now.addingTimeInterval(3)).sessions[0].subagents
        #expect(fs.readCount["\(dir)/agent-a.meta.json"] == 1)
        #expect(subs.first { $0.id == "nometa" }?.description == "")
    }

    @Test func jsonlContentIsNeverRead() {
        let fs = makeFS()
        let dir = Fixtures.subagentDir(encodedCwd: encoded, sessionId: "sess")
        addAgent(fs, dir: dir, id: "a", ago: 1)
        _ = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir).collect(now: now)
        #expect(fs.readCount["\(dir)/agent-a.jsonl"] == nil)
    }
}
```

- [ ] **Step 3: 실패 확인**

Run: `swift test 2>&1 | grep -E "passed|failed" | tail -10`
Expected: `activeSubagentsWithin15Seconds` 등 5개 실패(서브에이전트가 빈 배열), `idleSessionDoesNotScanSubagents` 와 `jsonlContentIsNeverRead` 만 통과.

- [ ] **Step 4: 서브에이전트 구현**

`Sources/ClaudeCatsCore/StateCollector.swift` 에서 프로퍼티 추가(`sessionCache` 아래):
```swift
    /// key: sessionId. url 이 nil 이면 실패 캐시(checkedAt + projectLookupRetry 후 재시도).
    private var projectDirCache: [String: (url: URL?, checkedAt: Date)] = [:]
    /// key: meta.json 경로 → description
    private var metaCache: [String: String] = [:]
```

`// MARK: - Subagents` 섹션을 다음으로 교체:
```swift
    // MARK: - Subagents

    private struct MetaFile: Decodable {
        let description: String?
    }

    private func projectDir(for session: Session, now: Date) -> URL? {
        if let cached = projectDirCache[session.id] {
            if cached.url != nil { return cached.url }
            if now.timeIntervalSince(cached.checkedAt) < projectLookupRetry { return nil }
        }
        let projects = claudeDir.appendingPathComponent("projects")
        let guess = projects
            .appendingPathComponent(Self.encodeCwd(session.cwd))
            .appendingPathComponent(session.id)
        var found: URL? = (try? fs.stat(guess)) != nil ? guess : nil
        if found == nil, let dirs = try? fs.list(projects) {
            for dir in dirs {
                let candidate = dir.appendingPathComponent(session.id)
                if (try? fs.stat(candidate)) != nil {
                    found = candidate
                    break
                }
            }
        }
        projectDirCache[session.id] = (found, now)
        return found
    }

    private func activeSubagents(for session: Session, now: Date) -> [Subagent] {
        guard let dir = projectDir(for: session, now: now) else { return [] }
        let subDir = dir.appendingPathComponent("subagents")
        guard let files = try? fs.list(subDir) else { return [] }

        var result: [Subagent] = []
        for file in files where file.pathExtension == "jsonl" {
            guard let st = try? fs.stat(file),
                  now.timeIntervalSince(st.modified) <= subagentActiveWindow else { continue }
            let base = file.deletingPathExtension().lastPathComponent
            let id = base.hasPrefix("agent-") ? String(base.dropFirst("agent-".count)) : base
            let metaURL = file.deletingPathExtension().appendingPathExtension("meta.json")
            let description: String
            if let cached = metaCache[metaURL.path] {
                description = cached
            } else {
                description = (try? fs.read(metaURL))
                    .flatMap { try? JSONDecoder().decode(MetaFile.self, from: $0) }?
                    .description ?? ""
                metaCache[metaURL.path] = description
            }
            result.append(Subagent(id: id, description: description, lastActivity: st.modified))
        }
        return result.sorted { $0.id < $1.id }
    }
```

- [ ] **Step 5: 통과 확인**

Run: `swift test 2>&1 | tail -5`
Expected: `Test run with 23 tests passed`

- [ ] **Step 6: 실제 파일로 스모크 (선택, 결과만 확인)**

`Sources/ClaudeCats/main.swift` 를 임시로:
```swift
import Foundation
import ClaudeCatsCore

let home = FileManager.default.homeDirectoryForCurrentUser
let collector = StateCollector(fileSystem: RealFileSystem(), claudeDir: home.appendingPathComponent(".claude"))
let t0 = Date()
let snap = collector.collect(now: Date())
print("tick \(Int(Date().timeIntervalSince(t0) * 1000))ms")
for s in snap.sessions {
    print(s.status == .busy ? "●" : "○", s.name, s.subagents.map(\.id))
}
```
Run: `swift run 2>&1 | tail -20`
Expected: 살아있는 세션 목록이 출력되고 `tick` 이 50ms 이하. 이 main.swift 는 Task 9 에서 교체되므로 커밋해도 된다.

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "feat: StateCollector 서브에이전트 수집(mtime 15초 창, 프로젝트 디렉터리 폴백 캐시)"
```

---

### Task 5: StableHash + Scene 배치

**Files:**
- Create: `Sources/ClaudeCatsCore/StableHash.swift`
- Create: `Sources/ClaudeCatsCore/Scene.swift`
- Test: `Tests/ClaudeCatsCoreTests/SceneTests.swift`

**Interfaces:**
- Consumes: `Snapshot`, `Session`, `Subagent`.
- Produces:
  ```swift
  public enum StableHash { public static func fnv1a(_ s: String) -> UInt64 }
  public enum Pose: Sendable, Equatable { case sitting, sleeping }
  public struct CatPlacement: Sendable, Equatable, Identifiable {
      public var id: String            // 세션: sessionId, 새끼: "<sessionId>/<agentId>"
      public var origin: CGPoint       // 64×64 박스의 좌하단, AppKit 좌표(y 위로)
      public var scale: CGFloat        // 1.0 / 0.5
      public var pose: Pose
      public var paletteIndex: Int     // 0..<8
      public var label: String?        // 세션 이름, 새끼는 nil
      public var animated: Bool
      public var overflowCount: Int    // 세 번째 새끼에 "+n", 아니면 0
  }
  public struct Layout: Sendable, Equatable { public var cats: [CatPlacement] }
  public struct SceneConfig: Sendable { slotWidth 140, bottomInset 40, rowHeight 100, catWidth 64, kittenGap 24, kittenStack 10, maxKittens 3, paletteSize 8 }
  public enum Scene {
      public static func layout(_ snapshot: Snapshot, screenSize: CGSize, animationsEnabled: Bool, config: SceneConfig = SceneConfig()) -> Layout
  }
  ```

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/ClaudeCatsCoreTests/SceneTests.swift`:
```swift
import Testing
import Foundation
@testable import ClaudeCatsCore

@Suite struct SceneTests {
    let screen = CGSize(width: 1440, height: 900)   // slotCount = 10

    func session(_ name: String, status: Status = .idle, subagents: [Subagent] = []) -> Session {
        Session(id: "id-\(name)", pid: 1, name: name, cwd: "/", status: status, subagents: subagents)
    }

    func sub(_ id: String) -> Subagent {
        Subagent(id: id, description: "", lastActivity: .now)
    }

    func layout(_ sessions: [Session], animations: Bool = true) -> Layout {
        Scene.layout(Snapshot(sessions: sessions, takenAt: .now), screenSize: screen, animationsEnabled: animations)
    }

    @Test func fnv1aIsStable() {
        #expect(StableHash.fnv1a("") == 0xcbf29ce484222325)
        #expect(StableHash.fnv1a("a") == 0xaf63dc4c8601ec8c)
    }

    @Test func deterministicForSameInput() {
        let s = [session("alpha", status: .busy), session("beta"), session("gamma")]
        #expect(layout(s) == layout(s))
    }

    @Test func poseAndLabelFollowStatus() {
        let l = layout([session("busy1", status: .busy), session("idle1", status: .idle)])
        let busy = l.cats.first { $0.label == "busy1" }!
        let idle = l.cats.first { $0.label == "idle1" }!
        #expect(busy.pose == .sitting && busy.animated == true)
        #expect(idle.pose == .sleeping && idle.animated == false)
        #expect(busy.scale == 1 && busy.id == "id-busy1")
    }

    @Test func animationsDisabledTurnsOffAnimatedFlag() {
        let l = layout([session("b", status: .busy, subagents: [sub("x")])], animations: false)
        #expect(l.cats.allSatisfy { $0.animated == false })
        #expect(l.cats.first { $0.label == "b" }?.pose == .sitting)
    }

    @Test func originsAlignToSlotsAndBottomInset() {
        let l = layout([session("only")])
        let cat = l.cats[0]
        #expect(cat.origin.y == 40)
        #expect((cat.origin.x - 16).truncatingRemainder(dividingBy: 140) == 0)
        #expect(cat.origin.x >= 16 && cat.origin.x < 1440)
    }

    @Test func collisionsProbeToDistinctSlotsInSameRow() {
        // 슬롯 10개에 세션 10개: 충돌이 나도 전부 첫 줄(y == 40), x 는 서로 다름
        let s = (0..<10).map { session("s\($0)") }
        let l = layout(s)
        #expect(l.cats.allSatisfy { $0.origin.y == 40 })
        #expect(Set(l.cats.map(\.origin.x)).count == 10)
    }

    @Test func overflowGoesToSecondRow() {
        let s = (0..<11).map { session("s\($0)") }
        let l = layout(s)
        #expect(l.cats.filter { $0.origin.y == 140 }.count == 1)
        #expect(l.cats.filter { $0.origin.y == 40 }.count == 10)
    }

    @Test func kittensSitRightOfParentWithSameColorAndHalfScale() {
        let l = layout([session("p", status: .busy, subagents: [sub("k1"), sub("k2")])])
        let parent = l.cats.first { $0.id == "id-p" }!
        let k1 = l.cats.first { $0.id == "id-p/k1" }!
        let k2 = l.cats.first { $0.id == "id-p/k2" }!
        #expect(k1.scale == 0.5 && k1.label == nil && k1.pose == .sitting && k1.animated)
        #expect(k1.paletteIndex == parent.paletteIndex)
        #expect(k1.origin == CGPoint(x: parent.origin.x + 64 + 24, y: parent.origin.y))
        #expect(k2.origin == CGPoint(x: k1.origin.x + 10, y: k1.origin.y + 10))
        #expect(k1.overflowCount == 0 && k2.overflowCount == 0)
    }

    @Test func atMostThreeKittensThenOverflowBadge() {
        let subs = ["a", "b", "c", "d", "e"].map(sub)
        let l = layout([session("p", status: .busy, subagents: subs)])
        let kittens = l.cats.filter { $0.id.hasPrefix("id-p/") }
        #expect(kittens.count == 3)
        #expect(kittens.map(\.overflowCount) == [0, 0, 2])
    }

    @Test func paletteIndexWithinRangeAndStable() {
        let a = layout([session("obsidian-71")]).cats[0].paletteIndex
        let b = layout([session("obsidian-71"), session("other")]).cats.first { $0.label == "obsidian-71" }!.paletteIndex
        #expect(a == b && (0..<8).contains(a))
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test 2>&1 | tail -20`
Expected: 컴파일 에러 — `cannot find 'Scene' in scope`

- [ ] **Step 3: StableHash.swift 작성**

`Sources/ClaudeCatsCore/StableHash.swift`:
```swift
public enum StableHash {
    /// FNV-1a 64bit. Swift 의 Hasher 는 프로세스마다 시드가 달라 배치가 튀므로 쓰지 않는다.
    public static func fnv1a(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
```

- [ ] **Step 4: Scene.swift 작성**

`Sources/ClaudeCatsCore/Scene.swift`:
```swift
import Foundation
import CoreGraphics

public enum Pose: Sendable, Equatable {
    case sitting
    case sleeping
}

public struct CatPlacement: Sendable, Equatable, Identifiable {
    public var id: String
    public var origin: CGPoint
    public var scale: CGFloat
    public var pose: Pose
    public var paletteIndex: Int
    public var label: String?
    public var animated: Bool
    public var overflowCount: Int

    public init(id: String, origin: CGPoint, scale: CGFloat, pose: Pose, paletteIndex: Int,
                label: String?, animated: Bool, overflowCount: Int) {
        self.id = id
        self.origin = origin
        self.scale = scale
        self.pose = pose
        self.paletteIndex = paletteIndex
        self.label = label
        self.animated = animated
        self.overflowCount = overflowCount
    }
}

public struct Layout: Sendable, Equatable {
    public var cats: [CatPlacement]
    public init(cats: [CatPlacement]) { self.cats = cats }
}

public struct SceneConfig: Sendable {
    public var slotWidth: CGFloat = 140
    public var bottomInset: CGFloat = 40
    public var rowHeight: CGFloat = 100
    public var catWidth: CGFloat = 64
    public var slotPadding: CGFloat = 16
    public var kittenGap: CGFloat = 24
    public var kittenStack: CGFloat = 10
    public var maxKittens: Int = 3
    public var paletteSize: Int = 8
    public init() {}
}

public enum Scene {
    public static func layout(
        _ snapshot: Snapshot,
        screenSize: CGSize,
        animationsEnabled: Bool,
        config: SceneConfig = SceneConfig()
    ) -> Layout {
        let slotCount = max(1, Int(screenSize.width / config.slotWidth))
        var occupied = Set<Int>()   // row * slotCount + col
        var cats: [CatPlacement] = []

        for session in snapshot.sessions {
            let hash = StableHash.fnv1a(session.name)
            let base = Int(hash % UInt64(slotCount))
            let slot = findSlot(base: base, slotCount: slotCount, occupied: occupied)
            occupied.insert(slot)

            let row = slot / slotCount
            let col = slot % slotCount
            let origin = CGPoint(
                x: CGFloat(col) * config.slotWidth + config.slotPadding,
                y: config.bottomInset + CGFloat(row) * config.rowHeight
            )
            let paletteIndex = Int(hash % UInt64(config.paletteSize))
            let pose: Pose = session.status == .busy ? .sitting : .sleeping

            cats.append(CatPlacement(
                id: session.id, origin: origin, scale: 1, pose: pose,
                paletteIndex: paletteIndex, label: session.name,
                animated: pose == .sitting && animationsEnabled, overflowCount: 0
            ))

            let shown = session.subagents.prefix(config.maxKittens)
            for (i, sub) in shown.enumerated() {
                let isLast = i == config.maxKittens - 1
                let overflow = isLast ? max(0, session.subagents.count - config.maxKittens) : 0
                cats.append(CatPlacement(
                    id: session.id + "/" + sub.id,
                    origin: CGPoint(
                        x: origin.x + config.catWidth + config.kittenGap + CGFloat(i) * config.kittenStack,
                        y: origin.y + CGFloat(i) * config.kittenStack
                    ),
                    scale: 0.5, pose: .sitting, paletteIndex: paletteIndex,
                    label: nil, animated: animationsEnabled, overflowCount: overflow
                ))
            }
        }
        return Layout(cats: cats)
    }

    /// 같은 줄에서 오른쪽으로 선형 탐사(끝에 닿으면 줄 처음으로 감). 줄이 꽉 차면 다음 줄.
    private static func findSlot(base: Int, slotCount: Int, occupied: Set<Int>) -> Int {
        var row = 0
        while true {
            for k in 0..<slotCount {
                let slot = row * slotCount + (base + k) % slotCount
                if !occupied.contains(slot) { return slot }
            }
            row += 1
        }
    }
}
```

- [ ] **Step 5: 통과 확인**

Run: `swift test 2>&1 | tail -5`
Expected: `Test run with 33 tests passed`. `fnv1aIsStable` 의 `"a"` 기대값이 틀리면 구현이 아니라 상수 오타이므로 `python3 -c "h=0xcbf29ce484222325; h^=97; print(hex((h*0x100000001b3)&0xffffffffffffffff))"` 로 확인해 테스트 값을 맞춘다.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeCatsCore/StableHash.swift Sources/ClaudeCatsCore/Scene.swift Tests/ClaudeCatsCoreTests/SceneTests.swift
git commit -m "feat: Scene 결정적 슬롯 배치와 새끼 고양이 배치"
```

---

### Task 6: PowerPolicy

**Files:**
- Create: `Sources/ClaudeCatsCore/PowerPolicy.swift`
- Test: `Tests/ClaudeCatsCoreTests/PowerPolicyTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct PowerState: Sendable, Equatable {
      public var onBattery, lowPowerMode, screenLocked, displayAsleep, systemAsleep, userPaused: Bool
      public init(onBattery: Bool = false, lowPowerMode: Bool = false, screenLocked: Bool = false,
                  displayAsleep: Bool = false, systemAsleep: Bool = false, userPaused: Bool = false)
  }
  public enum PollingMode: Sendable, Equatable {
      case normal, lowPower, suspended
      public var interval: TimeInterval?     // 3, 10, nil
      public var animationsEnabled: Bool     // normal 만 true
  }
  public enum PowerPolicy { public static func mode(for state: PowerState) -> PollingMode }
  ```

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/ClaudeCatsCoreTests/PowerPolicyTests.swift`:
```swift
import Testing
@testable import ClaudeCatsCore

@Suite struct PowerPolicyTests {
    @Test func acPowerIsNormal() {
        #expect(PowerPolicy.mode(for: PowerState()) == .normal)
        #expect(PollingMode.normal.interval == 3)
        #expect(PollingMode.normal.animationsEnabled)
    }

    @Test func batteryOrLowPowerIsLowPower() {
        #expect(PowerPolicy.mode(for: PowerState(onBattery: true)) == .lowPower)
        #expect(PowerPolicy.mode(for: PowerState(lowPowerMode: true)) == .lowPower)
        #expect(PollingMode.lowPower.interval == 10)
        #expect(!PollingMode.lowPower.animationsEnabled)
    }

    @Test func lockSleepSaverPauseSuspend() {
        #expect(PowerPolicy.mode(for: PowerState(screenLocked: true)) == .suspended)
        #expect(PowerPolicy.mode(for: PowerState(displayAsleep: true)) == .suspended)
        #expect(PowerPolicy.mode(for: PowerState(systemAsleep: true)) == .suspended)
        #expect(PowerPolicy.mode(for: PowerState(userPaused: true)) == .suspended)
        #expect(PollingMode.suspended.interval == nil)
        #expect(!PollingMode.suspended.animationsEnabled)
    }

    @Test func suspendBeatsLowPower() {
        #expect(PowerPolicy.mode(for: PowerState(onBattery: true, screenLocked: true)) == .suspended)
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test 2>&1 | tail -20`
Expected: 컴파일 에러 — `cannot find 'PowerPolicy' in scope`

- [ ] **Step 3: PowerPolicy.swift 작성**

`Sources/ClaudeCatsCore/PowerPolicy.swift`:
```swift
import Foundation

public struct PowerState: Sendable, Equatable {
    public var onBattery: Bool
    public var lowPowerMode: Bool
    public var screenLocked: Bool
    public var displayAsleep: Bool
    public var systemAsleep: Bool
    public var userPaused: Bool

    public init(onBattery: Bool = false, lowPowerMode: Bool = false, screenLocked: Bool = false,
                displayAsleep: Bool = false, systemAsleep: Bool = false, userPaused: Bool = false) {
        self.onBattery = onBattery
        self.lowPowerMode = lowPowerMode
        self.screenLocked = screenLocked
        self.displayAsleep = displayAsleep
        self.systemAsleep = systemAsleep
        self.userPaused = userPaused
    }
}

public enum PollingMode: Sendable, Equatable {
    case normal
    case lowPower
    case suspended

    public var interval: TimeInterval? {
        switch self {
        case .normal: return 3
        case .lowPower: return 10
        case .suspended: return nil
        }
    }

    public var animationsEnabled: Bool {
        self == .normal
    }
}

public enum PowerPolicy {
    public static func mode(for state: PowerState) -> PollingMode {
        if state.userPaused || state.screenLocked || state.displayAsleep || state.systemAsleep {
            return .suspended
        }
        if state.onBattery || state.lowPowerMode {
            return .lowPower
        }
        return .normal
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test 2>&1 | tail -5`
Expected: `Test run with 37 tests passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeCatsCore/PowerPolicy.swift Tests/ClaudeCatsCoreTests/PowerPolicyTests.swift
git commit -m "feat: PowerPolicy 전원 상태 → 폴링 모드"
```

---

### Task 7: LayoutDiffer

**Files:**
- Create: `Sources/ClaudeCatsCore/LayoutDiffer.swift`
- Test: `Tests/ClaudeCatsCoreTests/LayoutDifferTests.swift`

**Interfaces:**
- Consumes: `Layout`, `CatPlacement`.
- Produces:
  ```swift
  public struct LayoutDiff: Sendable, Equatable {
      public var added: [CatPlacement]
      public var removed: [String]        // id
      public var updated: [CatPlacement]  // 이전에도 있었고 값이 바뀐 것
  }
  public enum LayoutDiffer { public static func diff(from old: Layout, to new: Layout) -> LayoutDiff }
  ```

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/ClaudeCatsCoreTests/LayoutDifferTests.swift`:
```swift
import Testing
import Foundation
@testable import ClaudeCatsCore

@Suite struct LayoutDifferTests {
    func cat(_ id: String, x: CGFloat = 0, pose: Pose = .sitting) -> CatPlacement {
        CatPlacement(id: id, origin: CGPoint(x: x, y: 40), scale: 1, pose: pose,
                     paletteIndex: 0, label: id, animated: false, overflowCount: 0)
    }

    @Test func emptyToEmptyIsEmptyDiff() {
        let d = LayoutDiffer.diff(from: Layout(cats: []), to: Layout(cats: []))
        #expect(d == LayoutDiff(added: [], removed: [], updated: []))
    }

    @Test func detectsAddedRemovedUpdatedAndIgnoresUnchanged() {
        let old = Layout(cats: [cat("a"), cat("b"), cat("c", pose: .sleeping)])
        let new = Layout(cats: [cat("a"), cat("c", pose: .sitting), cat("d", x: 10)])
        let d = LayoutDiffer.diff(from: old, to: new)
        #expect(d.added == [cat("d", x: 10)])
        #expect(d.removed == ["b"])
        #expect(d.updated == [cat("c", pose: .sitting)])
    }

    @Test func preservesNewLayoutOrderForAdded() {
        let new = Layout(cats: [cat("z"), cat("a")])
        let d = LayoutDiffer.diff(from: Layout(cats: []), to: new)
        #expect(d.added.map(\.id) == ["z", "a"])
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `swift test 2>&1 | tail -20`
Expected: 컴파일 에러 — `cannot find 'LayoutDiffer' in scope`

- [ ] **Step 3: LayoutDiffer.swift 작성**

`Sources/ClaudeCatsCore/LayoutDiffer.swift`:
```swift
public struct LayoutDiff: Sendable, Equatable {
    public var added: [CatPlacement]
    public var removed: [String]
    public var updated: [CatPlacement]

    public init(added: [CatPlacement], removed: [String], updated: [CatPlacement]) {
        self.added = added
        self.removed = removed
        self.updated = updated
    }

    public var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && updated.isEmpty
    }
}

public enum LayoutDiffer {
    public static func diff(from old: Layout, to new: Layout) -> LayoutDiff {
        var oldById: [String: CatPlacement] = [:]
        for cat in old.cats { oldById[cat.id] = cat }
        let newIds = Set(new.cats.map(\.id))

        var added: [CatPlacement] = []
        var updated: [CatPlacement] = []
        for cat in new.cats {
            if let previous = oldById[cat.id] {
                if previous != cat { updated.append(cat) }
            } else {
                added.append(cat)
            }
        }
        let removed = old.cats.map(\.id).filter { !newIds.contains($0) }
        return LayoutDiff(added: added, removed: removed, updated: updated)
    }
}
```

- [ ] **Step 4: 통과 확인**

Run: `swift test 2>&1 | tail -5`
Expected: `Test run with 40 tests passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeCatsCore/LayoutDiffer.swift Tests/ClaudeCatsCoreTests/LayoutDifferTests.swift
git commit -m "feat: LayoutDiffer 레이아웃 diff"
```

---

### Task 8: CatShapes + CatLayer (앱 타깃)

**Files:**
- Create: `Sources/ClaudeCats/CatShapes.swift`
- Create: `Sources/ClaudeCats/CatLayer.swift`

**Interfaces:**
- Consumes: `CatPlacement`, `Pose`.
- Produces:
  ```swift
  enum CatShapes {
      static let palette: [NSColor]                       // 8색
      static let boxSize: CGFloat                         // 64
      static func body(_ pose: Pose) -> CGPath            // 몸+머리+귀
      static func eyes(_ pose: Pose) -> CGPath            // sitting: 점 2개(fill), sleeping: 선 2개(stroke)
      static func tail(_ pose: Pose, frame: Int) -> CGPath // stroke 용, frame 0/1
  }
  @MainActor final class CatLayer: CALayer {
      private(set) var placement: CatPlacement
      init(placement: CatPlacement, contentsScale: CGFloat)
      func apply(_ placement: CatPlacement)   // CATransaction 액션 비활성 상태로 호출됨
      func tickTail()                          // 꼬리 프레임 토글
  }
  ```
  단위 테스트 없음(순수 AppKit). 빌드 성공 + Task 9 에서 시각 확인.

- [ ] **Step 1: CatShapes.swift 작성**

`Sources/ClaudeCats/CatShapes.swift`:
```swift
import AppKit
import ClaudeCatsCore

enum CatShapes {
    static let boxSize: CGFloat = 64

    static let palette: [NSColor] = [
        NSColor(red: 0.95, green: 0.62, blue: 0.25, alpha: 1),  // 치즈
        NSColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1),  // 검정
        NSColor(red: 0.93, green: 0.92, blue: 0.88, alpha: 1),  // 흰
        NSColor(red: 0.55, green: 0.56, blue: 0.60, alpha: 1),  // 회색
        NSColor(red: 0.60, green: 0.42, blue: 0.28, alpha: 1),  // 갈색
        NSColor(red: 0.86, green: 0.74, blue: 0.55, alpha: 1),  // 크림
        NSColor(red: 0.45, green: 0.38, blue: 0.52, alpha: 1),  // 라일락
        NSColor(red: 0.80, green: 0.50, blue: 0.42, alpha: 1),  // 살구
    ]

    static let eyeColor = NSColor(red: 0.12, green: 0.10, blue: 0.12, alpha: 1)

    /// 좌표계: 64×64, 원점 좌하단(AppKit).
    static func body(_ pose: Pose) -> CGPath {
        let path = CGMutablePath()
        switch pose {
        case .sitting:
            path.addEllipse(in: CGRect(x: 14, y: 4, width: 36, height: 34))          // 몸
            path.addEllipse(in: CGRect(x: 18, y: 30, width: 28, height: 28))         // 머리
            path.move(to: CGPoint(x: 20, y: 50)); path.addLine(to: CGPoint(x: 23, y: 63)); path.addLine(to: CGPoint(x: 30, y: 55)); path.closeSubpath()
            path.move(to: CGPoint(x: 44, y: 50)); path.addLine(to: CGPoint(x: 41, y: 63)); path.addLine(to: CGPoint(x: 34, y: 55)); path.closeSubpath()
        case .sleeping:
            path.addEllipse(in: CGRect(x: 6, y: 4, width: 52, height: 26))           // 웅크린 몸
            path.addEllipse(in: CGRect(x: 34, y: 12, width: 24, height: 24))         // 머리(오른쪽 위)
            path.move(to: CGPoint(x: 38, y: 30)); path.addLine(to: CGPoint(x: 39, y: 40)); path.addLine(to: CGPoint(x: 46, y: 34)); path.closeSubpath()
            path.move(to: CGPoint(x: 56, y: 30)); path.addLine(to: CGPoint(x: 57, y: 40)); path.addLine(to: CGPoint(x: 50, y: 34)); path.closeSubpath()
        }
        return path
    }

    static func eyes(_ pose: Pose) -> CGPath {
        let path = CGMutablePath()
        switch pose {
        case .sitting:
            path.addEllipse(in: CGRect(x: 25, y: 42, width: 4, height: 5))
            path.addEllipse(in: CGRect(x: 35, y: 42, width: 4, height: 5))
        case .sleeping:
            path.move(to: CGPoint(x: 40, y: 23)); path.addLine(to: CGPoint(x: 45, y: 23))
            path.move(to: CGPoint(x: 49, y: 23)); path.addLine(to: CGPoint(x: 54, y: 23))
        }
        return path
    }

    static func tail(_ pose: Pose, frame: Int) -> CGPath {
        let path = CGMutablePath()
        switch pose {
        case .sitting:
            path.move(to: CGPoint(x: 46, y: 10))
            if frame == 0 {
                path.addQuadCurve(to: CGPoint(x: 62, y: 26), control: CGPoint(x: 64, y: 8))
            } else {
                path.addQuadCurve(to: CGPoint(x: 60, y: 6), control: CGPoint(x: 62, y: 20))
            }
        case .sleeping:
            path.move(to: CGPoint(x: 12, y: 10))
            path.addQuadCurve(to: CGPoint(x: 30, y: 6), control: CGPoint(x: 4, y: 0))
        }
        return path
    }
}
```

- [ ] **Step 2: CatLayer.swift 작성**

`Sources/ClaudeCats/CatLayer.swift`:
```swift
import AppKit
import ClaudeCatsCore

/// 고양이 한 마리. 서브레이어: 꼬리 2장(몸 뒤) → 몸 → 눈 → 라벨 → 배지.
/// 모든 프로퍼티 변경은 호출자가 CATransaction 액션을 끈 상태에서 한다.
@MainActor
final class CatLayer: CALayer {
    private(set) var placement: CatPlacement
    private let tailA = CAShapeLayer()
    private let tailB = CAShapeLayer()
    private let bodyLayer = CAShapeLayer()
    private let eyesLayer = CAShapeLayer()
    private let labelLayer = CATextLayer()
    private let badgeLayer = CATextLayer()
    private var tailToggle = false

    init(placement: CatPlacement, contentsScale: CGFloat) {
        self.placement = placement
        super.init()
        anchorPoint = .zero
        bounds = CGRect(x: 0, y: 0, width: CatShapes.boxSize, height: CatShapes.boxSize)
        self.contentsScale = contentsScale

        for tail in [tailA, tailB] {
            tail.fillColor = nil
            tail.lineWidth = 6
            tail.lineCap = .round
            tail.contentsScale = contentsScale
        }
        eyesLayer.lineWidth = 2
        eyesLayer.lineCap = .round
        eyesLayer.contentsScale = contentsScale
        bodyLayer.contentsScale = contentsScale

        labelLayer.frame = CGRect(x: -38, y: -18, width: 140, height: 16)
        labelLayer.alignmentMode = .center
        labelLayer.contentsScale = contentsScale
        labelLayer.isWrapped = false
        labelLayer.truncationMode = .end

        badgeLayer.frame = CGRect(x: 40, y: 48, width: 40, height: 16)
        badgeLayer.alignmentMode = .left
        badgeLayer.contentsScale = contentsScale

        [tailA, tailB, bodyLayer, eyesLayer, labelLayer, badgeLayer].forEach(addSublayer)
        apply(placement)
    }

    override init(layer: Any) {
        // presentation layer 복사용. 우리는 애니메이션 프로퍼티를 쓰지 않으므로 원본 값 복사만.
        let other = layer as! CatLayer
        self.placement = other.placement
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func apply(_ p: CatPlacement) {
        placement = p
        position = p.origin
        transform = CATransform3DMakeScale(p.scale, p.scale, 1)

        let color = CatShapes.palette[p.paletteIndex % CatShapes.palette.count].cgColor
        bodyLayer.path = CatShapes.body(p.pose)
        bodyLayer.fillColor = color

        eyesLayer.path = CatShapes.eyes(p.pose)
        eyesLayer.fillColor = p.pose == .sitting ? CatShapes.eyeColor.cgColor : nil
        eyesLayer.strokeColor = p.pose == .sleeping ? CatShapes.eyeColor.cgColor : nil

        tailA.path = CatShapes.tail(p.pose, frame: 0)
        tailB.path = CatShapes.tail(p.pose, frame: 1)
        tailA.strokeColor = color
        tailB.strokeColor = color
        tailToggle = false
        tailA.isHidden = false
        tailB.isHidden = true

        labelLayer.string = p.label.map(Self.outlinedLabel)
        labelLayer.isHidden = p.label == nil

        badgeLayer.string = p.overflowCount > 0 ? Self.outlinedLabel("+\(p.overflowCount)") : nil
        badgeLayer.isHidden = p.overflowCount == 0
    }

    func tickTail() {
        guard placement.pose == .sitting else { return }
        tailToggle.toggle()
        tailA.isHidden = tailToggle
        tailB.isHidden = !tailToggle
    }

    /// 흰 글자 + 검은 외곽선(배경 박스 없음). 음수 strokeWidth = fill + stroke.
    private static func outlinedLabel(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black.withAlphaComponent(0.85),
            .strokeWidth: -3,
        ])
    }
}
```

- [ ] **Step 3: 빌드 확인**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` (경고 없이. `@MainActor` 관련 에러가 나면 `override init(layer:)` 에 `nonisolated` 가 아니라 `@MainActor` 컨텍스트에서 호출되도록 그대로 두고, 에러 메시지의 지시대로 `MainActor.assumeIsolated` 를 쓴다.)

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeCats/CatShapes.swift Sources/ClaudeCats/CatLayer.swift
git commit -m "feat: 벡터 고양이 도형과 CatLayer"
```

---

### Task 9: DesktopWindow + AppController + main (화면에 고양이 표시)

**Files:**
- Create: `Sources/ClaudeCats/DesktopWindow.swift`
- Create: `Sources/ClaudeCats/AppController.swift`
- Create: `Sources/ClaudeCats/AppDelegate.swift`
- Modify: `Sources/ClaudeCats/main.swift` (전체 교체)

**Interfaces:**
- Consumes: `StateCollector`, `Scene`, `LayoutDiffer`, `PollingMode`, `CatLayer`.
- Produces:
  ```swift
  @MainActor final class DesktopWindow {
      init()
      var screenSize: CGSize
      func apply(_ layout: Layout)       // diff 반영 + 꼬리 타이머 시작/정지
      func refitToScreen()               // 디스플레이 변경 시
  }
  @MainActor final class AppController {
      init(collector: StateCollector, window: DesktopWindow)
      var onSnapshot: ((Snapshot) -> Void)?   // 메뉴 요약용
      func setMode(_ mode: PollingMode)        // 타이머 재스케줄, suspended 아니면 즉시 1회 폴링
      func pollNow()
  }
  ```

- [ ] **Step 1: DesktopWindow.swift 작성**

`Sources/ClaudeCats/DesktopWindow.swift`:
```swift
import AppKit
import ClaudeCatsCore

/// 바탕화면 위·아이콘 아래 투명 창. 레이어 diff 만 반영하고 60fps 루프는 없다.
@MainActor
final class DesktopWindow {
    private let window: NSWindow
    private let rootLayer = CALayer()
    private var layers: [String: CatLayer] = [:]
    private var layout = Layout(cats: [])
    private var tailTimer: DispatchSourceTimer?

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        rootLayer.contentsScale = screen.backingScaleFactor
        view.layer = rootLayer          // layer-hosting: wantsLayer 보다 먼저 대입
        view.wantsLayer = true
        window.contentView = view
        window.orderFrontRegardless()
    }

    var screenSize: CGSize { window.frame.size }

    func refitToScreen() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        window.setFrame(screen.frame, display: true)
        rootLayer.contentsScale = screen.backingScaleFactor
    }

    func apply(_ new: Layout) {
        let diff = LayoutDiffer.diff(from: layout, to: new)
        layout = new
        guard !diff.isEmpty else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for id in diff.removed {
            guard let layer = layers.removeValue(forKey: id) else { continue }
            fadeOutAndRemove(layer)
        }
        for cat in diff.updated {
            layers[cat.id]?.apply(cat)
        }
        for cat in diff.added {
            let layer = CatLayer(placement: cat, contentsScale: rootLayer.contentsScale)
            layer.opacity = 0
            rootLayer.addSublayer(layer)
            layers[cat.id] = layer
            fadeIn(layer)
        }
        CATransaction.commit()

        updateTailTimer()
    }

    private func fadeIn(_ layer: CALayer) {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 0
        anim.toValue = 1
        anim.duration = 0.3
        layer.opacity = 1
        layer.add(anim, forKey: "fade")
    }

    private func fadeOutAndRemove(_ layer: CALayer) {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1
        anim.toValue = 0
        anim.duration = 0.3
        anim.isRemovedOnCompletion = false
        anim.fillMode = .forwards
        layer.add(anim, forKey: "fade")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            layer.removeFromSuperlayer()
        }
    }

    // MARK: - 꼬리 애니메이션 (1초 주기, animated 고양이가 있을 때만)

    private func updateTailTimer() {
        let hasAnimated = layers.values.contains { $0.placement.animated }
        if hasAnimated, tailTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
            timer.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.tickTails() }
            }
            timer.resume()
            tailTimer = timer
        } else if !hasAnimated, let timer = tailTimer {
            timer.cancel()
            tailTimer = nil
        }
    }

    private func tickTails() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in layers.values where layer.placement.animated {
            layer.tickTail()
        }
        CATransaction.commit()
    }
}
```

- [ ] **Step 2: AppController.swift 작성**

`Sources/ClaudeCats/AppController.swift`:
```swift
import AppKit
import ClaudeCatsCore
import os

/// 폴링 타이머를 돌리고 Snapshot → Layout → 창 반영을 잇는다.
@MainActor
final class AppController {
    private let collector: StateCollector
    private let window: DesktopWindow
    private let queue = DispatchQueue(label: "claude-cats.collector", qos: .utility)
    private let log = Logger(subsystem: "claude-cats", category: "controller")
    private var timer: DispatchSourceTimer?
    private var mode: PollingMode = .suspended
    private var lastSnapshot: Snapshot?
    private var lastAnimationsEnabled = false

    var onSnapshot: ((Snapshot) -> Void)?

    init(collector: StateCollector, window: DesktopWindow) {
        self.collector = collector
        self.window = window
    }

    func setMode(_ newMode: PollingMode) {
        guard newMode != mode else { return }
        mode = newMode
        timer?.cancel()
        timer = nil
        log.info("polling mode: \(String(describing: newMode), privacy: .public)")

        if let snapshot = lastSnapshot, lastAnimationsEnabled != newMode.animationsEnabled {
            render(snapshot)
        }

        guard let interval = newMode.interval else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(Int(interval * 1000 / 3))
        )
        source.setEventHandler { [collector, weak self] in
            let snapshot = Self.collectTimed(collector)
            DispatchQueue.main.async { self?.handle(snapshot) }
        }
        source.resume()
        timer = source
        pollNow()
    }

    func pollNow() {
        queue.async { [collector, weak self] in
            let snapshot = Self.collectTimed(collector)
            DispatchQueue.main.async { self?.handle(snapshot) }
        }
    }

    func screenChanged() {
        window.refitToScreen()
        if let snapshot = lastSnapshot { render(snapshot) }
    }

    private nonisolated static func collectTimed(_ collector: StateCollector) -> Snapshot {
        let start = ContinuousClock.now
        let snapshot = collector.collect(now: Date())
        let elapsed = ContinuousClock.now - start
        if elapsed > .milliseconds(200) {
            Logger(subsystem: "claude-cats", category: "controller")
                .warning("slow tick: \(elapsed, privacy: .public)")
        }
        return snapshot
    }

    private func handle(_ snapshot: Snapshot) {
        guard snapshot != lastSnapshot || lastAnimationsEnabled != mode.animationsEnabled else { return }
        render(snapshot)
    }

    private func render(_ snapshot: Snapshot) {
        lastSnapshot = snapshot
        lastAnimationsEnabled = mode.animationsEnabled
        let layout = Scene.layout(snapshot, screenSize: window.screenSize, animationsEnabled: mode.animationsEnabled)
        window.apply(layout)
        onSnapshot?(snapshot)
    }
}
```

- [ ] **Step 3: AppDelegate.swift 와 main.swift 작성**

`Sources/ClaudeCats/AppDelegate.swift`:
```swift
import AppKit
import ClaudeCatsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: DesktopWindow!
    private var controller: AppController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let collector = StateCollector(
            fileSystem: RealFileSystem(),
            claudeDir: home.appendingPathComponent(".claude")
        )
        window = DesktopWindow()
        controller = AppController(collector: collector, window: window)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.screenChanged() }
        }

        controller.setMode(.normal)   // Task 10 에서 PowerMonitor 로 교체
    }
}
```

`Sources/ClaudeCats/main.swift` (전체 교체):
```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [ ] **Step 4: 빌드 + 실행 + 시각 확인**

Run: `swift build 2>&1 | tail -3 && (swift run > /dev/null 2>&1 &) && sleep 5 && screencapture -x /tmp/claude-cats-check.png && echo captured`
Expected: `Build complete!`, 바탕화면 하단에 세션 수만큼 고양이(busy = 앉은 자세, idle = 웅크림)와 이름 라벨. 캡처 이미지를 `Read` 로 열어 확인한다. 고양이가 데스크탑 아이콘 **아래**에 있는지(아이콘이 고양이를 가림) 확인.

확인 후 종료: `pkill -f "\.build/.*ClaudeCats"`.

문제 시 흔한 원인:
- 아무것도 안 보임 → `window.level` 을 임시로 `.floating` 으로 바꿔 렌더링 자체를 확인한 뒤 되돌린다.
- 고양이가 위아래 뒤집힘 → `rootLayer.isGeometryFlipped` 가 true 로 되어 있는지 확인(false 여야 한다).
- 라벨이 흐릿함 → `contentsScale` 이 서브레이어에 전달됐는지 확인.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeCats
git commit -m "feat: 데스크탑 투명 창에 세션 고양이 표시, 폴링 컨트롤러"
```

---

### Task 10: PowerMonitor + 전원 정책 연결

**Files:**
- Create: `Sources/ClaudeCats/PowerMonitor.swift`
- Modify: `Sources/ClaudeCats/AppDelegate.swift`
- Modify: `Sources/ClaudeCats/AppController.swift` (틱마다 배터리 재확인 훅)

**Interfaces:**
- Consumes: `PowerState`, `PowerPolicy`, `PollingMode`, `AppController.setMode`.
- Produces:
  ```swift
  @MainActor final class PowerMonitor {
      private(set) var state: PowerState
      var onChange: ((PowerState) -> Void)?
      init()
      func setPaused(_ paused: Bool)
      func refreshPowerSource()           // 배터리/AC 재확인. 폴링 틱마다 호출됨
      nonisolated static func isOnBattery() -> Bool
  }
  ```
  배터리 전환은 IOKit 알림 대신 **폴링 틱마다** `refreshPowerSource()` 로 확인한다(C 콜백 없이 단순, 최대 10초 지연 허용). 스펙 6절과 일치하도록 스펙에 이 결정을 반영한다(Task 12).

- [ ] **Step 1: PowerMonitor.swift 작성**

`Sources/ClaudeCats/PowerMonitor.swift`:
```swift
import AppKit
import IOKit.ps
import ClaudeCatsCore

/// 시스템 알림을 PowerState 로 모은다. 상태가 바뀔 때만 onChange 를 부른다.
@MainActor
final class PowerMonitor {
    private(set) var state: PowerState
    var onChange: ((PowerState) -> Void)?
    private var observers: [Any] = []

    init() {
        state = PowerState(
            onBattery: Self.isOnBattery(),
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        subscribe()
    }

    func setPaused(_ paused: Bool) {
        update { $0.userPaused = paused }
    }

    func refreshPowerSource() {
        let onBattery = Self.isOnBattery()
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        update { $0.onBattery = onBattery; $0.lowPowerMode = lowPower }
    }

    nonisolated static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else {
            return false
        }
        return (type as String) == kIOPSBatteryPowerValue
    }

    private func update(_ change: (inout PowerState) -> Void) {
        var next = state
        change(&next)
        guard next != state else { return }
        state = next
        onChange?(next)
    }

    private func subscribe() {
        let ws = NSWorkspace.shared.notificationCenter
        let dc = DistributedNotificationCenter.default()
        let nc = NotificationCenter.default

        func on(_ center: NotificationCenter, _ name: Notification.Name, _ change: @escaping @MainActor (inout PowerState) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update(change) }
            }
            observers.append(token)
        }

        on(ws, NSWorkspace.screensDidSleepNotification) { $0.displayAsleep = true }
        on(ws, NSWorkspace.screensDidWakeNotification) { $0.displayAsleep = false }
        on(ws, NSWorkspace.willSleepNotification) { $0.systemAsleep = true }
        on(ws, NSWorkspace.didWakeNotification) { $0.systemAsleep = false }
        on(dc, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true }
        on(dc, Notification.Name("com.apple.screenIsUnlocked")) { $0.screenLocked = false }
        on(dc, Notification.Name("com.apple.screensaver.didstart")) { $0.screenLocked = true }
        on(dc, Notification.Name("com.apple.screensaver.didstop")) { $0.screenLocked = false }
        on(nc, .NSProcessInfoPowerStateDidChange) { $0.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled }
    }
}
```

`DistributedNotificationCenter` 는 `NotificationCenter` 의 서브클래스이므로 `on(dc, ...)` 가 그대로 컴파일된다.

- [ ] **Step 2: AppController 에 틱 훅 추가**

`Sources/ClaudeCats/AppController.swift` 에 프로퍼티 추가(`onSnapshot` 아래):
```swift
    /// 매 틱(메인 큐)에서 스냅샷 처리 전에 호출. PowerMonitor.refreshPowerSource 연결용.
    var onTick: (() -> Void)?
```
`handle(_:)` 첫 줄에 추가:
```swift
        onTick?()
```

- [ ] **Step 3: AppDelegate 연결**

`Sources/ClaudeCats/AppDelegate.swift` 에서 프로퍼티 추가:
```swift
    private var power: PowerMonitor!
```
`controller.setMode(.normal)   // Task 10 에서 PowerMonitor 로 교체` 줄을 다음으로 교체:
```swift
        power = PowerMonitor()
        power.onChange = { [weak self] state in
            self?.controller.setMode(PowerPolicy.mode(for: state))
        }
        controller.onTick = { [weak self] in self?.power.refreshPowerSource() }
        controller.setMode(PowerPolicy.mode(for: power.state))
```

- [ ] **Step 4: 빌드 + 동작 확인**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

Run (별도 터미널에서 로그 관찰):
```bash
(swift run > /dev/null 2>&1 &)
log stream --predicate 'subsystem == "claude-cats"' --style compact &
sleep 3; pmset displaysleepnow; sleep 5
```
Expected: 로그에 `polling mode: suspended` 가 찍히고, 키 입력으로 깨우면 `polling mode: normal`(배터리면 `lowPower`) 이 찍힌다. 확인 후 `pkill -f "\.build/.*ClaudeCats"; kill %1`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeCats
git commit -m "feat: PowerMonitor 로 잠금/슬립/배터리에 따라 폴링·애니메이션 제어"
```

---

### Task 11: 메뉴바 메뉴

**Files:**
- Create: `Sources/ClaudeCats/StatusMenu.swift`
- Modify: `Sources/ClaudeCats/AppDelegate.swift`

**Interfaces:**
- Consumes: `Snapshot`, `PowerMonitor.setPaused`, `AppController.pollNow`.
- Produces:
  ```swift
  @MainActor final class StatusMenu: NSObject {
      init(onPauseToggle: @escaping (Bool) -> Void, onRefresh: @escaping () -> Void)
      func update(with snapshot: Snapshot)   // "고양이 N마리 · 작업 중 M"
  }
  ```

- [ ] **Step 1: StatusMenu.swift 작성**

`Sources/ClaudeCats/StatusMenu.swift`:
```swift
import AppKit
import ServiceManagement
import ClaudeCatsCore

@MainActor
final class StatusMenu: NSObject {
    private let item: NSStatusItem
    private let summaryItem = NSMenuItem(title: "고양이 0마리", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "일시정지", action: #selector(togglePause), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "로그인 시 시작", action: #selector(toggleLogin), keyEquivalent: "")
    private let onPauseToggle: (Bool) -> Void
    private let onRefresh: () -> Void
    private var paused = false

    init(onPauseToggle: @escaping (Bool) -> Void, onRefresh: @escaping () -> Void) {
        self.onPauseToggle = onPauseToggle
        self.onRefresh = onRefresh
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let image = NSImage(systemSymbolName: "cat", accessibilityDescription: "Claude Cats")
            ?? NSImage(systemSymbolName: "pawprint", accessibilityDescription: "Claude Cats")
        item.button?.image = image

        let menu = NSMenu()
        summaryItem.isEnabled = false
        menu.addItem(summaryItem)
        menu.addItem(.separator())
        menu.addItem(pauseItem)
        let refresh = NSMenuItem(title: "지금 새로고침", action: #selector(refresh), keyEquivalent: "r")
        menu.addItem(refresh)
        menu.addItem(.separator())
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for entry in [pauseItem, refresh, loginItem] { entry.target = self }
        item.menu = menu
        updateLoginState()
    }

    func update(with snapshot: Snapshot) {
        let busy = snapshot.sessions.filter { $0.status == .busy }.count
        let kittens = snapshot.sessions.reduce(0) { $0 + $1.subagents.count }
        var text = "고양이 \(snapshot.sessions.count)마리 · 작업 중 \(busy)"
        if kittens > 0 { text += " · 새끼 \(kittens)" }
        summaryItem.title = text
    }

    @objc private func togglePause() {
        paused.toggle()
        pauseItem.title = paused ? "재개" : "일시정지"
        onPauseToggle(paused)
    }

    @objc private func refresh() {
        onRefresh()
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "로그인 시 시작 설정 실패"
            alert.informativeText = "앱 번들(.app)로 실행 중일 때만 등록할 수 있습니다.\n\(error.localizedDescription)"
            alert.runModal()
        }
        updateLoginState()
    }

    private func updateLoginState() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
```

- [ ] **Step 2: AppDelegate 연결**

`Sources/ClaudeCats/AppDelegate.swift` 프로퍼티 추가:
```swift
    private var menu: StatusMenu!
```
`power = PowerMonitor()` 줄 **앞에** 추가:
```swift
        menu = StatusMenu(
            onPauseToggle: { [weak self] paused in self?.power.setPaused(paused) },
            onRefresh: { [weak self] in self?.controller.pollNow() }
        )
        controller.onSnapshot = { [weak self] snapshot in self?.menu.update(with: snapshot) }
```

- [ ] **Step 3: 빌드 + 확인**

Run: `swift build 2>&1 | tail -3 && (swift run > /dev/null 2>&1 &) && sleep 3 && echo running`
Expected: 메뉴바에 고양이 아이콘. 클릭하면 "고양이 N마리 · 작업 중 M" 요약. "일시정지" → 꼬리가 멈추고 `log stream` 에 `polling mode: suspended`. "재개" → 다시 `normal`. 확인 후 `pkill -f "\.build/.*ClaudeCats"`.

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeCats
git commit -m "feat: 메뉴바 메뉴(요약, 일시정지, 새로고침, 로그인 시 시작, 종료)"
```

---

### Task 12: .app 번들 스크립트 + 전력 측정 + 스펙 갱신

**Files:**
- Create: `scripts/bundle.sh`
- Create: `README.md`
- Modify: `docs/superpowers/specs/2026-09-07-claude-cats-wallpaper-design.md` (6절 배터리 감지 방식, 측정 기록)

- [ ] **Step 1: bundle.sh 작성**

`scripts/bundle.sh`:
```bash
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
```

Run: `chmod +x scripts/bundle.sh && ./scripts/bundle.sh`
Expected: `built dist/ClaudeCats.app`. `.gitignore` 에 `dist/` 추가.

- [ ] **Step 2: 번들 실행 + 10분 전력 측정**

```bash
open dist/ClaudeCats.app
sleep 600
PID=$(pgrep -x ClaudeCats)
ps -o pid,%cpu,%mem,rss,etime -p "$PID"
sudo powermetrics --samplers tasks -i 5000 -n 6 2>/dev/null | grep -E "ClaudeCats|Name" | head -8
```
Expected: `%cpu` 0.0~0.2, `rss` 30MB(30720 KB) 이하. powermetrics 의 `ClaudeCats` 행 CPU ms/s 가 5 이하, Energy Impact 컬럼이 1.0 이하. Activity Monitor → 에너지 탭에서 "에너지 영향" 이 "낮음" 인지 눈으로 확인.

- [ ] **Step 3: 측정값과 배터리 감지 방식을 스펙에 기록**

스펙 6절 표 아래 문장
```
- 전원: `IOPSCopyPowerSourcesInfo` + `IOPSNotificationCreateRunLoopSource` 로 변화 알림.
```
을 다음으로 교체:
```
- 전원: 폴링 틱마다 `IOPSCopyPowerSourcesInfo` 로 배터리/AC 를 재확인한다(IOKit 알림 콜백 대신
  단순화, 최대 10초 지연 허용). 잠금/슬립 복귀 시에도 즉시 폴링하므로 그때 갱신된다.
```
스펙 끝 "## 측정 기록" 아래 `(구현 후 채움)` 을 실제 값으로 교체:
```
| 항목 | 값 | 측정일 |
|---|---|---|
| 세션 수 / busy 수 | N / M | 2026-09-xx |
| 10분 평균 CPU (%cpu) | x.x | |
| RSS | xx MB | |
| powermetrics CPU ms/s | x | |
| Activity Monitor 에너지 영향 | 낮음 | |
```

- [ ] **Step 4: README.md 작성**

```markdown
# Claude Cats

이 Mac 의 Claude Code 세션을 바탕화면 위 벡터 고양이로 보여주는 메뉴바 앱.
세션 하나 = 고양이 한 마리(작업 중이면 앉아서 꼬리를 흔들고, idle 이면 잠), 실행 중
서브에이전트 = 옆의 새끼 고양이.

## 빌드 / 실행

```bash
swift test                # 단위 테스트
swift run                 # 개발 실행
./scripts/bundle.sh       # dist/ClaudeCats.app 생성
open dist/ClaudeCats.app
```

## 동작 원리

`~/.claude/sessions/*.json` 을 3초마다 stat 폴링(내용은 mtime 이 바뀐 파일만 파싱),
busy 세션의 `~/.claude/projects/<cwd>/<sessionId>/subagents/*.jsonl` mtime 이 15초 이내면
새끼 고양이로 표시. 화면 잠금/슬립 시 정지, 배터리/저전력 시 10초 폴링 + 애니메이션 끔.

설계: `docs/superpowers/specs/2026-09-07-claude-cats-wallpaper-design.md`
```

- [ ] **Step 5: Commit**

```bash
git add scripts/bundle.sh README.md .gitignore docs
git commit -m "chore: .app 번들 스크립트, README, 전력 측정 기록"
```

---

## Self-Review

**Spec coverage**
- 2절 구조(StateCollector/Scene/DesktopWindow/PowerPolicy) → Task 3–7, 9, 10 ✓
- 3절 수집 규칙(pid 생존, interactive, 미지 status, busy 만 스캔, 15초, cwd 인코딩 폴백 + 60초 재시도, meta 캐시, mtime 캐시) → Task 3, 4 ✓
- 4절 배치(슬롯 140, 하단 40, 선형 탐사, 두 번째 줄, 새끼 3마리 + `+n`, 팔레트 8, FNV-1a) → Task 5 ✓
- 5절 창/그리기/애니메이션(레벨, 그림자 없음, 마우스 무시, 레이어 diff, 페이드 0.3s, 1초 꼬리 타이머, 0마리면 정지) → Task 8, 9 ✓
- 6절 전력 정책(3/10/정지, 잠금·슬립·스크린세이버, 저전력, 재개 시 즉시 폴링) → Task 6, 10 ✓. 배터리 알림은 IOKit 콜백 대신 틱마다 확인으로 바꿨고 Task 12 에서 스펙에 반영.
- 7절 메뉴바 → Task 11 ✓
- 8절 에러 처리(건너뛰기, 빈 스냅샷, 200ms 경고) → Task 3, 9 ✓
- 9절 테스트 목록 → Task 1–7 단위 테스트, Task 12 수동 측정 ✓
- 10절 구조 → 스펙의 하위 디렉터리(App/, Collector/ …) 대신 평면 구조를 썼다. 파일 수가 적어 디렉터리가 오히려 방해라 판단. 스펙 10절과 다르지만 의도적.

**Placeholder scan**: "TBD/TODO/나중에" 없음. Task 12 측정 표의 `x.x` 는 실행자가 실제 값으로 채우는 칸이며 지시가 명시돼 있다.

**Type consistency**: `CatPlacement` 필드(id/origin/scale/pose/paletteIndex/label/animated/overflowCount)가 Task 5, 7, 8 에서 동일. `PollingMode.interval/animationsEnabled` 가 Task 6, 9 에서 동일. `AppController.setMode/pollNow/onSnapshot/onTick` 이 Task 9–11 에서 동일. `PowerMonitor.setPaused/refreshPowerSource/state/onChange` 가 Task 10, 11 에서 동일.
