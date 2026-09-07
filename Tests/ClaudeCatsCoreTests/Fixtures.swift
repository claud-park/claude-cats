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

    static func metaJSON(description: String) -> String {
        """
        {"agentType":"fork","isFork":true,"description":"\(description)",\
        "toolUseId":"toolu_01","spawnDepth":1,"model":"inherit"}
        """
    }
}
