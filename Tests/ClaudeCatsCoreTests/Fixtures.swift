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
}
