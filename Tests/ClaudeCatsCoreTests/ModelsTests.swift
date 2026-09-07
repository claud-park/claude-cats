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
