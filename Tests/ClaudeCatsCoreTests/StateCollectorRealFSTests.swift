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

    /// `modified` 를 주면 그 시각으로 mtime 을 박는다 — 이벤트 시각이 곧 알림 시각이다.
    func writeEvent(_ root: URL, _ name: String, _ json: String, modified: Date? = nil) throws {
        let dir = root.appendingPathComponent("claude-cats").appendingPathComponent("events")
        let url = dir.appendingPathComponent(name + ".json")
        try Data((json + "\n").utf8).write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
    }

    func eventCount(_ root: URL) throws -> Int {
        let dir = root.appendingPathComponent("claude-cats").appendingPathComponent("events")
        return try FileManager.default.contentsOfDirectory(atPath: dir.path).count
    }

    /// 권한을 승인하면 Claude 가 도구를 돌리고 transcript 에 append 한다. 그 mtime 변화가
    /// 알림을 푸는 신호다 — 다만 알림 직후(`alertClearGrace` 안)에 붙는 줄은 알림을 띄운
    /// 그 턴이 자기 기록을 마저 쓰는 것이라 무시해야 한다.
    ///
    /// 시각은 전부 진짜 파일 mtime 이다(알림 시각 = 이벤트 파일, 해제 판정 = transcript).
    /// 테스트가 몇 초씩 기다리지 않게 mtime 을 직접 박아 둔다.
    @Test func permissionAlertClearsOnlyAfterTheGraceWindow() throws {
        try withClaudeDir(status: "busy") { root, collector in
            let fired = Date().addingTimeInterval(-60)      // 훅이 1분 전에 터졌다고 치자
            let transcript = root.appendingPathComponent("projects").appendingPathComponent(encoded)
                .appendingPathComponent(sessionId + ".jsonl")
            // 알림 **전에** 마지막으로 쓰인 상태로 되돌린다(하네스는 지금 시각으로 만든다).
            try FileManager.default.setAttributes(
                [.modificationDate: fired.addingTimeInterval(-10)], ofItemAtPath: transcript.path)
            try writeEvent(root, "0001", Fixtures.notification(
                type: "permission_prompt", message: "Claude needs your permission to run Bash",
                sessionId: sessionId), modified: fired)

            let alerted = collector.collect(now: Date()).sessions
            #expect(alerted.count == 1)
            #expect(alerted[0].alert?.kind == .permission)
            #expect(alerted[0].alert?.since == fired)       // 틱 시각이 아니라 훅이 터진 때
            #expect(try eventCount(root) == 0)              // RealFileSystem.remove 가 실제로 지웠다

            // 우리가 만든 transcript 에 한 줄 덧붙인다(= 그 턴이 기록을 마저 쓴다).
            try append(transcript, "still writing", at: fired.addingTimeInterval(2))
            #expect(collector.collect(now: Date()).sessions[0].alert != nil)

            // 유예를 넘겨 붙은 줄은 "승인하고 도구가 돌았다"는 뜻이다.
            try append(transcript, "ran the tool", at: fired.addingTimeInterval(6))
            #expect(collector.collect(now: Date()).sessions[0].alert == nil)
        }
    }

    /// transcript 에 한 줄 붙이고 mtime 을 원하는 시각으로 박는다.
    func append(_ url: URL, _ text: String, at modified: Date) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((Fixtures.messageLine(text, sessionId: sessionId) + "\n").utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
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
