import Testing
import Foundation
@testable import ClaudeCatsCore

@Suite struct StateCollectorAlertTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let cwd = "/Users/me/proj_x"

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

    /// 파일 이름 순서가 곧 처리 순서다. 10 < 9 이므로 "9-…" 가 나중이다.
    @Test func eventsAreProcessedInFilenameOrder() {
        let fs = makeFS()
        addEvent(fs, "10", Fixtures.notification(type: "permission_prompt", message: "first"))
        addEvent(fs, "9", Fixtures.notification(type: "idle_prompt", message: "second"))
        let alert = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
            .collect(now: now).sessions[0].alert
        #expect(alert?.kind == .idle && alert?.message == "second")
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

    @Test func statusChangeClearsTheAlert() {
        let fs = makeFS(status: "idle")
        addEvent(fs, "1", Fixtures.notification(type: "permission_prompt", message: "x"))
        let c = StateCollector(fileSystem: fs, claudeDir: Fixtures.claudeDir)
        #expect(c.collect(now: now).sessions[0].alert != nil)
        // 같은 상태로 한 틱 더 — 그대로 남는다.
        #expect(c.collect(now: now.addingTimeInterval(3)).sessions[0].alert != nil)

        let later = now.addingTimeInterval(6)
        fs.add(Fixtures.sessionPath(pid: 10),
               Fixtures.sessionJSON(pid: 10, id: "sess", name: "a", cwd: cwd, status: "busy"),
               modified: later)
        #expect(c.collect(now: later).sessions[0].alert == nil)
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
