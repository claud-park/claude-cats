import Foundation
import os

/// ~/.claude 를 읽어 Snapshot 을 만든다.
/// 스레드 안전하지 않다. 항상 같은 직렬 큐에서 collect 를 호출할 것.
public final class StateCollector: @unchecked Sendable {
    public var subagentActiveWindow: TimeInterval = 15
    public var projectLookupRetry: TimeInterval = 60
    /// transcript 를 다시 읽기까지의 최소 간격. mtime 이 바뀌어도 이 시간 전엔 안 읽는다.
    public var titleRefreshInterval: TimeInterval = 10
    /// 알림을 지우는 안전망. 훅이 죽거나 이벤트를 놓쳐도 말풍선이 영원히 남지는 않게.
    public var alertTTL: TimeInterval = 30 * 60
    /// `SubagentStop` 을 놓쳤을 때 새끼를 거두는 안전망. 서브에이전트는 몇 시간씩 돌기도 한다.
    public var hookAgentTTL: TimeInterval = 4 * 60 * 60

    /// transcript 는 수 MB 까지 자란다. 꼬리 256KB 만 본다.
    static let titleTailBytes = 262_144
    /// 세션 하나가 기억하는 "이미 끝난 서브에이전트" 개수 상한.
    static let stoppedAgentLimit = 200
    /// 한 틱에 삼킬 이벤트 파일 수 상한. 앱이 꺼져 있는 동안 쌓인 더미로 틱이 길어지지 않게.
    static let eventsPerTick = 200
    /// 지우기에 실패해 다시 만날 이벤트 파일을 기억하는 개수 상한.
    static let processedEventLimit = 1000

    private let fs: any FileSystem
    private let claudeDir: URL
    private let log = Logger(subsystem: "claude-cats", category: "collector")

    /// key: sessions/<pid>.json 경로. session 이 nil 이면 파싱 실패(비대화형/깨진 JSON)의 부정 캐시.
    private var sessionCache: [String: (modified: Date, session: Session?)] = [:]
    /// key: sessionId. url 이 nil 이면 실패 캐시(checkedAt + projectLookupRetry 후 재시도).
    private var projectRootCache: [String: (url: URL?, checkedAt: Date)] = [:]
    /// key: meta.json 경로 → description. 이번 틱에 실행 중으로 판정된 서브에이전트의
    /// meta 경로만 남긴다(`@testable` 로 테스트에서 직접 들여다본다).
    private(set) var metaCache: [String: String] = [:]
    /// key: sessionId. title 이 nil 이면 "아직 제목이 안 붙은 세션".
    private var titleCache: [String: (modified: Date, readAt: Date, title: String?)] = [:]

    /// key: sessionId. 훅이 알려준 "사용자를 기다리는 중".
    private(set) var alerts: [String: Alert] = [:]
    /// 알림이 **처음 보인 틱**의 세션 상태. 이 상태가 바뀌면 알림을 지운다
    /// (사용자가 답했거나 작업이 넘어갔다는 뜻).
    private var alertStatus: [String: Status] = [:]
    /// key: sessionId → agentId → 실행 중인 서브에이전트. SubagentStart 로 들어오고 Stop 으로 빠진다.
    private(set) var hookAgents: [String: [String: HookAgent]] = [:]
    /// key: sessionId. 이미 Stop 을 받은 agentId 들(오래된 순). mtime 휴리스틱이 다시
    /// 살려내지 못하게 억제하고, 순서가 뒤집힌 Start 도 막는다.
    private(set) var stoppedAgents: [String: [String]] = [:]
    /// 이미 적용했지만 지우지 못한 이벤트 파일 경로. 같은 내용을 두 번 적용하지 않게 막는다.
    /// `processedEventOrder` 는 상한을 넘겼을 때 버릴 순서를 기억한다.
    private(set) var processedEvents: Set<String> = []
    private var processedEventOrder: [String] = []

    struct HookAgent: Equatable {
        var type: String
        var startedAt: Date
    }

    public init(fileSystem: any FileSystem, claudeDir: URL) {
        self.fs = fileSystem
        self.claudeDir = claudeDir
    }

    public func collect(now: Date) -> Snapshot {
        // 세션을 읽기 **전에** 훅 이벤트를 소화해야 같은 틱에 알림이 보인다.
        ingestHookEvents(now: now)
        let sessionsDir = claudeDir.appendingPathComponent("sessions")
        guard let files = try? fs.list(sessionsDir) else {
            // 목록 조회 실패(일시적 오류 포함)는 캐시를 건드리지 않고 빈 스냅샷만 반환한다.
            return Snapshot(sessions: [], takenAt: now)
        }
        var sessions: [Session] = []
        var seenPaths = Set<String>()
        var seenIds = Set<String>()
        var seenMetaPaths = Set<String>()

        for file in files where file.pathExtension == "json" {
            guard let st = try? fs.stat(file) else { continue }
            seenPaths.insert(file.path)

            var session: Session
            if let cached = sessionCache[file.path], cached.modified == st.modified {
                guard let cachedSession = cached.session else { continue }
                session = cachedSession
            } else {
                guard let data = try? fs.read(file) else {
                    log.warning("read failed: \(file.path, privacy: .public)")
                    continue
                }
                guard let parsed = Self.parseSession(data) else {
                    log.info("skipped session file: \(file.path, privacy: .public)")
                    sessionCache[file.path] = (st.modified, nil)
                    continue
                }
                session = parsed
                sessionCache[file.path] = (st.modified, parsed)
            }

            guard fs.processAlive(session.pid) else { continue }
            guard !seenIds.contains(session.id) else { continue }
            seenIds.insert(session.id)

            // transcript stat 은 틱당 세션마다 **한 번**만 한다. 제목과 알림 해제가 같이 쓴다.
            let transcript = transcriptStat(for: session, now: now)
            session.alert = resolveAlert(for: session, now: now, transcript: transcript?.stat)
            // mtime 휴리스틱은 busy 세션만 훑는다. 훅이 세어 준 서브에이전트는 idle 세션에도
            // 붙인다 — 프롬프트 앞에서 쉬는 동안 백그라운드 에이전트가 돌 수 있다.
            let scanned = session.status == .busy
                ? activeSubagents(for: session, now: now, seenMetaPaths: &seenMetaPaths)
                : []
            session.subagents = mergedSubagents(for: session.id, now: now, scanned: scanned)
            session.title = title(for: session, now: now, transcript: transcript)
            sessions.append(session)
        }

        sessionCache = sessionCache.filter { seenPaths.contains($0.key) }
        titleCache = titleCache.filter { seenIds.contains($0.key) }
        projectRootCache = projectRootCache.filter { seenIds.contains($0.key) }
        // 세션이 사라지면 그 세션의 훅 상태도 같이 버린다(모르는 세션에 온 이벤트도 여기서 걸러진다).
        alerts = alerts.filter { seenIds.contains($0.key) }
        alertStatus = alertStatus.filter { alerts[$0.key] != nil }
        hookAgents = hookAgents.filter { seenIds.contains($0.key) }
        stoppedAgents = stoppedAgents.filter { seenIds.contains($0.key) }
        // 서브에이전트는 세션보다 훨씬 자주 생겼다 사라진다. 다른 캐시와 같은 규칙으로
        // 이번 틱에 실행 중이던 것만 남기지 않으면 프로세스 수명 내내 단조 증가한다.
        metaCache = metaCache.filter { seenMetaPaths.contains($0.key) }
        sessions.sort { ($0.name, $0.id) < ($1.name, $1.id) }
        return Snapshot(sessions: sessions, takenAt: now)
    }

    // MARK: - Sessions

    private struct SessionFile: Decodable {
        let pid: Int32
        let sessionId: String
        let name: String
        let cwd: String
        let status: String?
        let kind: String?
    }

    static func parseSession(_ data: Data) -> Session? {
        guard let f = try? JSONDecoder().decode(SessionFile.self, from: data) else { return nil }
        guard f.kind == "interactive" else { return nil }
        return Session(
            id: f.sessionId, pid: f.pid, name: f.name, cwd: f.cwd,
            status: f.status == "busy" ? .busy : .idle,
            subagents: []
        )
    }

    /// 관찰된 규칙: `/` 와 `_` 를 `-` 로. 맞지 않으면 projectDir 가 glob 으로 폴백한다.
    static func encodeCwd(_ cwd: String) -> String {
        String(cwd.map { $0 == "/" || $0 == "_" ? "-" : $0 })
    }

    // MARK: - Subagents

    private struct MetaFile: Decodable {
        let description: String?
    }

    /// 세션이 사는 `projects/<encoded>` 디렉터리. transcript(`<id>.jsonl`) 나
    /// 서브에이전트 디렉터리(`<id>/`) 중 하나만 있어도 그 디렉터리로 인정한다.
    /// (서브에이전트를 한 번도 안 띄운 세션은 `<id>/` 가 없다.)
    private func projectRoot(for session: Session, now: Date) -> URL? {
        if let cached = projectRootCache[session.id] {
            if cached.url != nil { return cached.url }
            if now.timeIntervalSince(cached.checkedAt) < projectLookupRetry { return nil }
        }
        let projects = claudeDir.appendingPathComponent("projects")
        let guess = projects.appendingPathComponent(Self.encodeCwd(session.cwd))
        var found: URL? = holdsSession(guess, session.id) ? guess : nil
        if found == nil, let dirs = try? fs.list(projects) {
            for dir in dirs where holdsSession(dir, session.id) {
                found = dir
                break
            }
        }
        projectRootCache[session.id] = (found, now)
        return found
    }

    /// 서브에이전트 transcript 경로 → 새끼 고양이 id. 파일 이름은 `agent-<id>.jsonl` 이다.
    ///
    /// mtime 휴리스틱과 훅이 **같은 id 를 써야** 한 에이전트가 새끼 두 마리로 보이지 않고,
    /// `SubagentStop` 억제도 먹는다. 훅 페이로드의 `agent_id` 가 이 `<id>` 와 같다는 보장이
    /// 없으므로, 훅 쪽도 `agent_transcript_path` 를 이 함수에 통과시켜 id 를 만든다.
    static func subagentId(fromTranscript url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        return base.hasPrefix("agent-") ? String(base.dropFirst("agent-".count)) : base
    }

    private func holdsSession(_ root: URL, _ id: String) -> Bool {
        if (try? fs.stat(root.appendingPathComponent(id + ".jsonl"))) != nil { return true }
        return (try? fs.stat(root.appendingPathComponent(id))) != nil
    }

    private func activeSubagents(
        for session: Session, now: Date, seenMetaPaths: inout Set<String>
    ) -> [Subagent] {
        guard let root = projectRoot(for: session, now: now) else { return [] }
        let subDir = root.appendingPathComponent(session.id).appendingPathComponent("subagents")
        guard let files = try? fs.list(subDir) else { return [] }

        var result: [Subagent] = []
        for file in files where file.pathExtension == "jsonl" {
            guard let st = try? fs.stat(file),
                  now.timeIntervalSince(st.modified) <= subagentActiveWindow else { continue }
            let id = Self.subagentId(fromTranscript: file)
            let metaURL = file.deletingPathExtension().appendingPathExtension("meta.json")
            seenMetaPaths.insert(metaURL.path)
            let description: String
            if let cached = metaCache[metaURL.path] {
                description = cached
            } else {
                description = (try? fs.read(metaURL))
                    .flatMap { try? JSONDecoder().decode(MetaFile.self, from: $0) }?
                    .description ?? ""
                metaCache[metaURL.path] = description
            }
            result.append(Subagent(id: id, description: description, lastActivity: st.modified))
        }
        return result.sorted { $0.id < $1.id }
    }

    // MARK: - 훅 이벤트

    /// 훅 스크립트가 떨궈 놓은 파일 하나. 문서에 없는 필드는 무시하고, 없는 필드는 nil 이다.
    struct HookEvent: Decodable {
        let hookEventName: String
        let sessionId: String
        let notificationType: String?
        let message: String?
        let agentId: String?
        let agentType: String?
        let agentTranscriptPath: String?

        enum CodingKeys: String, CodingKey {
            case hookEventName = "hook_event_name"
            case sessionId = "session_id"
            case notificationType = "notification_type"
            case message
            case agentId = "agent_id"
            case agentType = "agent_type"
            case agentTranscriptPath = "agent_transcript_path"
        }

        /// 새끼 고양이 id. transcript 경로에서 뽑는 게 정본이다 — mtime 휴리스틱이 쓰는 id 와
        /// 같아야 한 에이전트가 두 마리로 보이지 않는다. 경로가 없을 때만 `agent_id` 로 떨어진다.
        var kittenId: String? {
            if let path = agentTranscriptPath, !path.isEmpty {
                let id = StateCollector.subagentId(fromTranscript: URL(fileURLWithPath: path))
                if !id.isEmpty { return id }
            }
            guard let agentId, !agentId.isEmpty else { return nil }
            return agentId
        }
    }

    /// `~/.claude/claude-cats/events/*.json` 을 오래된 것부터 읽고 지운다.
    /// 디렉터리가 없으면 훅이 안 깔린 것이다 — 만들지 않고 그냥 돌아간다.
    /// 보통은 파일이 없거나 몇 개뿐이라 유휴 틱 비용은 `list` 한 번이다.
    ///
    /// 앱이 꺼져 있는 동안 훅은 계속 파일을 쌓는다. 한 틱에 다 삼키면 폴링 틱이 길어지므로
    /// `eventsPerTick` 만 처리하고 나머지는 다음 틱으로 넘긴다.
    private func ingestHookEvents(now: Date) {
        let dir = claudeDir.appendingPathComponent("claude-cats").appendingPathComponent("events")
        guard let files = try? fs.list(dir) else { return }
        // 파일 이름의 초 단위 타임스탬프는 같은 초 안에서 순서를 못 정한다. mtime(APFS 는
        // 나노초)을 1순위로, 이름을 동점 처리로 쓴다.
        var dated: [(url: URL, modified: Date)] = []
        for url in files where url.pathExtension == "json" {
            guard let stat = try? fs.stat(url) else { continue }
            dated.append((url, stat.modified))
        }
        let ordered = dated.sorted { lhs, rhs in
            if lhs.modified != rhs.modified { return lhs.modified < rhs.modified }
            return lhs.url.lastPathComponent < rhs.url.lastPathComponent
        }

        for entry in ordered.prefix(Self.eventsPerTick) {
            let path = entry.url.path
            // 지우기에 실패한 파일은 다시 만난다. 내용을 두 번 적용하지 않으려면 기억해야 한다.
            let alreadyApplied = processedEvents.contains(path)
            defer {
                do {
                    try fs.remove(entry.url)
                    forgetProcessedEvent(path)
                } catch {
                    rememberProcessedEvent(path)
                }
            }
            guard !alreadyApplied else { continue }
            guard let data = try? fs.read(entry.url),
                  let event = try? JSONDecoder().decode(HookEvent.self, from: data) else {
                log.info("dropped hook event: \(entry.url.lastPathComponent, privacy: .public)")
                continue
            }
            apply(event, now: now)
        }
    }

    private func apply(_ event: HookEvent, now: Date) {
        let sid = event.sessionId
        guard !sid.isEmpty else { return }
        switch event.hookEventName {
        case "Notification":
            // 우리가 보는 세 종류 말고는 무시한다(auth_success 등).
            guard let kind = AlertKind(notificationType: event.notificationType) else { return }
            alerts[sid] = Alert(kind: kind, message: event.message ?? "", since: now)
            alertStatus[sid] = nil          // 새 알림이니 상태 기준점을 다시 잡는다
        case "UserPromptSubmit":
            clearAlert(sid)                 // 사용자가 답했다
        case "SubagentStart":
            guard let agentId = event.kittenId else { return }
            // 같은 시각의 파일은 순서가 뒤집힐 수 있다. Stop 을 이미 봤으면 뒤늦게 온 Start 로
            // 되살리지 않는다.
            guard !(stoppedAgents[sid]?.contains(agentId) ?? false) else { return }
            hookAgents[sid, default: [:]][agentId] =
                HookAgent(type: event.agentType ?? "", startedAt: now)
        case "SubagentStop":
            guard let agentId = event.kittenId else { return }
            hookAgents[sid]?[agentId] = nil
            if hookAgents[sid]?.isEmpty == true { hookAgents[sid] = nil }
            recordStop(sid, agentId)
        default:
            break
        }
    }

    private func rememberProcessedEvent(_ path: String) {
        guard !processedEvents.contains(path) else { return }
        processedEvents.insert(path)
        processedEventOrder.append(path)
        if processedEventOrder.count > Self.processedEventLimit {
            let dropped = processedEventOrder.removeFirst()
            processedEvents.remove(dropped)
        }
    }

    private func forgetProcessedEvent(_ path: String) {
        guard processedEvents.remove(path) != nil else { return }
        processedEventOrder.removeAll { $0 == path }
    }

    private func recordStop(_ sessionId: String, _ agentId: String) {
        var stopped = stoppedAgents[sessionId] ?? []
        guard !stopped.contains(agentId) else { return }
        stopped.append(agentId)
        if stopped.count > Self.stoppedAgentLimit {
            stopped.removeFirst(stopped.count - Self.stoppedAgentLimit)
        }
        stoppedAgents[sessionId] = stopped
    }

    private func clearAlert(_ sessionId: String) {
        alerts[sessionId] = nil
        alertStatus[sessionId] = nil
    }

    /// 알림이 사라지는 경우는 다섯이다.
    ///
    /// 1. `UserPromptSubmit` — 사용자가 답했다 (이벤트 쪽에서 이미 지웠다)
    /// 2. **transcript mtime 이 `since` 를 지나갔다** — 권한을 승인하면 Claude 가 도구를 돌리고
    ///    transcript 에 append 한다. 제일 정확한 "답했다" 신호다. stat 은 제목 조회가 이미
    ///    하고 있으므로 공짜다(값을 넘겨받는다).
    /// 3. **idle → busy 전이** — 새 작업이 시작됐다. busy → idle 은 아니다: 권한 프롬프트가
    ///    뜨는 동안 세션이 idle 로 넘어가는 게 정상이라 그걸로 지우면 알림이 바로 사라진다.
    /// 4. 세션 소멸 (틱 끝 프루닝)
    /// 5. TTL (훅이 죽어 2·3 이 영영 안 올 때의 안전망)
    private func resolveAlert(for session: Session, now: Date, transcript: FileStat?) -> Alert? {
        guard let alert = alerts[session.id] else { return nil }
        let previousStatus = alertStatus[session.id]
        alertStatus[session.id] = session.status

        if now.timeIntervalSince(alert.since) >= alertTTL {
            clearAlert(session.id)
            return nil
        }
        if let modified = transcript?.modified, modified > alert.since {
            clearAlert(session.id)
            return nil
        }
        if previousStatus == .idle, session.status == .busy {
            clearAlert(session.id)
            return nil
        }
        return alert
    }

    /// mtime 휴리스틱과 훅이 센 서브에이전트의 합집합에서, 이미 Stop 을 받은 id 를 뺀다.
    ///
    /// 훅은 Stop 을 놓칠 수 있다(Claude 가 죽거나 훅이 실패하거나). 그러면 새끼가 영영
    /// 남으므로 `hookAgentTTL` 을 안전망으로 둔다 — 서브에이전트는 몇 시간씩 돌기도 해서
    /// 넉넉하게 잡는다.
    private func mergedSubagents(for sessionId: String, now: Date, scanned: [Subagent]) -> [Subagent] {
        if var hooked = hookAgents[sessionId] {
            hooked = hooked.filter { now.timeIntervalSince($0.value.startedAt) < hookAgentTTL }
            hookAgents[sessionId] = hooked.isEmpty ? nil : hooked
        }
        let hooked = hookAgents[sessionId] ?? [:]
        if hooked.isEmpty, stoppedAgents[sessionId] == nil { return scanned }
        var byId: [String: Subagent] = [:]
        for sub in scanned { byId[sub.id] = sub }
        for (agentId, agent) in hooked {
            // 훅이 센 쪽이 정확하다 — 같은 id 면 덮어쓴다.
            byId[agentId] = Subagent(id: agentId, description: agent.type, lastActivity: agent.startedAt)
        }
        let stopped = Set(stoppedAgents[sessionId] ?? [])
        return byId.values.filter { !stopped.contains($0.id) }.sorted { $0.id < $1.id }
    }

    // MARK: - 세션 제목

    private struct TitleLine: Decodable {
        let type: String
        let aiTitle: String
    }

    /// 유휴 틱 비용은 세션당 transcript `stat` **1회**다. 제목과 알림 해제가 이 값을 같이
    /// 쓰므로 stat 은 여기서 한 번만 한다.
    private func transcriptStat(for session: Session, now: Date) -> (url: URL, stat: FileStat)? {
        guard let root = projectRoot(for: session, now: now) else { return nil }
        let url = root.appendingPathComponent(session.id + ".jsonl")
        guard let stat = try? fs.stat(url) else { return nil }
        return (url, stat)
    }

    /// 실제 읽기(`readTail`)는 mtime 이 바뀌었고 **동시에** 마지막 읽기로부터
    /// titleRefreshInterval 이 지났을 때만 한다.
    private func title(for session: Session, now: Date, transcript: (url: URL, stat: FileStat)?) -> String? {
        guard let transcript else { return nil }
        let (transcriptURL, st) = transcript

        let cached = titleCache[session.id]
        if let cached,
           cached.modified == st.modified || now.timeIntervalSince(cached.readAt) < titleRefreshInterval {
            return cached.title
        }
        guard let data = try? fs.readTail(transcriptURL, maxBytes: Self.titleTailBytes) else {
            log.warning("tail read failed: \(transcriptURL.path, privacy: .public)")
            // 실패도 캐시에 기록해야 매 틱 재시도를 막는다(스로틀은 성공·실패 공통).
            titleCache[session.id] = (st.modified, now, cached?.title)
            return cached?.title
        }
        // 꼬리에 제목 줄이 없을 수 있다(긴 작업 중). 그럴 땐 이전 제목을 유지한다.
        // 파일이 꼬리보다 짧으면 잘린 게 아니므로 첫 줄도 온전한 줄이다.
        let title = Self.parseTitle(data, truncated: data.count >= Self.titleTailBytes) ?? cached?.title
        titleCache[session.id] = (st.modified, now, title)
        return title
    }

    /// 꼬리 바이트에서 마지막 `ai-title` 줄을 찾는다.
    /// `truncated` 면 첫 조각이 줄 한가운데서 시작하므로 버린다.
    /// 판정은 부분 문자열이 아니라 디코딩한 `type` 필드로 한다 — 프롬프트 본문에
    /// `ai-title` 이라는 글자가 들어간 줄을 제목으로 오인하지 않게.
    static func parseTitle(_ data: Data, truncated: Bool) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        let all = text.split(separator: "\n", omittingEmptySubsequences: false)
        let lines = truncated ? Array(all.dropFirst()) : Array(all)
        // 줄마다 JSON 을 디코딩하면 비싸다. 후보만 싸게 거른 뒤 디코딩한다.
        for line in lines.reversed() where line.contains("ai-title") {
            if let parsed = try? JSONDecoder().decode(TitleLine.self, from: Data(line.utf8)),
               parsed.type == "ai-title" {
                return parsed.aiTitle
            }
        }
        return nil
    }
}
