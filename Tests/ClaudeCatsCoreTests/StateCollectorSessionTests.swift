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

    @Test func nonInteractiveFileNotReparsedWhenMtimeUnchanged() {
        let fs = FakeFileSystem()
        let path = Fixtures.sessionPath(pid: 10)
        fs.add(path, Fixtures.sessionJSON(pid: 10, id: "s1", name: "a", cwd: "/p", kind: "background"), modified: now)
        fs.alivePids = [10]
        let c = makeCollector(fs)
        #expect(c.collect(now: now).sessions.isEmpty)
        #expect(c.collect(now: now.addingTimeInterval(3)).sessions.isEmpty)
        #expect(fs.readCount[path] == 1)

        fs.add(path, Fixtures.sessionJSON(pid: 10, id: "s1", name: "a", cwd: "/p", kind: "interactive"), modified: now.addingTimeInterval(5))
        let snap = c.collect(now: now.addingTimeInterval(6))
        #expect(fs.readCount[path] == 2)
        #expect(snap.sessions.count == 1)
    }

    @Test func brokenJsonNotReparsedWhenMtimeUnchanged() {
        let fs = FakeFileSystem()
        let path = Fixtures.sessionPath(pid: 10)
        fs.add(path, "{not json", modified: now)
        fs.alivePids = [10]
        let c = makeCollector(fs)
        #expect(c.collect(now: now).sessions.isEmpty)
        #expect(c.collect(now: now.addingTimeInterval(3)).sessions.isEmpty)
        #expect(fs.readCount[path] == 1)

        fs.add(path, Fixtures.sessionJSON(pid: 10, id: "s1", name: "a", cwd: "/p"), modified: now.addingTimeInterval(5))
        let snap = c.collect(now: now.addingTimeInterval(6))
        #expect(fs.readCount[path] == 2)
        #expect(snap.sessions.count == 1)
    }

    @Test func sessionCacheSurvivesTransientListFailure() {
        let fs = FakeFileSystem()
        let path = Fixtures.sessionPath(pid: 10)
        fs.add(path, Fixtures.sessionJSON(pid: 10, id: "s1", name: "a", cwd: "/p"), modified: now)
        fs.alivePids = [10]
        let c = makeCollector(fs)
        #expect(c.collect(now: now).sessions.count == 1)

        fs.remove(path)
        #expect(c.collect(now: now.addingTimeInterval(3)).sessions.isEmpty)

        fs.add(path, Fixtures.sessionJSON(pid: 10, id: "s1", name: "a", cwd: "/p"), modified: now)
        let snap = c.collect(now: now.addingTimeInterval(6))
        #expect(snap.sessions.count == 1)
        #expect(fs.readCount[path] == 1)
    }

    @Test func sortTiebreaksOnIdForEqualNames() {
        let fs = FakeFileSystem()
        fs.add(Fixtures.sessionPath(pid: 10), Fixtures.sessionJSON(pid: 10, id: "b", name: "same", cwd: "/p"), modified: now)
        fs.add(Fixtures.sessionPath(pid: 11), Fixtures.sessionJSON(pid: 11, id: "a", name: "same", cwd: "/p"), modified: now)
        fs.alivePids = [10, 11]
        #expect(makeCollector(fs).collect(now: now).sessions.map(\.id) == ["a", "b"])
    }
}
