import Testing
import Foundation
@testable import ClaudeCatsCore

/// 남의 `settings.json` 을 다루는 파일 작업. FakeFileSystem 이 아니라 **진짜 파일**에 대고
/// 확인한다 — 심볼릭 링크·권한·원자적 쓰기는 흉내로는 못 잡는다.
@Suite struct SettingsFileTests {
    /// 임시 디렉터리 하나를 만들어 클로저에 넘기고 끝나면 지운다.
    func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-cats-settings-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // /var → /private/var 심볼릭 링크 때문에 경로 비교가 어긋난다. 미리 풀어 둔다.
        try body(dir.resolvingSymlinksInPath())
    }

    func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    @Test func readsMissingAndEmptyFilesAsEmptySettings() throws {
        try withTempDir { dir in
            let missing = dir.appendingPathComponent("settings.json")
            #expect(try SettingsFile.read(missing).isEmpty)
            try Data().write(to: missing)
            #expect(try SettingsFile.read(missing).isEmpty)
        }
    }

    @Test func readThrowsWhenTopLevelIsNotAnObject() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("settings.json")
            try Data("[1, 2]".utf8).write(to: url)
            #expect(throws: SettingsFile.NotAnObject.self) { _ = try SettingsFile.read(url) }
        }
    }

    /// 핵심: dotfiles 저장소로 링크를 걸어 둔 사람의 링크를 죽이면 안 된다.
    @Test func writingThroughASymlinkKeepsTheLinkAndUpdatesTheTarget() throws {
        try withTempDir { dir in
            let target = dir.appendingPathComponent("dotfiles-settings.json")
            let link = dir.appendingPathComponent("settings.json")
            try Data(#"{"model":"opus"}"#.utf8).write(to: target)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

            try SettingsFile.write(["model": "sonnet"], to: link, backupTo: nil)

            // 링크가 아직 링크이고 여전히 원본을 가리킨다.
            let type = try FileManager.default.attributesOfItem(atPath: link.path)[.type] as? FileAttributeType
            #expect(type == .typeSymbolicLink)
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
            // 새 내용은 원본에 들어갔다 — 고아가 된 파일이 없다.
            #expect(try SettingsFile.read(target)["model"] as? String == "sonnet")
        }
    }

    @Test func writePreservesTheOriginalPermissions() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("settings.json")
            try Data("{}".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

            try SettingsFile.write(["a": 1], to: url, backupTo: nil)
            #expect(try permissions(url) == 0o600)
        }
    }

    @Test func writeThroughASymlinkPreservesTheTargetPermissions() throws {
        try withTempDir { dir in
            let target = dir.appendingPathComponent("real.json")
            let link = dir.appendingPathComponent("settings.json")
            try Data("{}".utf8).write(to: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: target.path)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

            try SettingsFile.write(["a": 1], to: link, backupTo: nil)
            #expect(try permissions(target) == 0o640)
        }
    }

    /// 백업은 우리가 손대기 전 원본이어야 한다. 두 번째 쓰기(= 앱 재실행)에 덮어쓰면
    /// "이미 훅이 든 파일"이 백업 자리에 들어가 원본이 사라진다.
    @Test func backupIsWrittenOnceAndNeverOverwritten() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("settings.json")
            let backup = dir.appendingPathComponent("settings.json.claude-cats.bak")
            try Data(#"{"original":true}"#.utf8).write(to: url)

            let first = try SettingsFile.write(["v": 1], to: url, backupTo: backup)
            #expect(first)
            #expect(try SettingsFile.read(backup)["original"] as? Bool == true)

            // 두 번째 쓰기(다음 실행이라 치고)는 백업을 건드리지 않는다.
            let second = try SettingsFile.write(["v": 2], to: url, backupTo: backup)
            #expect(second == false)
            #expect(try SettingsFile.read(backup)["original"] as? Bool == true)
            #expect(try SettingsFile.read(url)["v"] as? Int == 2)
        }
    }

    @Test func noBackupWhenThereIsNoOriginal() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("settings.json")
            let backup = dir.appendingPathComponent("settings.json.claude-cats.bak")
            let made = try SettingsFile.write(["v": 1], to: url, backupTo: backup)
            #expect(made == false)
            #expect(FileManager.default.fileExists(atPath: backup.path) == false)
        }
    }

    @Test func serializeIsStableAndEndsWithANewline() throws {
        let settings: [String: Any] = ["b": 1, "a": ["z": true, "y": "x/y"]]
        let data = try SettingsFile.serialize(settings)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasSuffix("}\n"))
        #expect(text.contains("\"x/y\""))                       // 슬래시를 이스케이프하지 않는다
        #expect(text.firstRange(of: "\"a\"")!.lowerBound < text.firstRange(of: "\"b\"")!.lowerBound)
        #expect(try SettingsFile.serialize(settings) == data)   // 매번 같은 바이트
    }
}
