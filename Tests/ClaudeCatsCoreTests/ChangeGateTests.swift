import Testing
@testable import ClaudeCatsCore

@Suite struct ChangeGateTests {
    @Test func firstValuePasses() {
        let gate = ChangeGate<Int>()
        #expect(gate.shouldSend(1))
    }

    @Test func sameValueBlocked() {
        let gate = ChangeGate<Int>()
        #expect(gate.shouldSend(1))
        #expect(!gate.shouldSend(1))
        #expect(!gate.shouldSend(1))
    }

    @Test func differentValuePasses() {
        let gate = ChangeGate<Int>()
        #expect(gate.shouldSend(1))
        #expect(gate.shouldSend(2))
        #expect(!gate.shouldSend(2))
        #expect(gate.shouldSend(1))
    }

    @Test func resetLetsNextValueThrough() {
        let gate = ChangeGate<Bool>()
        #expect(gate.shouldSend(true))
        #expect(!gate.shouldSend(true))
        gate.reset()
        #expect(gate.shouldSend(true))
    }

    @Test func recordUpdatesBaselineWithoutSending() {
        let gate = ChangeGate<Int>()
        gate.record(7)
        #expect(!gate.shouldSend(7))
        #expect(gate.shouldSend(8))
    }

    /// AppController 가 실제로 쓰는 타입(Snapshot)에서도 같은 규칙이 성립하는지.
    @Test func worksWithSnapshot() {
        let gate = ChangeGate<Snapshot>()
        func snap(_ name: String) -> Snapshot {
            Snapshot(sessions: [Session(id: "s", pid: 1, name: name, cwd: "/", status: .idle, subagents: [])],
                     takenAt: .distantPast)
        }
        #expect(gate.shouldSend(snap("a")))
        #expect(!gate.shouldSend(snap("a")))
        #expect(gate.shouldSend(snap("b")))
    }
}
