import Foundation
import os

/// ~/.claude 를 읽어 Snapshot 을 만든다.
/// 스레드 안전하지 않다. 항상 같은 직렬 큐에서 collect 를 호출할 것.
public final class StateCollector: @unchecked Sendable {
    public var subagentActiveWindow: TimeInterval = 15
    public var projectLookupRetry: TimeInterval = 60
    /// transcript 를 다시 읽기까지의 최소 간격. mtime 이 바뀌어도 이 시간 전엔 안 읽는다.
    public var titleRefreshInterval: TimeInterval = 10

    /// transcript 는 수 MB 까지 자란다. 꼬리 256KB 만 본다.
    static let titleTailBytes = 262_144

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

    public init(fileSystem: any FileSystem, claudeDir: URL) {
        self.fs = fileSystem
        self.claudeDir = claudeDir
    }

    public func collect(now: Date) -> Snapshot {
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

            session.subagents = session.status == .busy
                ? activeSubagents(for: session, now: now, seenMetaPaths: &seenMetaPaths)
                : []
            session.title = title(for: session, now: now)
            sessions.append(session)
        }

        sessionCache = sessionCache.filter { seenPaths.contains($0.key) }
        titleCache = titleCache.filter { seenIds.contains($0.key) }
        projectRootCache = projectRootCache.filter { seenIds.contains($0.key) }
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
            let base = file.deletingPathExtension().lastPathComponent
            let id = base.hasPrefix("agent-") ? String(base.dropFirst("agent-".count)) : base
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

    // MARK: - 세션 제목

    private struct TitleLine: Decodable {
        let type: String
        let aiTitle: String
    }

    /// 유휴 틱 비용은 세션당 transcript `stat` 1회다. 실제 읽기(`readTail`)는
    /// mtime 이 바뀌었고 **동시에** 마지막 읽기로부터 titleRefreshInterval 이 지났을 때만.
    private func title(for session: Session, now: Date) -> String? {
        guard let root = projectRoot(for: session, now: now) else { return nil }
        let transcript = root.appendingPathComponent(session.id + ".jsonl")
        guard let st = try? fs.stat(transcript) else { return nil }

        let cached = titleCache[session.id]
        if let cached,
           cached.modified == st.modified || now.timeIntervalSince(cached.readAt) < titleRefreshInterval {
            return cached.title
        }
        guard let data = try? fs.readTail(transcript, maxBytes: Self.titleTailBytes) else {
            log.warning("tail read failed: \(transcript.path, privacy: .public)")
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
