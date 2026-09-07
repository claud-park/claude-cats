import Foundation

enum Fixtures {
    static let claudeDir = URL(fileURLWithPath: "/home/.claude")

    static func sessionJSON(
        pid: Int32, id: String, name: String, cwd: String,
        status: String = "idle", kind: String = "interactive"
    ) -> String {
        """
        {"pid":\(pid),"sessionId":"\(id)","cwd":"\(cwd)","startedAt":1788527779524,\
        "version":"2.1.260","kind":"\(kind)","entrypoint":"cli","name":"\(name)",\
        "status":"\(status)","updatedAt":1788756167866}
        """
    }

    static func sessionPath(pid: Int32) -> String {
        "/home/.claude/sessions/\(pid).json"
    }

    static func subagentDir(encodedCwd: String, sessionId: String) -> String {
        "/home/.claude/projects/\(encodedCwd)/\(sessionId)/subagents"
    }

    static func transcriptPath(encodedCwd: String, sessionId: String) -> String {
        "/home/.claude/projects/\(encodedCwd)/\(sessionId).jsonl"
    }

    /// Claude Code 가 transcript 끝에 주기적으로 append 하는 제목 줄.
    static func titleLine(_ title: String, sessionId: String = "sess") -> String {
        """
        {"type":"ai-title","aiTitle":"\(title)","sessionId":"\(sessionId)"}
        """
    }

    static func promptLine(_ prompt: String, sessionId: String = "sess") -> String {
        """
        {"type":"last-prompt","lastPrompt":"\(prompt)",\
        "leafUuid":"11111111-2222-3333-4444-555555555555","sessionId":"\(sessionId)"}
        """
    }

    /// 일반 대화 줄. 제목 파싱이 무시해야 하는 잡음.
    static func messageLine(_ text: String, sessionId: String = "sess") -> String {
        """
        {"parentUuid":null,"isSidechain":false,"type":"user",\
        "message":{"role":"user","content":"\(text)"},\
        "uuid":"66666666-7777-8888-9999-000000000000",\
        "timestamp":"2026-09-07T00:00:00.000Z","sessionId":"\(sessionId)"}
        """
    }

    /// 훅 스크립트가 떨구는 이벤트 파일 경로. 이름 순이 곧 처리 순서다.
    static func eventPath(_ name: String) -> String {
        "/home/.claude/claude-cats/events/\(name).json"
    }

    /// 공통 필드만 있는 훅 페이로드. `extra` 는 앞에 쉼표 없이 `"k":v` 형태로 넘긴다.
    static func hookEvent(_ event: String, sessionId: String = "sess", extra: String = "") -> String {
        """
        {"session_id":"\(sessionId)","transcript_path":"/home/.claude/projects/p/\(sessionId).jsonl",\
        "cwd":"/Users/me/proj_x","hook_event_name":"\(event)"\(extra.isEmpty ? "" : "," + extra)}
        """
    }

    static func notification(type: String, message: String, sessionId: String = "sess") -> String {
        hookEvent("Notification", sessionId: sessionId,
                  extra: #""notification_type":"\#(type)","message":"\#(message)""#)
    }

    /// 실제 훅 페이로드는 `agent_id` 와 transcript 경로를 **둘 다** 준다. 새끼 id 의 정본은
    /// 경로 쪽이므로(`agent-<id>.jsonl`) 테스트에서도 둘을 따로 줄 수 있게 한다.
    static func subagentEvent(_ event: String, agentId: String, agentType: String = "fork",
                              sessionId: String = "sess", transcriptId: String? = nil) -> String {
        var extra = #""agent_id":"\#(agentId)","agent_type":"\#(agentType)""#
        if let transcriptId {
            extra += #","agent_transcript_path":"/home/.claude/projects/p/\#(sessionId)/subagents/agent-\#(transcriptId).jsonl""#
        }
        return hookEvent(event, sessionId: sessionId, extra: extra)
    }

    static func metaJSON(description: String) -> String {
        """
        {"agentType":"fork","isFork":true,"description":"\(description)",\
        "toolUseId":"toolu_01","spawnDepth":1,"model":"inherit"}
        """
    }
}
