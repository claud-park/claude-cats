import Testing
import Foundation
@testable import ClaudeCatsCore

/// 훅 경로를 **진짜 파일시스템**에 대고 한 바퀴 돌린다 — 이벤트 파일을 실제로 쓰고, 실제로
/// 지워지는지 보고, transcript 를 실제로 건드려 알림이 풀리는지 본다.
/// FakeFileSystem 은 mtime 을 마음대로 정할 수 있어서 놓치는 것들(RealFileSystem.remove,
/// 실제 mtime 해상도)이 여기서 걸린다.
@Suite struct StateCollectorRealFSTests {
    /// 살아 있는 pid 가 필요하다. 테스트 프로세스 자신이면 확실하다.
    let pid = ProcessInfo.processInfo.processIdentifier
    let sessionId = "real-fs-session"
    let cwd = "/Users/me/proj"
    let encoded = "-Users-me-proj"

    /// `~/.claude` 흉내를 낸 임시 디렉터리. 진짜 `~/.claude` 는 절대 건드리지 않는다.
    func withClaudeDir(status: String, _ body: (URL, StateCollector) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-cats-realfs-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessions = root.appendingPathComponent("sessions")
        let project = root.appendingPathComponent("projects").appendingPathComponent(encoded)
        let events = root.appendingPathComponent("claude-cats").appendingPathComponent("events")
        for dir in [sessions, project, events] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try Data(Fixtures.sessionJSON(pid: pid, id: sessionId, name: "real", cwd: cwd, status: status).utf8)
            .write(to: sessions.appendingPathComponent("\(pid).json"))
        try Data((Fixtures.titleLine("real title", sessionId: sessionId) + "\n").utf8)
            .write(to: project.appendingPathComponent(sessionId + ".jsonl"))

        try body(root, StateCollector(fileSystem: RealFileSystem(), claudeDir: root))
    }

    func writeEvent(_ root: URL, _ name: String, _ json: String) throws {
        let dir = root.appendingPathComponent("claude-cats").appendingPathComponent("events")
        try Data((json + "\n").utf8).write(to: dir.appendingPathComponent(name + ".json"))
    }

    func eventCount(_ root: URL) throws -> Int {
        let dir = root.appendingPathComponent("claude-cats").appendingPathComponent("events")
        return try FileManager.default.contentsOfDirectory(atPath: dir.path).count
    }

    /// 권한을 승인하면 Claude 가 도구를 돌리고 transcript 에 append 한다. 그 mtime 변화가
    /// 알림을 푸는 신호다 — 여기서는 그 append 를 흉내 낸다.
    @Test func permissionAlertClearsWhenTheTranscriptGrows() throws {
        try withClaudeDir(status: "busy") { root, collector in
            try writeEvent(root, "0001", Fixtures.notification(
                type: "permission_prompt", message: "Claude needs your permission to run Bash",
                sessionId: sessionId))

            let start = Date()
            let alerted = collector.collect(now: start).sessions
            #expect(alerted.count == 1)
            #expect(alerted[0].alert?.kind == .permission)
            #expect(try eventCount(root) == 0)      // RealFileSystem.remove 가 실제로 지웠다

            // transcript 가 그대로면 계속 기다리는 중이다.
            #expect(collector.collect(now: start.addingTimeInterval(3)).sessions[0].alert != nil)

            // 우리가 만든 transcript 에 한 줄 덧붙인다(= 도구가 돌았다).
            let transcript = root.appendingPathComponent("projects").appendingPathComponent(encoded)
                .appendingPathComponent(sessionId + ".jsonl")
            let handle = try FileHandle(forWritingTo: transcript)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((Fixtures.messageLine("ran it", sessionId: sessionId) + "\n").utf8))
            try handle.close()

            #expect(collector.collect(now: Date().addingTimeInterval(1)).sessions[0].alert == nil)
        }
    }

    /// 새끼 id 는 transcript 경로에서 뽑는다. 진짜 파일로도 한 번 확인한다.
    @Test func subagentStartAndStopRoundTripOnDisk() throws {
        try withClaudeDir(status: "idle") { root, collector in
            try writeEvent(root, "0001", Fixtures.subagentEvent(
                "SubagentStart", agentId: "opaque-hook-id", agentType: "explore",
                sessionId: sessionId, transcriptId: "kitten-1"))
            let started = collector.collect(now: Date()).sessions[0].subagents
            #expect(started.map(\.id) == ["kitten-1"])
            #expect(started[0].description == "explore")
            #expect(try eventCount(root) == 0)

            try writeEvent(root, "0002", Fixtures.subagentEvent(
                "SubagentStop", agentId: "opaque-hook-id",
                sessionId: sessionId, transcriptId: "kitten-1"))
            #expect(collector.collect(now: Date()).sessions[0].subagents.isEmpty)
            #expect(try eventCount(root) == 0)
        }
    }

    /// 이벤트 디렉터리가 아예 없으면(훅 미설치) 아무 일도 없어야 한다 — 만들지도 않는다.
    @Test func missingEventsDirIsNotCreated() throws {
        try withClaudeDir(status: "idle") { root, collector in
            let events = root.appendingPathComponent("claude-cats").appendingPathComponent("events")
            try FileManager.default.removeItem(at: events)
            #expect(collector.collect(now: Date()).sessions.count == 1)
            #expect(FileManager.default.fileExists(atPath: events.path) == false)
        }
    }
}
