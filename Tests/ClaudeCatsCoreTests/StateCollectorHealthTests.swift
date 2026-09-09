import Testing
import Foundation
@testable import ClaudeCatsCore

/// `Snapshot.health` — 세션 파일을 몇 개 보고 몇 개를 받아들였는지, 못 받아들인 건 왜인지.
/// 메뉴바가 "정말 세션이 없다"와 "파일은 있는데 못 읽었다"를 구분하는 근거다.
@Suite struct StateCollectorHealthTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func makeCollector(_ fs: FakeFileSystem) -> StateCollector {
        StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
    }

    /// 좋은 파일 하나, 깨진 JSON 하나, 비대화형 하나, 죽은 pid 하나 — 네 가지가 각자 칸으로.
    @Test func countsEachDropReason() {
        let fs = FakeFileSystem()
        fs.add(Fixtures.sessionPath(pid: 10),
               Fixtures.sessionJSON(pid: 10, id: "s1", name: "good", cwd: "/p/a"), modified: now)
        fs.add(Fixtures.sessionPath(pid: 11), "{ 이건 JSON 이 아니다", modified: now)
        fs.add(Fixtures.sessionPath(pid: 12),
               Fixtures.sessionJSON(pid: 12, id: "s3", name: "bg", cwd: "/p/c", kind: "background"),
               modified: now)
        fs.add(Fixtures.sessionPath(pid: 13),
               Fixtures.sessionJSON(pid: 13, id: "s4", name: "dead", cwd: "/p/d"), modified: now)
        fs.alivePids = [10]

        let health = makeCollector(fs).collect(now: now).health
        #expect(health == CollectorHealth(sessionFiles: 4, accepted: 1, unreadable: 0,
                                          malformed: 1, nonInteractive: 1, deadPid: 1))
    }

    @Test func healthyRunHasNoFailures() {
        let fs = FakeFileSystem()
        fs.add(Fixtures.sessionPath(pid: 10),
               Fixtures.sessionJSON(pid: 10, id: "s1", name: "a", cwd: "/p/a"), modified: now)
        fs.alivePids = [10]

        let health = makeCollector(fs).collect(now: now).health
        #expect(health == CollectorHealth(sessionFiles: 1, accepted: 1))
        #expect(!health.readNothing)
        #expect(health.failures == 0)
    }

    /// 읽기가 던지는 파일은 unreadable 이다 — 스키마가 바뀐 게 아니라 못 연 것이다.
    @Test func readFailureCountsAsUnreadable() {
        let fs = FakeFileSystem()
        fs.add(Fixtures.sessionPath(pid: 10),
               Fixtures.sessionJSON(pid: 10, id: "s1", name: "a", cwd: "/p/a"), modified: now)
        fs.failReads = [Fixtures.sessionPath(pid: 10)]

        let health = makeCollector(fs).collect(now: now).health
        #expect(health == CollectorHealth(sessionFiles: 1, accepted: 0, unreadable: 1))
        #expect(health.readNothing)
        #expect(health.failures == 1)
    }

    /// 파일은 있는데 하나도 못 받아들인 상태 — 구조 변경을 의심해야 하는 그 상태다.
    @Test func readNothingWhenEveryFileIsMalformed() {
        let fs = FakeFileSystem()
        fs.add(Fixtures.sessionPath(pid: 10), #"{"pid":"열","kind":"interactive"}"#, modified: now)
        fs.add(Fixtures.sessionPath(pid: 11), "not json at all", modified: now)
        fs.alivePids = [10, 11]

        let snap = makeCollector(fs).collect(now: now)
        #expect(snap.sessions.isEmpty)
        #expect(snap.health.sessionFiles == 2)
        #expect(snap.health.malformed == 2)
        #expect(snap.health.readNothing)
    }

    /// 세션 파일이 아예 없으면 경고할 게 없다 — 진짜 "고양이 0마리"다.
    @Test func noSessionFilesIsNotAFailure() {
        let health = makeCollector(FakeFileSystem()).collect(now: now).health
        #expect(health == CollectorHealth())
        #expect(!health.readNothing)
    }

    /// 캐시에 걸린(= mtime 이 그대로라 다시 파싱하지 않은) 파일도 매 틱 다시 세야 한다.
    /// 안 그러면 두 번째 틱부터 경고가 사라진다.
    @Test func cachedFilesStillCount() {
        let fs = FakeFileSystem()
        fs.add(Fixtures.sessionPath(pid: 10),
               Fixtures.sessionJSON(pid: 10, id: "s1", name: "a", cwd: "/p/a"), modified: now)
        fs.add(Fixtures.sessionPath(pid: 11), "{ broken", modified: now)
        fs.add(Fixtures.sessionPath(pid: 12),
               Fixtures.sessionJSON(pid: 12, id: "s3", name: "bg", cwd: "/p/c", kind: "background"),
               modified: now)
        fs.alivePids = [10]
        let collector = makeCollector(fs)

        let first = collector.collect(now: now).health
        let second = collector.collect(now: now.addingTimeInterval(3)).health
        #expect(first == second)
        #expect(second == CollectorHealth(sessionFiles: 3, accepted: 1,
                                          malformed: 1, nonInteractive: 1))
    }

    /// health 는 스냅샷 동등성에 들어가지 않는다 — 고양이 배치가 그대로면 다시 그리지 않는다.
    /// (메뉴 줄 갱신은 AppController 가 별도 게이트로 챙긴다.)
    @Test func healthDoesNotAffectSnapshotEquality() {
        let session = Session(id: "s1", pid: 10, name: "a", cwd: "/p", status: .idle, subagents: [])
        let healthy = Snapshot(sessions: [session], takenAt: now)
        let broken = Snapshot(sessions: [session], takenAt: now,
                              health: CollectorHealth(sessionFiles: 3, accepted: 1, malformed: 2))
        #expect(healthy == broken)
    }

    /// 실패 이유를 nil 하나로 뭉개지 않는다 — "스키마가 바뀌었다"와 "대화형이 아니다"는
    /// 사용자에게 다른 얘기다.
    @Test func parseSessionDistinguishesMalformedFromNonInteractive() {
        let good = Data(Fixtures.sessionJSON(pid: 10, id: "s1", name: "a", cwd: "/p").utf8)
        let background = Data(
            Fixtures.sessionJSON(pid: 10, id: "s1", name: "a", cwd: "/p", kind: "background").utf8)

        #expect(StateCollector.parseSession(Data("{".utf8)) == .malformed)
        #expect(StateCollector.parseSession(background) == .nonInteractive)
        guard case .session(let parsed) = StateCollector.parseSession(good) else {
            Issue.record("정상 세션 파일이 .session 으로 안 나왔다")
            return
        }
        #expect(parsed.id == "s1")
    }
}
