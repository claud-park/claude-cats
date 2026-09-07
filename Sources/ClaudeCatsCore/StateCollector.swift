import Foundation
import os

/// ~/.claude 를 읽어 Snapshot 을 만든다.
/// 스레드 안전하지 않다. 항상 같은 직렬 큐에서 collect 를 호출할 것.
public final class StateCollector: @unchecked Sendable {
    public var subagentActiveWindow: TimeInterval = 15
    public var projectLookupRetry: TimeInterval = 60

    private let fs: any FileSystem
    private let claudeDir: URL
    private let log = Logger(subsystem: "claude-cats", category: "collector")

    /// key: sessions/<pid>.json 경로
    private var sessionCache: [String: (modified: Date, session: Session)] = [:]
    /// key: sessionId. url 이 nil 이면 실패 캐시(checkedAt + projectLookupRetry 후 재시도).
    private var projectDirCache: [String: (url: URL?, checkedAt: Date)] = [:]
    /// key: meta.json 경로 → description
    private var metaCache: [String: String] = [:]

    public init(fileSystem: any FileSystem, claudeDir: URL) {
        self.fs = fileSystem
        self.claudeDir = claudeDir
    }

    public func collect(now: Date) -> Snapshot {
        let sessionsDir = claudeDir.appendingPathComponent("sessions")
        let files = (try? fs.list(sessionsDir)) ?? []
        var sessions: [Session] = []
        var seenPaths = Set<String>()
        var seenIds = Set<String>()

        for file in files where file.pathExtension == "json" {
            guard let st = try? fs.stat(file) else { continue }
            seenPaths.insert(file.path)

            var session: Session
            if let cached = sessionCache[file.path], cached.modified == st.modified {
                session = cached.session
            } else {
                guard let data = try? fs.read(file) else {
                    log.warning("read failed: \(file.path, privacy: .public)")
                    continue
                }
                guard let parsed = Self.parseSession(data) else {
                    log.debug("skipped session file: \(file.path, privacy: .public)")
                    continue
                }
                session = parsed
                sessionCache[file.path] = (st.modified, parsed)
            }

            guard fs.processAlive(session.pid) else { continue }
            guard !seenIds.contains(session.id) else { continue }
            seenIds.insert(session.id)

            session.subagents = session.status == .busy ? activeSubagents(for: session, now: now) : []
            sessions.append(session)
        }

        sessionCache = sessionCache.filter { seenPaths.contains($0.key) }
        sessions.sort { $0.name < $1.name }
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

    private func projectDir(for session: Session, now: Date) -> URL? {
        if let cached = projectDirCache[session.id] {
            if cached.url != nil { return cached.url }
            if now.timeIntervalSince(cached.checkedAt) < projectLookupRetry { return nil }
        }
        let projects = claudeDir.appendingPathComponent("projects")
        let guess = projects
            .appendingPathComponent(Self.encodeCwd(session.cwd))
            .appendingPathComponent(session.id)
        var found: URL? = (try? fs.stat(guess)) != nil ? guess : nil
        if found == nil, let dirs = try? fs.list(projects) {
            for dir in dirs {
                let candidate = dir.appendingPathComponent(session.id)
                if (try? fs.stat(candidate)) != nil {
                    found = candidate
                    break
                }
            }
        }
        projectDirCache[session.id] = (found, now)
        return found
    }

    private func activeSubagents(for session: Session, now: Date) -> [Subagent] {
        guard let dir = projectDir(for: session, now: now) else { return [] }
        let subDir = dir.appendingPathComponent("subagents")
        guard let files = try? fs.list(subDir) else { return [] }

        var result: [Subagent] = []
        for file in files where file.pathExtension == "jsonl" {
            guard let st = try? fs.stat(file),
                  now.timeIntervalSince(st.modified) <= subagentActiveWindow else { continue }
            let base = file.deletingPathExtension().lastPathComponent
            let id = base.hasPrefix("agent-") ? String(base.dropFirst("agent-".count)) : base
            let metaURL = file.deletingPathExtension().appendingPathExtension("meta.json")
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
}
