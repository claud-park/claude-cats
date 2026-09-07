import AppKit
import ClaudeCatsCore
import os

/// "알림 연동" 메뉴가 실제로 파일을 만지는 자리.
/// 훅 스크립트를 앱 지원 폴더에 깔고, `~/.claude/settings.json` 에 그 스크립트를 등록한다.
/// 설정 트리를 고치는 규칙 자체는 `HookInstaller`(Core, 테스트 있음)에 있다.
@MainActor
enum HookSetup {
    private static let log = Logger(subsystem: "claude-cats", category: "hooks")
    /// 세션당 한 번만 백업한다 — 토글을 여러 번 눌러도 첫 백업(= 우리가 손대기 전 파일)을 지킨다.
    private static var backedUp = false

    // MARK: - 경로

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static var claudeDir: URL { home.appendingPathComponent(".claude") }
    static var settingsURL: URL { claudeDir.appendingPathComponent("settings.json") }
    static var backupURL: URL { claudeDir.appendingPathComponent("settings.json.claude-cats.bak") }
    /// 훅이 이벤트 파일을 떨구는 곳. 수집기가 여기를 읽고 지운다.
    static var eventsDir: URL {
        claudeDir.appendingPathComponent("claude-cats").appendingPathComponent("events")
    }

    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("ClaudeCats")
    }

    static var scriptURL: URL { supportDir.appendingPathComponent("claude-cats-hook.sh") }

    /// settings.json 에 적히는 명령. 경로에 공백이 있으므로(Application Support) 홑따옴표로 감싼다.
    static var command: String {
        "'" + scriptURL.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 훅 스크립트. stdin(JSON 한 덩어리)을 파일 하나로 옮기는 것 말고는 아무것도 안 한다.
    /// 무슨 일이 있어도 exit 0 — Claude 를 붙잡거나 막지 않는다.
    /// 임시 이름으로 받아 같은 디렉터리 안에서 rename 한다: 앱이 반쯤 쓰인 파일을 읽지 않게.
    static let script = """
    #!/bin/sh
    # Claude Cats: Claude Code 훅 페이로드를 파일 하나로 넘긴다. 절대 Claude 를 막지 않는다.
    # GENERATED — Sources/ClaudeCats/HookSetup.swift 가 쓴다. 손으로 고치지 말 것.
    d="$HOME/.claude/claude-cats/events"
    mkdir -p "$d" 2>/dev/null || exit 0
    f="$d/$(date +%s)-$$-$RANDOM"
    cat > "$f.tmp" 2>/dev/null || { rm -f "$f.tmp" 2>/dev/null; exit 0; }
    mv "$f.tmp" "$f.json" 2>/dev/null || rm -f "$f.tmp" 2>/dev/null
    exit 0

    """

    // MARK: - 상태

    /// 지금 훅이 깔려 있나. 파일이 없거나 못 읽으면 false(= 켤 수 있는 상태).
    static func isInstalled() -> Bool {
        guard let settings = try? readSettings() else { return false }
        return HookInstaller.isInstalled(in: settings, command: command)
    }

    // MARK: - 토글

    /// 켜기/끄기. 실패하면 NSAlert 하나 띄우고 아무것도 바꾸지 않는다.
    /// 되돌린 상태(= 실제 상태)를 반환한다.
    @discardableResult
    static func setInstalled(_ install: Bool) -> Bool {
        do {
            if install {
                try writeScript()
                try FileManager.default.createDirectory(at: eventsDir, withIntermediateDirectories: true)
            }
            let settings = try readSettings()
            let updated = install
                ? try HookInstaller.install(into: settings, command: command)
                : try HookInstaller.remove(from: settings, command: command)
            try writeSettings(updated)
            log.info("hooks \(install ? "installed" : "removed", privacy: .public)")
            return install
        } catch {
            report(error, installing: install)
            return isInstalled()
        }
    }

    // MARK: - 파일

    /// 없으면 빈 설정으로 본다(첫 쓰기에서 만든다). 있는데 JSON 이 아니면 던진다.
    private static func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookInstaller.MalformedSettings(path: "(최상위가 객체가 아니다)")
        }
        return object
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        if !backedUp, FileManager.default.fileExists(atPath: settingsURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.copyItem(at: settingsURL, to: backupURL)
            backedUp = true
        }
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        // 키 순서·들여쓰기는 우리가 다시 짠다(JSONSerialization 은 원본 서식을 못 지킨다).
        // sortedKeys 라도 붙여야 매번 같은 파일이 나온다 — README 의 "서식" 항목 참고.
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try (data + Data("\n".utf8)).write(to: settingsURL, options: .atomic)
    }

    private static func writeScript() throws {
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try Data(script.utf8).write(to: scriptURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    // MARK: - 실패 알림

    private static func report(_ error: any Error, installing: Bool) {
        log.error("hook setup failed: \(String(describing: error), privacy: .public)")
        let alert = NSAlert()
        alert.messageText = installing ? "알림 연동을 켜지 못했습니다" : "알림 연동을 끄지 못했습니다"
        if let malformed = error as? HookInstaller.MalformedSettings {
            alert.informativeText = """
            \(settingsURL.path) 의 `\(malformed.path)` 를 알아볼 수 없어 아무것도 고치지 않았습니다.
            그 부분을 고친 뒤 다시 시도해 주세요.
            """
        } else {
            alert.informativeText = "\(settingsURL.path)\n\(error.localizedDescription)"
        }
        alert.runModal()
    }
}
