import Foundation

/// `settings.json` 을 읽고 쓰는 자리. 남의 파일이라 조심할 게 몇 가지 있다.
///
/// - **심볼릭 링크**: dotfiles 저장소로 `~/.claude/settings.json` 에 링크를 걸어 두는 사람들이
///   있다. `.atomic` 쓰기는 새 파일을 만들어 링크 **위에** rename 하므로 링크가 죽고 원본이
///   고아가 된다. 그래서 읽기·백업·쓰기 모두 링크를 따라간 실제 경로에 대고 한다.
/// - **권한**: `.atomic` 이 만든 새 파일은 umask 기본값을 받는다. 원래 파일 권한을 읽어 두었다가
///   되돌린다.
/// - **백업**: 우리가 손대기 전 원본이어야 의미가 있다. 이미 있으면 덮어쓰지 않는다.
public enum SettingsFile {
    /// 최상위가 JSON 객체가 아닐 때.
    public struct NotAnObject: Error, Equatable {
        public let path: String
        public init(path: String) { self.path = path }
    }

    /// 심볼릭 링크를 따라간 실제 경로.
    ///
    /// `resolvingSymlinksInPath()` 는 **대상이 없는 링크**(아직 안 만든 dotfiles 파일, 다른
    /// 머신에서 만든 링크)를 만나면 링크 경로를 그대로 돌려준다. 그 상태로 쓰면 링크를
    /// 지우고 그 자리에 일반 파일을 놓게 된다 — 링크를 죽이지 않으려면 직접 따라가야 한다.
    public static func resolve(_ url: URL) -> URL {
        let resolved = url.resolvingSymlinksInPath()
        guard resolved.path == url.path, isSymbolicLink(url) else { return resolved }
        guard let destination = try? FileManager.default
            .destinationOfSymbolicLink(atPath: url.path) else { return resolved }
        // 상대 경로 링크는 링크가 있는 디렉터리 기준이다.
        let target = destination.hasPrefix("/")
            ? URL(fileURLWithPath: destination)
            : url.deletingLastPathComponent().appendingPathComponent(destination)
        // 대상이 또 링크일 수 있다. 한 번 더 풀어 본다(순환은 standardized 로 끊는다).
        return target.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    /// 파일이 없거나 비어 있으면 빈 설정. 있는데 JSON 객체가 아니면 던진다.
    public static func read(_ url: URL) throws -> [String: Any] {
        let target = resolve(url)
        guard FileManager.default.fileExists(atPath: target.path) else { return [:] }
        let data = try Data(contentsOf: target)
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NotAnObject(path: url.path)
        }
        return object
    }

    /// 키 순서·들여쓰기는 우리가 다시 짠다(JSONSerialization 은 원본 서식을 못 지킨다).
    /// sortedKeys 라도 붙여야 매번 같은 파일이 나온다 — README 의 "서식" 항목 참고.
    public static func serialize(_ settings: [String: Any]) throws -> Data {
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return data + Data("\n".utf8)
    }

    /// `backupTo` 가 있고 그 자리가 **비어 있을 때만** 원본을 복사해 둔다.
    /// 반환값은 이번 호출이 백업을 만들었는지 여부.
    @discardableResult
    public static func write(_ settings: [String: Any], to url: URL, backupTo backup: URL?) throws -> Bool {
        let target = resolve(url)
        let manager = FileManager.default
        let existed = manager.fileExists(atPath: target.path)

        var madeBackup = false
        if let backup, existed, !manager.fileExists(atPath: backup.path) {
            try manager.copyItem(at: target, to: backup)
            madeBackup = true
        }

        let permissions = existed
            ? (try? manager.attributesOfItem(atPath: target.path))?[.posixPermissions] as? NSNumber
            : nil

        try manager.createDirectory(at: target.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
        try serialize(settings).write(to: target, options: .atomic)
        if let permissions {
            try? manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
        }
        return madeBackup
    }
}
