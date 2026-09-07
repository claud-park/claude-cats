import Foundation

public enum Status: Sendable, Equatable {
    case busy
    case idle
}

public struct Subagent: Sendable, Identifiable {
    public var id: String
    public var description: String
    public var lastActivity: Date

    public init(id: String, description: String, lastActivity: Date) {
        self.id = id
        self.description = description
        self.lastActivity = lastActivity
    }
}

extension Subagent: Equatable {
    /// lastActivity 는 매 틱 바뀌므로 동등성에서 제외한다. 스냅샷 변경 감지용.
    public static func == (lhs: Subagent, rhs: Subagent) -> Bool {
        lhs.id == rhs.id && lhs.description == rhs.description
    }
}

public struct Session: Sendable, Equatable, Identifiable {
    public var id: String
    public var pid: Int32
    public var name: String
    public var cwd: String
    public var status: Status
    public var subagents: [Subagent]

    public init(id: String, pid: Int32, name: String, cwd: String, status: Status, subagents: [Subagent]) {
        self.id = id
        self.pid = pid
        self.name = name
        self.cwd = cwd
        self.status = status
        self.subagents = subagents
    }
}

public struct Snapshot: Sendable {
    public var sessions: [Session]
    public var takenAt: Date

    public init(sessions: [Session], takenAt: Date) {
        self.sessions = sessions
        self.takenAt = takenAt
    }
}

extension Snapshot: Equatable {
    /// takenAt 은 매 틱 바뀌므로 제외. 같으면 다시 그리지 않는다.
    public static func == (lhs: Snapshot, rhs: Snapshot) -> Bool {
        lhs.sessions == rhs.sessions
    }
}
