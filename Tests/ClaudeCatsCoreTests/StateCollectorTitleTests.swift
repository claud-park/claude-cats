import Testing
import Foundation
@testable import ClaudeCatsCore

@Suite struct StateCollectorTitleTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let cwd = "/Users/me/proj_x"
    let encoded = "-Users-me-proj-x"

    var transcript: String { Fixtures.transcriptPath(encodedCwd: encoded, sessionId: "sess") }

    func makeFS(status: String = "idle") -> FakeFileSystem {
        let fs = FakeFileSystem()
        fs.add(Fixtures.sessionPath(pid: 10),
               Fixtures.sessionJSON(pid: 10, id: "sess", name: "a", cwd: cwd, status: status),
               modified: now)
        fs.alivePids = [10]
        return fs
    }

    func collector(_ fs: FakeFileSystem) -> StateCollector {
        StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
    }

    @Test func titleParsedFromTail() {
        let fs = makeFS()
        fs.add(transcript, [
            Fixtures.messageLine("hello"),
            Fixtures.messageLine("world"),
            Fixtures.titleLine("A"),
            Fixtures.promptLine("do the thing"),
            Fixtures.titleLine("B"),
            "",
        ].joined(separator: "\n"), modified: now)
        #expect(collector(fs).collect(now: now).sessions[0].title == "B")
    }

    @Test func truncatedFirstLineIgnored() {
        let fs = makeFS()
        // 앞에 300KB 짜리 한 줄 → 256KB 꼬리는 그 줄 한가운데서 시작한다.
        let dummy = Fixtures.messageLine(String(repeating: "x", count: 300_000))
        fs.add(transcript, [dummy, Fixtures.titleLine("late"), ""].joined(separator: "\n"), modified: now)
        #expect(collector(fs).collect(now: now).sessions[0].title == "late")
    }

    @Test func notReReadWhenMtimeUnchanged() {
        let fs = makeFS()
        fs.add(transcript, Fixtures.messageLine("x") + "\n" + Fixtures.titleLine("A") + "\n", modified: now)
        let c = collector(fs)
        #expect(c.collect(now: now).sessions[0].title == "A")
        #expect(c.collect(now: now.addingTimeInterval(60)).sessions[0].title == "A")
        #expect(fs.readCount[transcript] == 1)
    }

    @Test func notReReadWithin10SecondsEvenIfMtimeChanged() {
        let fs = makeFS()
        fs.add(transcript, Fixtures.messageLine("x") + "\n" + Fixtures.titleLine("A") + "\n", modified: now)
        let c = collector(fs)
        _ = c.collect(now: now)
        #expect(fs.readCount[transcript] == 1)

        fs.add(transcript, Fixtures.messageLine("x") + "\n" + Fixtures.titleLine("B") + "\n",
               modified: now.addingTimeInterval(4))
        #expect(c.collect(now: now.addingTimeInterval(5)).sessions[0].title == "A")
        #expect(fs.readCount[transcript] == 1)

        #expect(c.collect(now: now.addingTimeInterval(12)).sessions[0].title == "B")
        #expect(fs.readCount[transcript] == 2)
    }

    @Test func previousTitleKeptWhenTailHasNoTitle() {
        let fs = makeFS()
        fs.add(transcript, Fixtures.messageLine("x") + "\n" + Fixtures.titleLine("A") + "\n", modified: now)
        let c = collector(fs)
        #expect(c.collect(now: now).sessions[0].title == "A")

        // 긴 작업 중 — 꼬리에 제목 줄이 없다.
        fs.add(transcript, Fixtures.messageLine("y") + "\n" + Fixtures.messageLine("z") + "\n",
               modified: now.addingTimeInterval(11))
        #expect(c.collect(now: now.addingTimeInterval(12)).sessions[0].title == "A")
        #expect(fs.readCount[transcript] == 2)
    }

    /// 읽기가 실패해도 매 틱 재시도하면 안 된다. 실패도 10초 스로틀을 탄다.
    @Test func failedTailReadIsThrottledAndKeepsPreviousTitle() {
        let fs = makeFS()
        fs.add(transcript, Fixtures.messageLine("x") + "\n" + Fixtures.titleLine("A") + "\n", modified: now)
        let c = collector(fs)
        #expect(c.collect(now: now).sessions[0].title == "A")
        #expect(fs.readCount[transcript] == 1)

        // 이제부터 읽기가 계속 실패한다(권한 오류 등).
        fs.failReads.insert(transcript)
        fs.touch(transcript, modified: now.addingTimeInterval(11))
        #expect(c.collect(now: now.addingTimeInterval(12)).sessions[0].title == "A")
        #expect(fs.readCount[transcript] == 2)

        // 실패 직후 1초 뒤 — 다시 시도하지 않는다.
        #expect(c.collect(now: now.addingTimeInterval(13)).sessions[0].title == "A")
        #expect(fs.readCount[transcript] == 2)

        // mtime 이 또 바뀌고 10초가 지나야 비로소 한 번 더 시도한다.
        fs.touch(transcript, modified: now.addingTimeInterval(23))
        #expect(c.collect(now: now.addingTimeInterval(24)).sessions[0].title == "A")
        #expect(fs.readCount[transcript] == 3)
    }

    @Test func idleSessionsGetTitlesToo() {
        let fs = makeFS(status: "idle")
        fs.add(transcript, Fixtures.messageLine("x") + "\n" + Fixtures.titleLine("zzz") + "\n", modified: now)
        let snap = collector(fs).collect(now: now)
        #expect(snap.sessions[0].status == .idle)
        #expect(snap.sessions[0].title == "zzz")
    }

    @Test func transcriptFoundViaGlobWhenEncodedCwdMisses() {
        let fs = makeFS()
        // subagents 디렉터리 없이 transcript 만 있는, 인코딩 추정이 빗나간 프로젝트.
        let path = Fixtures.transcriptPath(encodedCwd: "-weird", sessionId: "sess")
        fs.add(path, Fixtures.messageLine("x") + "\n" + Fixtures.titleLine("found") + "\n", modified: now)
        #expect(collector(fs).collect(now: now).sessions[0].title == "found")
    }

    @Test func noTranscriptGivesNilTitle() {
        let fs = makeFS()
        // 프로젝트 디렉터리는 있지만(서브에이전트만) transcript 파일은 없다.
        fs.add(Fixtures.subagentDir(encodedCwd: encoded, sessionId: "sess") + "/agent-a.jsonl", "{}\n", modified: now)
        #expect(collector(fs).collect(now: now).sessions[0].title == nil)
    }

    @Test func titleChangeChangesSnapshotEquality() {
        func snap(_ title: String?) -> Snapshot {
            Snapshot(sessions: [Session(id: "s", pid: 1, name: "n", cwd: "/", status: .idle,
                                        subagents: [], title: title)], takenAt: now)
        }
        #expect(snap("A") != snap("B"))
        #expect(snap("A") != snap(nil))
        #expect(snap("A") == snap("A"))
    }
}
