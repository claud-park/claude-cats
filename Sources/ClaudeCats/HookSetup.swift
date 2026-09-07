import AppKit
import ClaudeCatsCore
import os

/// "알림 연동" 메뉴가 실제로 파일을 만지는 자리.
/// 훅 스크립트를 앱 지원 폴더에 깔고, `~/.claude/settings.json` 에 그 스크립트를 등록한다.
/// 설정 트리를 고치는 규칙 자체는 `HookInstaller`(Core, 테스트 있음)에 있다.
@MainActor
enum HookSetup {
    private static let log = Logger(subsystem: "claude-cats", category: "hooks")

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

    /// 앱이 안 떠 있는 동안 훅이 쌓을 수 있는 이벤트 파일 수의 상한. 넘으면 훅이 그냥 쉰다.
    static let eventBacklogLimit = 5000

    /// 훅 스크립트. stdin(JSON 한 덩어리)을 파일 하나로 옮기는 것 말고는 아무것도 안 한다.
    /// 무슨 일이 있어도 exit 0 — Claude 를 붙잡거나 막지 않는다.
    /// 임시 이름으로 받아 같은 디렉터리 안에서 rename 한다: 앱이 반쯤 쓰인 파일을 읽지 않게.
    /// 앱이 꺼져 있으면 아무도 안 치우므로, 쌓인 게 많으면 쓰지 않고 나간다
    /// (`find | head` 로 상한 + 1 개까지만 세므로 디렉터리가 아무리 커도 비용이 일정하다).
    static let script = """
    #!/bin/sh
    # Claude Cats: Claude Code 훅 페이로드를 파일 하나로 넘긴다. 절대 Claude 를 막지 않는다.
    # GENERATED — Sources/ClaudeCats/HookSetup.swift 가 쓴다. 손으로 고치지 말 것.
    d="$HOME/.claude/claude-cats/events"
    mkdir -p "$d" 2>/dev/null || exit 0
    n=$(find "$d" -maxdepth 1 -name '*.json' 2>/dev/null | head -\(eventBacklogLimit + 1) | wc -l)
    [ "$n" -gt \(eventBacklogLimit) ] && exit 0
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
            // 끄기인데 파일이 아예 없으면 만들지 않는다 — 훅을 켠 적 없는 사용자에게 `{}` 를
            // 남길 이유가 없다. 바뀐 게 없어도 쓰지 않는다: 사용자가 손으로 잡아 둔 서식을
            // 괜히 다시 짜고 백업·mtime 을 건드리게 된다.
            let exists = FileManager.default.fileExists(atPath: resolvedSettingsURL.path)
            let changed = try serialized(settings) != serialized(updated)
            if changed, exists || install {
                try writeSettings(updated)
            }
            log.info("hooks \(install ? "installed" : "removed", privacy: .public) (written: \(changed && (exists || install), privacy: .public))")
            return install
        } catch {
            report(error, installing: install)
            return isInstalled()
        }
    }

    // MARK: - 파일

    /// 심볼릭 링크를 따라간 실제 경로(`SettingsFile` 이 하는 일과 같다 — 존재 확인용).
    static var resolvedSettingsURL: URL { SettingsFile.resolve(settingsURL) }

    private static func readSettings() throws -> [String: Any] {
        try SettingsFile.read(settingsURL)
    }

    private static func serialized(_ settings: [String: Any]) throws -> Data {
        try SettingsFile.serialize(settings)
    }

    /// 백업은 **우리가 손대기 전 원본**이어야 한다. 앱을 다시 켤 때마다 덮어쓰면
    /// 두 번째 실행에서 "이미 훅이 든 파일"이 백업 자리에 들어가 원본이 사라진다 —
    /// 그래서 `SettingsFile` 이 백업 자리가 비어 있을 때만 만든다(실행마다가 아니라 딱 한 번).
    private static func writeSettings(_ settings: [String: Any]) throws {
        let madeBackup = try SettingsFile.write(settings, to: settingsURL, backupTo: backupURL)
        if madeBackup { log.info("backed up settings to \(backupURL.path, privacy: .public)") }
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
        } else if error is SettingsFile.NotAnObject {
            alert.informativeText = """
            \(settingsURL.path) 가 JSON 객체가 아니라 아무것도 고치지 않았습니다.
            파일을 고친 뒤 다시 시도해 주세요.
            """
        } else {
            alert.informativeText = "\(settingsURL.path)\n\(error.localizedDescription)"
        }
        alert.runModal()
    }
}
