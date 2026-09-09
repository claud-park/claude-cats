import AppKit
import ClaudeCatsCore
import os

/// 소스에서 자기 자신을 업데이트한다.
///
/// 이 앱은 릴리스 바이너리를 배포하지 않는다 — 다들 저장소를 clone 해서 직접 빌드해 쓴다.
/// 그래서 업데이트도 "새 `.app` 을 내려받기"가 아니라 **원래 빌드했던 그 저장소에서 다시
/// 빌드하기**다. `scripts/bundle.sh` 가 번들에 저장소 경로·커밋을 박아 두고(`Stamp`),
/// 여기서는 그 경로에 대고 `git fetch` 만 해 본다.
///
/// 폴링 틱에는 아무 비용도 얹지 않는다. 네트워크는 확인할 때만 쓰고, 반복 타이머도 없다 —
/// 실행 30초 뒤에 한 번, 그 뒤로는 **메뉴를 열 때** 24시간이 지났으면 한 번.
@MainActor
final class Updater {
    /// 지금 무슨 상태인가. 메뉴 항목 제목·활성 여부가 전부 여기서 나온다.
    enum Phase: Equatable, Sendable {
        /// 아직 한 번도 확인하지 않았다.
        case idle
        case checking
        /// 마지막 확인 결과.
        case checked(UpdateStatus)
        /// `install.sh --self-update` 가 도는 중.
        case installing
    }

    /// `scripts/bundle.sh` 가 Info.plist 에 박아 둔 값들.
    struct Stamp: Equatable {
        static let unknown = "unknown"

        var repoRoot: String
        var commit: String
        var commitDate: String
        var branch: String
        var version: String

        /// 메뉴의 읽기 전용 버전 줄.
        var summary: String {
            guard commit != Self.unknown else { return "버전 \(version) · 소스 정보 없음" }
            return "버전 \(version) · \(commit) · \(commitDate)"
        }
    }

    /// 마지막 확인 시각. 24시간 지나면 메뉴를 열 때 한 번 더 본다.
    private static let lastCheckKey = "lastUpdateCheck"
    /// 자동 확인 켬/끔. 키가 없으면 켜짐(기본값).
    private static let autoCheckKey = "autoUpdateCheck"
    /// 자동 확인 간격.
    private static let autoCheckInterval: TimeInterval = 24 * 60 * 60
    /// 실행 후 첫 자동 확인까지. 뜨자마자 네트워크를 쓰지 않게 조금 미룬다.
    private static let firstCheckDelay: TimeInterval = 30

    let stamp: Stamp
    private(set) var phase: Phase = .idle

    /// 상태가 바뀌면 메뉴를 다시 그리라는 신호.
    var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private let queue = DispatchQueue(label: "claude-cats.updater", qos: .utility)
    private let log = Logger(subsystem: "claude-cats", category: "updater")

    init(stamp: Stamp = .fromMainBundle()) {
        self.stamp = stamp
    }

    // MARK: - 메뉴가 보는 것

    var autoCheckEnabled: Bool {
        get { defaults.object(forKey: Self.autoCheckKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.autoCheckKey) }
    }

    var isInstalling: Bool { phase == .installing }

    /// 설치할 게 손에 잡혀 있나. 메뉴바 배지도 이걸 본다.
    var hasUpdate: Bool {
        if case .checked(.behind) = phase { return true }
        return false
    }

    var menuTitle: String {
        switch phase {
        case .checking: "업데이트 확인 중…"
        case .installing: "업데이트 중…"
        case .checked(.behind(let commits, _)): "업데이트 설치 (\(commits)개 커밋)"
        case .checked(.notAGitRepo): "업데이트: 소스 저장소를 모름"
        case .checked(.dirtyTree): "업데이트: 로컬 변경 있음"
        default: "업데이트 확인…"
        }
    }

    /// 눌러서 뭔가 할 수 있나. 도는 중이거나 저장소를 모르면 잠근다.
    var isActionable: Bool {
        switch phase {
        case .checking, .installing, .checked(.notAGitRepo): false
        default: true
        }
    }

    // MARK: - 자동 확인

    /// 실행 30초 뒤 한 번. 반복 타이머는 만들지 않는다 — 그 뒤는 `checkIfDue()` 가 맡는다.
    func scheduleFirstCheck() {
        guard isGitRepo else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstCheckDelay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.autoCheckEnabled, self.phase == .idle else { return }
                self.check(userInitiated: false)
            }
        }
    }

    /// 메뉴가 열릴 때마다 불린다. 마지막 확인이 24시간보다 오래됐을 때만 실제로 확인한다.
    func checkIfDue() {
        guard autoCheckEnabled, isGitRepo, isActionable else { return }
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < Self.autoCheckInterval {
            return
        }
        check(userInitiated: false)
    }

    // MARK: - 확인

    /// `userInitiated` 면 결과를 창으로 알린다. 자동 확인은 조용히 메뉴만 바꾼다.
    func check(userInitiated: Bool) {
        guard phase != .checking, phase != .installing else { return }
        guard isGitRepo else {
            log.info("no source repo stamped in the bundle")
            setPhase(.checked(.notAGitRepo))
            if userInitiated { presentResult(.notAGitRepo) }
            return
        }
        setPhase(.checking)
        let repo = stamp.repoRoot
        let branch = stamp.branch
        queue.async { [weak self] in
            let status = Self.performCheck(repo: repo, branch: branch)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.defaults.set(Date(), forKey: Self.lastCheckKey)
                    self.log.info("update check: \(String(describing: status), privacy: .public)")
                    self.setPhase(.checked(status))
                    if userInitiated { self.presentResult(status) }
                }
            }
        }
    }

    /// 확인의 실제 알맹이. 백그라운드 큐 전용.
    private nonisolated static func performCheck(repo: String, branch: String) -> UpdateStatus {
        appendLog("== 확인 \(timestamp()) — \(repo) (\(branch))")
        let fetch = Shell.run("git", ["-C", repo, "fetch", "--quiet", "origin", branch],
                              cwd: repo, timeout: 20)
        if fetch.status != 0 {
            // 아직 push 하지 않은 브랜치에서 도는 빌드가 흔하다(작업 브랜치에서 번들을 만든 경우).
            // origin 에 그 브랜치가 없는 건 고장이 아니라 "당길 게 없다"는 뜻이다.
            if fetch.output.contains("couldn't find remote ref") {
                appendLog("origin 에 \(branch) 브랜치가 없다 — 최신으로 본다\n\(fetch.output)")
                return .upToDate
            }
            appendLog("fetch 실패(\(fetch.status))\n\(fetch.output)")
            return .offline(reason(fetch))
        }

        let count = Shell.run("git", ["-C", repo, "rev-list", "--count", "HEAD..origin/\(branch)"],
                              cwd: repo, timeout: 10)
        guard count.status == 0 else {
            appendLog("rev-list 실패(\(count.status))\n\(count.output)")
            return .offline(reason(count))
        }
        let porcelain = Shell.run("git", ["-C", repo, "status", "--porcelain"], cwd: repo, timeout: 10)
        guard porcelain.status == 0 else {
            appendLog("status 실패(\(porcelain.status))\n\(porcelain.output)")
            return .offline(reason(porcelain))
        }
        let subject = Shell.run("git", ["-C", repo, "log", "-1", "--format=%s", "origin/\(branch)"],
                                cwd: repo, timeout: 10)

        let status = UpdateCheck.status(
            revListCount: count.output,
            logLine: subject.status == 0 ? subject.output : nil,
            statusPorcelain: porcelain.output
        )
        appendLog("결과: \(status)")
        return status
    }

    /// 실패 이유를 한 줄로. git 은 마지막 줄에 제일 쓸모 있는 말을 남긴다.
    private nonisolated static func reason(_ result: Shell.Result) -> String {
        if result.timedOut { return "시간이 초과됐습니다 (네트워크·인증 확인)" }
        let line = result.output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .last
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !line.isEmpty else { return "git 이 \(result.status) 로 끝났습니다" }
        return String(line.prefix(200))
    }

    // MARK: - 설치

    /// `scripts/install.sh --self-update` 를 돌린다. 성공하면 그 스크립트가 새 인스턴스를 띄우고
    /// 우리를 죽인다 — 여기서 앱을 내리지 않는 이유다. 실패는 **기존 앱을 건드리기 전에** 나므로
    /// 창 하나 띄우고 하던 일을 계속하면 된다.
    func install() {
        guard phase != .installing, isGitRepo else { return }
        let repo = stamp.repoRoot
        let target = UpdateCheck.targetInstallDir(
            runningBundlePath: Bundle.main.bundlePath,
            repoRoot: repo
        )
        let pid = ProcessInfo.processInfo.processIdentifier
        log.info("self-update → \(target, privacy: .public) (old pid \(pid, privacy: .public))")
        // 실패하면 여기로 되돌린다 — 업데이트는 여전히 남아 있으니 메뉴도 그렇게 말해야 한다.
        let previous = phase
        setPhase(.installing)

        queue.async { [weak self] in
            Self.appendLog("== 설치 \(Self.timestamp()) — \(repo) → \(target) (pid \(pid))")
            // 빌드가 길다(release 콜드 빌드는 분 단위). 출력은 그때그때 로그로 흘린다.
            let result = Shell.run(
                "/bin/bash",
                ["\(repo)/scripts/install.sh", "--self-update", target, "\(pid)"],
                cwd: repo,
                timeout: 15 * 60,
                onOutput: { chunk in Self.appendLog(chunk, newline: false) }
            )
            Self.appendLog("== 설치 종료 (\(result.status))")
            Self.trimLog()
            let tail = Self.lastLines(of: result.output, count: 20)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if result.status == 0 {
                        // 새 인스턴스가 이미 떴다. 스크립트가 곧 우리에게 SIGTERM 을 보낸다.
                        self.log.info("self-update done — waiting to be replaced")
                        self.setPhase(.checked(.upToDate))
                    } else {
                        self.log.error("self-update failed (\(result.status, privacy: .public))")
                        self.setPhase(previous)
                        self.presentFailure(tail: tail, timedOut: result.timedOut)
                    }
                }
            }
        }
    }

    // MARK: - 알림창

    private func presentResult(_ status: UpdateStatus) {
        let alert = NSAlert()
        switch status {
        case .upToDate:
            alert.messageText = "최신 버전입니다"
            alert.informativeText = stamp.summary
            alert.addButton(withTitle: "확인")
        case .behind(let commits, let subject):
            alert.messageText = "업데이트 \(commits)개 커밋이 있습니다"
            let latest = subject.isEmpty ? "" : "최신 커밋 — \"\(subject)\"\n\n"
            alert.informativeText = latest
                + "소스를 받아 다시 빌드한 뒤 앱을 새로 띄웁니다. 빌드에 1~2분쯤 걸립니다."
            alert.addButton(withTitle: "지금 업데이트")
            alert.addButton(withTitle: "나중에")
        case .dirtyTree:
            alert.messageText = "로컬 변경이 있어 업데이트하지 않았습니다"
            alert.informativeText = """
            \(stamp.repoRoot) 에 커밋하지 않은 변경이 있습니다.
            그 위로 당기면 작업을 잃을 수 있어 아무것도 하지 않았습니다.
            변경을 커밋하거나 치운 뒤 다시 확인해 주세요.
            """
            alert.addButton(withTitle: "확인")
        case .notAGitRepo:
            alert.messageText = "소스 저장소를 모릅니다"
            alert.informativeText = """
            이 번들에는 빌드한 저장소 경로가 박혀 있지 않거나, 그 자리에 저장소가 없습니다.
            저장소에서 `./scripts/install.sh` 로 다시 설치하면 업데이트를 쓸 수 있습니다.
            """
            alert.addButton(withTitle: "확인")
        case .offline(let why):
            alert.messageText = "업데이트를 확인하지 못했습니다"
            alert.informativeText = "\(why)\n\n\(Self.logURL.path)"
            alert.addButton(withTitle: "확인")
            alert.addButton(withTitle: "로그 열기")
        }

        NSApp.activate()
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            if case .offline = status, response == .alertSecondButtonReturn { openLog() }
            return
        }
        if case .behind = status { install() }
    }

    private func presentFailure(tail: String, timedOut: Bool) {
        let alert = NSAlert()
        alert.messageText = "업데이트에 실패했습니다"
        let head = timedOut
            ? "빌드가 15분을 넘겨 중단했습니다. 앱은 그대로입니다.\n\n"
            : "앱은 그대로 두었습니다. 마지막 로그입니다.\n\n"
        alert.informativeText = head + (tail.isEmpty ? Self.logURL.path : tail)
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "로그 열기")
        NSApp.activate()
        if alert.runModal() == .alertSecondButtonReturn { openLog() }
    }

    private func openLog() {
        NSWorkspace.shared.open(Self.logURL)
    }

    // MARK: - 상태

    private var isGitRepo: Bool {
        guard stamp.repoRoot != Stamp.unknown, !stamp.repoRoot.isEmpty else { return false }
        // worktree 는 `.git` 이 디렉터리가 아니라 파일이다. 존재만 본다.
        return FileManager.default.fileExists(atPath: stamp.repoRoot + "/.git")
    }

    private func setPhase(_ new: Phase) {
        guard phase != new else { return }
        phase = new
        onChange?()
    }

    // MARK: - 로그

    /// 업데이트 로그. 앱 로그(`log stream`)와 달리 빌드 출력을 통째로 담아야 해서 파일로 둔다.
    nonisolated static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ClaudeCats/update.log")
    }

    /// 로그 상한. 넘으면 앞을 잘라 최근 1MB 만 남긴다.
    private nonisolated static let logLimit = 1024 * 1024

    private nonisolated static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }

    /// 이어 쓴다. `queue`(직렬)에서만 부르므로 잠금은 없다.
    private nonisolated static func appendLog(_ text: String, newline: Bool = true) {
        let url = logURL
        let data = Data((newline ? text + "\n" : text).utf8)
        let manager = FileManager.default
        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? data.write(to: url)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    /// 최근 1MB 만 남긴다. 줄 가운데서 자르지 않게 첫 줄바꿈까지 더 버린다.
    private nonisolated static func trimLog() {
        let url = logURL
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size > logLimit, let data = try? Data(contentsOf: url) else { return }
        var tail = data.suffix(logLimit)
        if let newline = tail.firstIndex(of: 0x0A) { tail = tail[(newline + 1)...] }
        try? Data(tail).write(to: url, options: .atomic)
    }

    private nonisolated static func lastLines(of text: String, count: Int) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(count)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Info.plist

extension Updater.Stamp {
    /// `scripts/bundle.sh` 가 박아 둔 값. 번들 밖(`.build/debug/ClaudeCats` 직접 실행)이면 전부 unknown.
    static func fromMainBundle() -> Self {
        func value(_ key: String) -> String {
            let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
            return raw.isEmpty ? unknown : raw
        }
        return Self(
            repoRoot: value("ClaudeCatsSourceRepo"),
            commit: value("ClaudeCatsCommit"),
            commitDate: value("ClaudeCatsCommitDate"),
            branch: value("ClaudeCatsBranch"),
            version: value("CFBundleShortVersionString")
        )
    }
}

// MARK: - 프로세스

/// 명령 하나를 돌리고 끝날 때까지 기다린다. **백그라운드 큐에서만** 부를 것.
private enum Shell {
    struct Result {
        var status: Int32
        /// stdout·stderr 합본(끝에서 64KB까지). 순서를 보존하려고 파이프 하나를 같이 쓴다.
        var output: String
        var timedOut: Bool
    }

    /// 앱 번들은 Finder 가 띄우므로 PATH 가 거의 비어 있다. git·swift 가 있을 만한 곳을 직접 깐다.
    private static let searchPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    private static let outputLimit = 64 * 1024

    /// `Process` 는 `Sendable` 이 아닌데 감시 타이머가 다른 스레드에서 봐야 한다.
    /// 보는 건 `isRunning` 과 `terminate()` 둘뿐이고 둘 다 스레드 안전하다.
    private final class Box: @unchecked Sendable {
        let process = Process()
    }

    /// `onOutput` 은 읽는 족족 불린다(설치 로그 흘리기용). 호출한 큐에서 그대로 실행된다.
    static func run(
        _ executable: String,
        _ arguments: [String],
        cwd: String?,
        timeout: TimeInterval,
        onOutput: ((String) -> Void)? = nil
    ) -> Result {
        let box = Box()
        let process = box.process
        // 절대 경로가 아니면 PATH 에서 찾는다(`/usr/bin/env` 가 그 일을 한다).
        if executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
        }
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath
        // 물어보는 순간 타임아웃까지 매달린다. 인증이 필요하면 그냥 실패하는 편이 낫다.
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_PAGER"] = "cat"
        environment["GIT_ASKPASS"] = "/usr/bin/true"
        environment["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return Result(status: -1, output: "\(executable) 실행 실패: \(error.localizedDescription)", timedOut: false)
        }

        // 시간이 넘으면 SIGTERM. 파이프가 닫히면서 아래 읽기 루프도 같이 끝난다.
        let watchdog = DispatchWorkItem { if box.process.isRunning { box.process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

        var collected = Data()
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            onOutput?(String(decoding: chunk, as: UTF8.self))
            collected.append(chunk)
            if collected.count > outputLimit { collected = Data(collected.suffix(outputLimit)) }
        }
        process.waitUntilExit()
        watchdog.cancel()

        return Result(
            status: process.terminationStatus,
            output: String(decoding: collected, as: UTF8.self),
            // 우리가 죽인 것 말고 git 이 시그널로 죽을 일은 거의 없다.
            timedOut: process.terminationReason == .uncaughtSignal
        )
    }
}
