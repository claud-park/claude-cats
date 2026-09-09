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

/// 한 틱에 세션 파일을 몇 개 보고 몇 개를 받아들였는지, 못 받아들인 건 왜인지.
///
/// 이 앱은 `~/.claude` 의 문서화되지 않은 내부 구조에 기대고 있어서 Claude Code 업데이트로
/// 조용히 깨질 수 있다. 그때 "고양이 0마리"와 "파일은 있는데 하나도 못 읽었다"를 구분하지
/// 못하면 사용자가 알아차릴 방법이 없다. 그 구분을 메뉴바에 한 줄로 드러내려고 센다.
public struct CollectorHealth: Equatable, Sendable {
    /// `sessions/` 에서 본 `.json` 파일 수.
    public var sessionFiles: Int
    /// 그중 살아 있는 대화형 세션으로 받아들인 수(= 고양이 수).
    public var accepted: Int
    /// stat 이나 read 가 실패한 파일 수(권한·경합·깨진 심볼릭 링크 등).
    public var unreadable: Int
    /// JSON 은 읽었는데 우리가 아는 스키마로 디코딩되지 않은 파일 수. **구조 변경의 신호**다.
    public var malformed: Int
    /// `kind` 가 `interactive` 가 아니라 건너뛴 파일 수(정상이다).
    public var nonInteractive: Int
    /// 프로세스가 이미 죽은 세션 파일 수(정상이다 — 치워지지 않은 찌꺼기).
    public var deadPid: Int

    public init(sessionFiles: Int = 0, accepted: Int = 0, unreadable: Int = 0,
                malformed: Int = 0, nonInteractive: Int = 0, deadPid: Int = 0) {
        self.sessionFiles = sessionFiles
        self.accepted = accepted
        self.unreadable = unreadable
        self.malformed = malformed
        self.nonInteractive = nonInteractive
        self.deadPid = deadPid
    }

    /// 파일은 있는데 하나도 못 받아들였고, **그 이유가 읽기·파싱 실패**인 상태.
    /// 구조가 바뀌었을 가능성이 가장 큰 자리다.
    ///
    /// 실패가 하나도 없는데 accepted 가 0 이면(전부 죽은 pid 이거나 전부 비대화형) 여기
    /// 안 들어온다 — 그건 정상이고 "고양이 0마리"가 맞는 답이다. 그때까지 구조 변경을
    /// 의심하게 만들면 경고가 늑대소년이 된다.
    public var readNothing: Bool { sessionFiles > 0 && accepted == 0 && failures > 0 }
    /// 일부만 실패했다. 못 읽은 파일 수(비대화형·죽은 pid 는 정상이라 세지 않는다).
    public var failures: Int { unreadable + malformed }
}

public struct Snapshot: Sendable {
    public var sessions: [Session]
    public var takenAt: Date
    /// 이 스냅샷을 만든 틱의 수집 상태. 메뉴바 경고 줄에만 쓴다.
    public var health: CollectorHealth

    public init(sessions: [Session], takenAt: Date, health: CollectorHealth = CollectorHealth()) {
        self.sessions = sessions
        self.takenAt = takenAt
        self.health = health
    }
}

extension Snapshot: Equatable {
    /// takenAt 은 매 틱 바뀌므로 제외. 같으면 다시 그리지 않는다.
    /// health 도 제외한다 — 고양이 배치는 health 로 달라지지 않으므로 이걸로 다시 그릴 이유가
    /// 없다. 메뉴 줄만 바뀌면 되고, 그건 AppController 가 별도 게이트로 챙긴다.
    public static func == (lhs: Snapshot, rhs: Snapshot) -> Bool {
        lhs.sessions == rhs.sessions
    }
}
