import Testing
import Foundation
@testable import ClaudeCatsCore

/// SubagentStart/Stop 훅으로 센 서브에이전트. mtime 휴리스틱과 합쳐지고,
/// Stop 을 받은 것은 mtime 이 아무리 싱싱해도 억제된다.
@Suite struct StateCollectorHookAgentTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let cwd = "/Users/me/proj_x"
    let encoded = "-Users-me-proj-x"

    func makeFS(status: String = "busy") -> FakeFileSystem {
        let fs = FakeFileSystem()
        fs.add(Fixtures.sessionPath(pid: 10),
               Fixtures.sessionJSON(pid: 10, id: "sess", name: "a", cwd: cwd, status: status),
               modified: now)
        fs.alivePids = [10]
        return fs
    }

    /// mtime 휴리스틱이 보는 파일. `ago` 가 15초를 넘으면 비활성이다.
    func addScannedAgent(_ fs: FakeFileSystem, id: String, ago: TimeInterval) {
        let dir = Fixtures.subagentDir(encodedCwd: encoded, sessionId: "sess")
        fs.add("\(dir)/agent-\(id).jsonl", "{}\n", modified: now.addingTimeInterval(-ago))
        fs.add("\(dir)/agent-\(id).meta.json", Fixtures.metaJSON(description: "scanned"),
               modified: now.addingTimeInterval(-ago))
    }

    func addEvent(_ fs: FakeFileSystem, _ name: String, _ json: String) {
        fs.add(Fixtures.eventPath(name), json, modified: now)
    }

    // MARK: - 훅이 세는 쪽

    @Test func subagentStartAddsAKittenEvenWithNoTranscriptAtAll() {
        let fs = makeFS()
        addEvent(fs, "1", Fixtures.subagentEvent("SubagentStart", agentId: "a1", agentType: "explore"))
        let subs = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
            .collect(now: now).sessions[0].subagents
        #expect(subs.map(\.id) == ["a1"])
        #expect(subs[0].description == "explore")
        #expect(subs[0].lastActivity == now)
    }

    /// mtime 이 오래됐어도(휴리스틱은 못 본다) 훅이 시작을 알렸으면 새끼가 붙는다.
    @Test func hookAgentSurvivesStaleTranscriptMtime() {
        let fs = makeFS()
        addScannedAgent(fs, id: "a1", ago: 600)
        addEvent(fs, "1", Fixtures.subagentEvent("SubagentStart", agentId: "a1"))
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        #expect(c.collect(now: now).sessions[0].subagents.map(\.id) == ["a1"])
        // 20분 뒤에도 Stop 이 안 왔으면 여전히 실행 중으로 본다.
        #expect(c.collect(now: now.addingTimeInterval(1200)).sessions[0].subagents.map(\.id) == ["a1"])
    }

    /// mtime 이 싱싱해도 Stop 을 받았으면 사라진다 — 훅이 휴리스틱을 이긴다.
    @Test func subagentStopSuppressesAFreshMtimeKitten() {
        let fs = makeFS()
        addScannedAgent(fs, id: "a1", ago: 1)
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        #expect(c.collect(now: now).sessions[0].subagents.map(\.id) == ["a1"])

        addEvent(fs, "2", Fixtures.subagentEvent("SubagentStop", agentId: "a1"))
        #expect(c.collect(now: now.addingTimeInterval(1)).sessions[0].subagents.isEmpty)
        #expect(c.hookAgents["sess"] == nil)
        #expect(c.stoppedAgents["sess"] == ["a1"])
    }

    @Test func startThenStopLeavesNoKitten() {
        let fs = makeFS()
        addEvent(fs, "1", Fixtures.subagentEvent("SubagentStart", agentId: "a1"))
        addEvent(fs, "2", Fixtures.subagentEvent("SubagentStop", agentId: "a1"))
        #expect(StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
            .collect(now: now).sessions[0].subagents.isEmpty)
    }

    /// 같은 초에 만들어진 파일은 이름 순이 시간 순이 아닐 수 있다. Stop 을 먼저 봐도
    /// 뒤늦은 Start 가 죽은 에이전트를 되살리면 안 된다.
    @Test func lateStartAfterStopDoesNotResurrect() {
        let fs = makeFS()
        addEvent(fs, "1", Fixtures.subagentEvent("SubagentStop", agentId: "a1"))
        addEvent(fs, "2", Fixtures.subagentEvent("SubagentStart", agentId: "a1"))
        #expect(StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
            .collect(now: now).sessions[0].subagents.isEmpty)
    }

    // MARK: - 합집합

    @Test func unionWithScannedKittensHasNoDuplicates() {
        let fs = makeFS()
        addScannedAgent(fs, id: "a1", ago: 1)     // 양쪽 다 아는 아이
        addScannedAgent(fs, id: "a2", ago: 1)     // 휴리스틱만 아는 아이
        addEvent(fs, "1", Fixtures.subagentEvent("SubagentStart", agentId: "a1", agentType: "hooked"))
        addEvent(fs, "2", Fixtures.subagentEvent("SubagentStart", agentId: "a3", agentType: "hooked"))
        let subs = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
            .collect(now: now).sessions[0].subagents
        #expect(subs.map(\.id) == ["a1", "a2", "a3"])
        #expect(subs[0].description == "hooked")   // 훅이 더 정확하다
        #expect(subs[1].description == "scanned")
    }

    /// idle 세션은 여전히 디스크를 훑지 않지만, 훅이 센 에이전트는 붙는다
    /// (프롬프트 앞에서 쉬는 동안 백그라운드 에이전트가 돌 수 있다).
    @Test func idleSessionShowsHookAgentsButStillDoesNotScan() {
        let fs = makeFS(status: "idle")
        addScannedAgent(fs, id: "scanned", ago: 1)
        addEvent(fs, "1", Fixtures.subagentEvent("SubagentStart", agentId: "hooked"))
        let subs = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
            .collect(now: now).sessions[0].subagents
        #expect(subs.map(\.id) == ["hooked"])
        let dir = Fixtures.subagentDir(encodedCwd: encoded, sessionId: "sess")
        #expect(fs.readCount["\(dir)/agent-scanned.meta.json"] == nil)
    }

    // MARK: - id 는 transcript 경로에서 뽑는다

    /// 훅의 `agent_id` 가 파일 이름의 `<id>` 와 다를 수 있다. 경로 쪽을 정본으로 쓰지 않으면
    /// 한 에이전트가 새끼 두 마리가 되고 Stop 억제도 빗나간다.
    @Test func kittenIdComesFromTheTranscriptPathNotAgentId() {
        let fs = makeFS()
        addScannedAgent(fs, id: "file-id", ago: 1)
        addEvent(fs, "1", Fixtures.subagentEvent("SubagentStart", agentId: "totally-different",
                                                 agentType: "hooked", transcriptId: "file-id"))
        let subs = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
            .collect(now: now).sessions[0].subagents
        #expect(subs.map(\.id) == ["file-id"])       // 두 마리가 아니라 한 마리
        #expect(subs[0].description == "hooked")
    }

    @Test func stopSuppressesUsingTheTranscriptId() {
        let fs = makeFS()
        addScannedAgent(fs, id: "file-id", ago: 1)
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        #expect(c.collect(now: now).sessions[0].subagents.map(\.id) == ["file-id"])

        addEvent(fs, "2", Fixtures.subagentEvent("SubagentStop", agentId: "totally-different",
                                                 transcriptId: "file-id"))
        #expect(c.collect(now: now.addingTimeInterval(1)).sessions[0].subagents.isEmpty)
        #expect(c.stoppedAgents["sess"] == ["file-id"])
    }

    /// transcript 경로가 없는 페이로드는 `agent_id` 로 떨어진다.
    @Test func agentIdIsTheFallbackWhenNoTranscriptPath() {
        let fs = makeFS()
        addEvent(fs, "1", Fixtures.subagentEvent("SubagentStart", agentId: "only-agent-id"))
        #expect(StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
            .collect(now: now).sessions[0].subagents.map(\.id) == ["only-agent-id"])
    }

    @Test func transcriptIdStripsTheAgentPrefixLikeTheScan() {
        #expect(StateCollector.subagentId(
            fromTranscript: URL(fileURLWithPath: "/p/subagents/agent-abc123.jsonl")) == "abc123")
        // 접두어가 없으면 파일 이름 그대로.
        #expect(StateCollector.subagentId(
            fromTranscript: URL(fileURLWithPath: "/p/subagents/plain.jsonl")) == "plain")
    }

    // MARK: - 안전망

    /// Stop 을 놓쳐도(Claude 가 죽거나 훅이 실패하거나) 새끼가 영영 남지는 않는다.
    @Test func hookAgentExpiresAfterItsTTL() {
        let fs = makeFS()
        addEvent(fs, "1", Fixtures.subagentEvent("SubagentStart", agentId: "a1"))
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        #expect(c.collect(now: now).sessions[0].subagents.map(\.id) == ["a1"])
        // 4시간 직전까지는 산다 — 서브에이전트는 오래 돌기도 한다.
        #expect(c.collect(now: now.addingTimeInterval(4 * 3600 - 1)).sessions[0].subagents.map(\.id) == ["a1"])
        #expect(c.collect(now: now.addingTimeInterval(4 * 3600)).sessions[0].subagents.isEmpty)
        #expect(c.hookAgents["sess"] == nil)
    }

    // MARK: - 청소

    @Test func hookAgentsArePrunedWhenTheSessionDisappears() {
        let fs = makeFS()
        addEvent(fs, "1", Fixtures.subagentEvent("SubagentStart", agentId: "a1"))
        addEvent(fs, "2", Fixtures.subagentEvent("SubagentStop", agentId: "a2"))
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        _ = c.collect(now: now)
        #expect(c.hookAgents["sess"]?.count == 1)

        fs.alivePids = []
        _ = c.collect(now: now.addingTimeInterval(3))
        #expect(c.hookAgents.isEmpty && c.stoppedAgents.isEmpty)
    }

    @Test func subagentEventForUnknownSessionIsDropped() {
        let fs = makeFS()
        addEvent(fs, "1", Fixtures.subagentEvent("SubagentStart", agentId: "a1", sessionId: "ghost"))
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        #expect(c.collect(now: now).sessions[0].subagents.isEmpty)
        #expect(c.hookAgents.isEmpty)
    }

    @Test func subagentEventWithoutAgentIdIsIgnored() {
        let fs = makeFS()
        addEvent(fs, "1", Fixtures.hookEvent("SubagentStart"))
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        #expect(c.collect(now: now).sessions[0].subagents.isEmpty)
        #expect(c.hookAgents.isEmpty)
    }

    /// 끝난 에이전트 목록은 세션당 상한이 있다 — 긴 세션에서 무한히 자라면 안 된다.
    @Test func stoppedAgentListIsCapped() {
        let fs = makeFS()
        for i in 0..<(StateCollector.stoppedAgentLimit + 10) {
            addEvent(fs, String(format: "%04d", i),
                     Fixtures.subagentEvent("SubagentStop", agentId: "a\(i)"))
        }
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        // 한 틱에 eventsPerTick 개만 삼키므로 두 틱 돌려야 다 들어간다.
        _ = c.collect(now: now)
        _ = c.collect(now: now.addingTimeInterval(3))
        let stopped = c.stoppedAgents["sess"] ?? []
        #expect(stopped.count == StateCollector.stoppedAgentLimit)
        #expect(stopped.last == "a\(StateCollector.stoppedAgentLimit + 9)")   // 최근 것이 남는다
    }
}
