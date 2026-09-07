import Testing
import Foundation
@testable import ClaudeCatsCore

@Suite struct StateCollectorAlertTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let cwd = "/Users/me/proj_x"
    let encoded = "-Users-me-proj-x"

    func makeFS(status: String = "idle") -> FakeFileSystem {
        let fs = FakeFileSystem()
        fs.add(Fixtures.sessionPath(pid: 10),
               Fixtures.sessionJSON(pid: 10, id: "sess", name: "a", cwd: cwd, status: status),
               modified: now)
        fs.alivePids = [10]
        return fs
    }

    @discardableResult
    func addEvent(_ fs: FakeFileSystem, _ name: String, _ json: String) -> String {
        let path = Fixtures.eventPath(name)
        fs.add(path, json, modified: now)
        return path
    }

    // MARK: - 알림 켜기

    @Test func permissionNotificationBecomesAlert() {
        let fs = makeFS()
        addEvent(fs, "1", Fixtures.notification(type: "permission_prompt",
                                                message: "Claude needs your permission to run Bash"))
        let alert = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
            .collect(now: now).sessions[0].alert
        #expect(alert?.kind == .permission)
        #expect(alert?.message == "Claude needs your permission to run Bash")
        #expect(alert?.since == now)
    }

    @Test func idleAndAgentNeedsInputMapToTheirKinds() {
        for (type, kind) in [("idle_prompt", AlertKind.idle), ("agent_needs_input", .agentNeedsInput)] {
            let fs = makeFS()
            addEvent(fs, "1", Fixtures.notification(type: type, message: "x"))
            let alert = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
                .collect(now: now).sessions[0].alert
            #expect(alert?.kind == kind)
        }
    }

    @Test func unknownNotificationTypeIsIgnored() {
        let fs = makeFS()
        addEvent(fs, "1", Fixtures.notification(type: "auth_success", message: "hi"))
        #expect(StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
            .collect(now: now).sessions[0].alert == nil)
    }

    @Test func newerNotificationReplacesTheOlderOne() {
        let fs = makeFS()
        addEvent(fs, "1", Fixtures.notification(type: "idle_prompt", message: "first"))
        addEvent(fs, "2", Fixtures.notification(type: "permission_prompt", message: "second"))
        let alert = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
            .collect(now: now).sessions[0].alert
        #expect(alert?.kind == .permission && alert?.message == "second")
    }

    /// mtime 이 같으면 파일 이름이 동점 처리다. 10 < 9 이므로 "9-…" 가 나중이다.
    @Test func eventsWithTheSameMtimeFallBackToFilenameOrder() {
        let fs = makeFS()
        addEvent(fs, "10", Fixtures.notification(type: "permission_prompt", message: "first"))
        addEvent(fs, "9", Fixtures.notification(type: "idle_prompt", message: "second"))
        let alert = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
            .collect(now: now).sessions[0].alert
        #expect(alert?.kind == .idle && alert?.message == "second")
    }

    /// 파일 이름의 타임스탬프는 초 단위라 같은 초 안에서는 순서를 못 정한다.
    /// mtime(APFS 는 나노초)이 1순위여야 한다 — 이름 순으로는 "second" 가 먼저다.
    @Test func mtimeBeatsFilenameOrder() {
        let system = makeFS()      // 이름 순으로는 "1-a" < "2-b" 라 반대 결과가 나온다
        system.add(Fixtures.eventPath("2-b"),
                   Fixtures.notification(type: "permission_prompt", message: "older"),
                   modified: now.addingTimeInterval(-2))
        system.add(Fixtures.eventPath("1-a"),
                   Fixtures.notification(type: "idle_prompt", message: "newer"),
                   modified: now.addingTimeInterval(-1))
        let alert = StateCollector(fileSystem: system, claudeDir: Fixtures.claudeDir)
            .collect(now: now).sessions[0].alert
        #expect(alert?.kind == .idle && alert?.message == "newer")
    }

    /// 앱이 꺼져 있는 동안 훅은 계속 쌓는다. 한 틱에 다 삼키면 폴링이 길어진다.
    @Test func atMostOneCapWorthOfEventsPerTick() {
        let fs = makeFS()
        let total = StateCollector.eventsPerTick + 30
        for i in 0..<total {
            fs.add(Fixtures.eventPath(String(format: "%05d", i)),
                   Fixtures.hookEvent("UserPromptSubmit"),
                   modified: now.addingTimeInterval(Double(i)))
        }
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        _ = c.collect(now: now)
        #expect(fs.removed.count == StateCollector.eventsPerTick)
        // 오래된 것부터 먹는다.
        #expect(fs.removed.first == Fixtures.eventPath("00000"))
        _ = c.collect(now: now.addingTimeInterval(3))
        #expect(fs.removed.count == total)          // 나머지는 다음 틱에
    }

    /// 지우기에 실패한 파일은 매 틱 다시 만난다. 내용을 두 번 적용하면 안 된다.
    @Test func undeletableEventIsNotAppliedTwice() {
        let fs = makeFS()
        let path = addEvent(fs, "1", Fixtures.notification(type: "idle_prompt", message: "x"))
        fs.failRemoves = [path]
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        #expect(c.collect(now: now).sessions[0].alert != nil)
        #expect(c.processedEvents == [path])

        // 두 번째 틱: 파일은 아직 있지만 다시 읽지도, 다시 적용하지도 않는다.
        addEvent(fs, "2", Fixtures.hookEvent("UserPromptSubmit"))
        #expect(c.collect(now: now.addingTimeInterval(3)).sessions[0].alert == nil)
        #expect(fs.readCount[path] == 1)
        // 세 번째 틱에서도 알림이 되살아나지 않는다.
        #expect(c.collect(now: now.addingTimeInterval(6)).sessions[0].alert == nil)

        // 지워지면 기억에서도 빠진다.
        fs.failRemoves = []
        _ = c.collect(now: now.addingTimeInterval(9))
        #expect(c.processedEvents.isEmpty)
    }

    // MARK: - 파일 청소

    @Test func eventFileIsRemovedAfterReading() {
        let fs = makeFS()
        let path = addEvent(fs, "1", Fixtures.notification(type: "idle_prompt", message: "x"))
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        _ = c.collect(now: now)
        #expect(fs.removed == [path])
        // 다시 읽히지 않는다 — 알림은 남아 있지만 파일은 없다.
        _ = c.collect(now: now.addingTimeInterval(3))
        #expect(fs.readCount[path] == 1)
    }

    @Test func undecodableFileIsRemovedAndIgnored() {
        let fs = makeFS()
        let bad = addEvent(fs, "1", "not json at all")
        let good = addEvent(fs, "2", Fixtures.notification(type: "idle_prompt", message: "x"))
        let snap = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir).collect(now: now)
        #expect(snap.sessions[0].alert?.kind == .idle)
        #expect(Set(fs.removed) == [bad, good])
    }

    /// hook_event_name 이 없으면 우리가 해석할 수 없는 파일이다. 지우고 넘어간다.
    @Test func eventMissingRequiredFieldsIsDropped() {
        let fs = makeFS()
        addEvent(fs, "1", #"{"session_id":"sess","notification_type":"idle_prompt"}"#)
        #expect(StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
            .collect(now: now).sessions[0].alert == nil)
        #expect(fs.removed.count == 1)
    }

    /// 모르는 필드가 붙어 있어도 무시하고 읽는다(훅 페이로드는 계속 늘어난다).
    @Test func unknownFieldsAreIgnored() {
        let fs = makeFS()
        addEvent(fs, "1", """
        {"hook_event_name":"Notification","session_id":"sess","notification_type":"idle_prompt",\
        "message":"x","cwd":"/tmp","transcript_path":"/t.jsonl","brand_new_field":{"a":[1,2]}}
        """)
        #expect(StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
            .collect(now: now).sessions[0].alert?.kind == .idle)
    }

    @Test func missingEventsDirIsFineAndNothingIsCreated() {
        let fs = makeFS()
        let snap = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir).collect(now: now)
        #expect(snap.sessions[0].alert == nil)
        #expect(fs.removed.isEmpty)
    }

    // MARK: - 알림 끄기

    @Test func userPromptSubmitClearsTheAlert() {
        let fs = makeFS()
        addEvent(fs, "1", Fixtures.notification(type: "permission_prompt", message: "x"))
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        #expect(c.collect(now: now).sessions[0].alert != nil)

        addEvent(fs, "2", Fixtures.hookEvent("UserPromptSubmit"))
        #expect(c.collect(now: now.addingTimeInterval(3)).sessions[0].alert == nil)
    }

    /// 세션 상태를 바꾼다(파일을 다시 써서 mtime 도 같이 올린다).
    func setStatus(_ fs: FakeFileSystem, _ status: String, at: Date) {
        fs.add(Fixtures.sessionPath(pid: 10),
               Fixtures.sessionJSON(pid: 10, id: "sess", name: "a", cwd: cwd, status: status),
               modified: at)
    }

    /// 권한을 승인하면 Claude 가 도구를 돌리고 transcript 에 append 한다 — 제일 정확한 신호다.
    /// 다만 알림 **직후**에 붙는 줄은 알림을 띄운 그 턴이 자기 기록을 마저 쓰는 것이라
    /// `alertClearGrace` 만큼 봐준다.
    @Test func transcriptWriteAfterTheGraceWindowClearsTheAlert() {
        let fs = makeFS(status: "busy")
        let transcript = Fixtures.transcriptPath(encodedCwd: encoded, sessionId: "sess")
        fs.add(transcript, Fixtures.titleLine("t") + "\n", modified: now.addingTimeInterval(-5))
        addEvent(fs, "1", Fixtures.notification(type: "permission_prompt", message: "x"))
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        #expect(c.collect(now: now).sessions[0].alert?.since == now)
        // transcript 가 그대로면 계속 기다리는 중이다.
        #expect(c.collect(now: now.addingTimeInterval(3)).sessions[0].alert != nil)

        // 유예 안(+3초)에 붙은 줄은 무시한다.
        fs.touch(transcript, modified: now.addingTimeInterval(3))
        #expect(c.collect(now: now.addingTimeInterval(4)).sessions[0].alert != nil)
        // 경계(정확히 +5초)도 아직 유예 안이다.
        fs.touch(transcript, modified: now.addingTimeInterval(5))
        #expect(c.collect(now: now.addingTimeInterval(5)).sessions[0].alert != nil)
        // 유예를 넘긴 줄은 "답했다"로 읽는다.
        fs.touch(transcript, modified: now.addingTimeInterval(7))
        #expect(c.collect(now: now.addingTimeInterval(8)).sessions[0].alert == nil)
    }

    /// 유예 창은 조절할 수 있어야 한다(테스트·튜닝용).
    @Test func graceWindowIsConfigurable() {
        let fs = makeFS(status: "busy")
        let transcript = Fixtures.transcriptPath(encodedCwd: encoded, sessionId: "sess")
        fs.add(transcript, Fixtures.titleLine("t") + "\n", modified: now.addingTimeInterval(-5))
        addEvent(fs, "1", Fixtures.notification(type: "permission_prompt", message: "x"))
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        c.alertClearGrace = 0
        #expect(c.collect(now: now).sessions[0].alert != nil)
        fs.touch(transcript, modified: now.addingTimeInterval(1))
        #expect(c.collect(now: now.addingTimeInterval(2)).sessions[0].alert == nil)
    }

    /// 알림 시각은 틱 시각이 아니라 **이벤트 파일 mtime** 이다. 폴링 간격(최대 3초)만큼,
    /// 앱이 꺼져 있었다면 그보다 훨씬 벌어진다 — 유예도 TTL 도 훅이 터진 때부터 재야 한다.
    @Test func alertSinceComesFromTheEventFileMtime() {
        let fs = makeFS()
        let fired = now.addingTimeInterval(-120)
        fs.add(Fixtures.eventPath("1"), Fixtures.notification(type: "idle_prompt", message: "x"),
               modified: fired)
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        #expect(c.collect(now: now).sessions[0].alert?.since == fired)
        // TTL 도 그 시각부터 잰다 — 이미 28분 전에 터졌으면 2분 뒤에 만료된다.
        #expect(c.collect(now: fired.addingTimeInterval(30 * 60)).sessions[0].alert == nil)
    }

    /// idle → busy 는 새 작업이 시작됐다는 뜻이라 알림을 지운다.
    @Test func idleToBusyTransitionClearsTheAlert() {
        let fs = makeFS(status: "idle")
        addEvent(fs, "1", Fixtures.notification(type: "idle_prompt", message: "x"))
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        #expect(c.collect(now: now).sessions[0].alert != nil)
        // 같은 상태로 한 틱 더 — 그대로 남는다.
        #expect(c.collect(now: now.addingTimeInterval(3)).sessions[0].alert != nil)

        let later = now.addingTimeInterval(6)
        setStatus(fs, "busy", at: later)
        #expect(c.collect(now: later).sessions[0].alert == nil)
    }

    /// busy → idle 은 지우지 않는다. 권한 프롬프트가 떠 있는 동안 세션이 idle 로 넘어가는 건
    /// 정상이고, 그걸로 지우면 알림이 뜨자마자 사라진다.
    @Test func busyToIdleBlipDoesNotClearTheAlert() {
        let fs = makeFS(status: "busy")
        addEvent(fs, "1", Fixtures.notification(type: "idle_prompt", message: "x"))
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        #expect(c.collect(now: now).sessions[0].alert != nil)

        setStatus(fs, "idle", at: now.addingTimeInterval(3))
        #expect(c.collect(now: now.addingTimeInterval(3)).sessions[0].alert != nil)
        #expect(c.collect(now: now.addingTimeInterval(6)).sessions[0].alert != nil)

        addEvent(fs, "2", Fixtures.hookEvent("UserPromptSubmit"))
        #expect(c.collect(now: now.addingTimeInterval(9)).sessions[0].alert == nil)
    }

    /// 서브에이전트가 입력을 기다리는 동안 본 대화(main turn)가 끝나 busy → idle 이 되어도
    /// 알림은 남아야 한다 — 기다리는 건 에이전트지 본 대화가 아니다.
    @Test func agentNeedsInputSurvivesTheMainTurnEnding() {
        let fs = makeFS(status: "busy")
        addEvent(fs, "1", Fixtures.notification(type: "agent_needs_input", message: "x"))
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        #expect(c.collect(now: now).sessions[0].alert?.kind == .agentNeedsInput)

        setStatus(fs, "idle", at: now.addingTimeInterval(3))
        #expect(c.collect(now: now.addingTimeInterval(3)).sessions[0].alert?.kind == .agentNeedsInput)
        #expect(c.collect(now: now.addingTimeInterval(60)).sessions[0].alert?.kind == .agentNeedsInput)
    }

    @Test func alertExpiresAfterTTL() {
        let fs = makeFS()
        addEvent(fs, "1", Fixtures.notification(type: "idle_prompt", message: "x"))
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        #expect(c.collect(now: now).sessions[0].alert != nil)
        #expect(c.collect(now: now.addingTimeInterval(29 * 60)).sessions[0].alert != nil)
        #expect(c.collect(now: now.addingTimeInterval(30 * 60)).sessions[0].alert == nil)
    }

    @Test func alertIsPrunedWhenTheSessionDisappears() {
        let fs = makeFS()
        addEvent(fs, "1", Fixtures.notification(type: "idle_prompt", message: "x"))
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        #expect(c.collect(now: now).sessions[0].alert != nil)

        fs.alivePids = []
        #expect(c.collect(now: now.addingTimeInterval(3)).sessions.isEmpty)
        #expect(c.alerts.isEmpty)
    }

    @Test func eventForUnknownSessionIsDropped() {
        let fs = makeFS()
        addEvent(fs, "1", Fixtures.notification(type: "idle_prompt", message: "x", sessionId: "ghost"))
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        #expect(c.collect(now: now).sessions[0].alert == nil)
        #expect(c.alerts.isEmpty)
    }
}
