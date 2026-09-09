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

/// Claude Code 가 사용자를 기다리는 상황. `Notification` 훅의 `notification_type` 에서 온다.
public enum AlertKind: Sendable, Equatable {
    /// `permission_prompt` — 도구 실행 권한을 묻는 중.
    case permission
    /// `idle_prompt` — 프롬프트에서 입력을 기다리는 중.
    case idle
    /// `agent_needs_input` — 서브에이전트가 입력을 기다리는 중.
    case agentNeedsInput

    /// 우리가 보는 세 종류만 받는다. 나머지(`auth_success` 등)는 nil.
    public init?(notificationType: String?) {
        switch notificationType {
        case "permission_prompt": self = .permission
        case "idle_prompt": self = .idle
        case "agent_needs_input": self = .agentNeedsInput
        default: return nil
        }
    }
}

public struct Alert: Sendable, Identifiable {
    public var kind: AlertKind
    public var message: String
    public var since: Date

    public var id: String { "\(kind)/\(message)" }

    public init(kind: AlertKind, message: String, since: Date) {
        self.kind = kind
        self.message = message
        self.since = since
    }
}

extension Alert: Equatable {
    /// `since` 는 스냅샷 변경 감지에서 뺀다 — 같은 알림이 계속 떠 있어도 다시 그리지 않게.
    public static func == (lhs: Alert, rhs: Alert) -> Bool {
        lhs.kind == rhs.kind && lhs.message == rhs.message
    }
}

public struct Session: Sendable, Equatable, Identifiable {
    public var id: String
    public var pid: Int32
    public var name: String
    public var cwd: String
    public var status: Status
    public var subagents: [Subagent]
    /// transcript 의 `ai-title` 줄. 제목이 한 번도 안 붙은 세션은 nil.
    public var title: String?
    /// 사용자 입력을 기다리는 중이면 그 알림. 훅이 설치돼 있을 때만 채워진다.
    public var alert: Alert?

    public init(id: String, pid: Int32, name: String, cwd: String, status: Status,
                subagents: [Subagent], title: String? = nil, alert: Alert? = nil) {
        self.id = id
        self.pid = pid
        self.name = name
        self.cwd = cwd
        self.status = status
        self.subagents = subagents
        self.title = title
        self.alert = alert
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
