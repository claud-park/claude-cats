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
