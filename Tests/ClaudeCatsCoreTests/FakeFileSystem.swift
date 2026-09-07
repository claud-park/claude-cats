import Foundation
@testable import ClaudeCatsCore

/// 테스트 전용 인메모리 파일시스템. 테스트 하나당 인스턴스 하나만 쓴다(동기화 없음).
final class FakeFileSystem: FileSystem, @unchecked Sendable {
    private var files: [String: (data: Data, modified: Date)] = [:]
    var alivePids: Set<Int32> = []
    var readCount: [String: Int] = [:]
    /// 이 경로들의 read/readTail 은 던진다(권한 오류·경합 시뮬레이션). 시도 횟수는 센다.
    var failReads: Set<String> = []

    func add(_ path: String, _ text: String, modified: Date) {
        files[path] = (Data(text.utf8), modified)
    }

    func remove(_ path: String) {
        files[path] = nil
    }

    func touch(_ path: String, modified: Date) {
        guard let f = files[path] else { return }
        files[path] = (f.data, modified)
    }

    private func isDirectory(_ path: String) -> Bool {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        return files.keys.contains { $0.hasPrefix(prefix) }
    }

    func list(_ dir: URL) throws -> [URL] {
        let prefix = dir.path.hasSuffix("/") ? dir.path : dir.path + "/"
        guard isDirectory(dir.path) else { throw CocoaError(.fileReadNoSuchFile) }
        var children = Set<String>()
        for path in files.keys where path.hasPrefix(prefix) {
            let rest = path.dropFirst(prefix.count)
            if let first = rest.split(separator: "/", maxSplits: 1).first, !first.hasPrefix(".") {
                children.insert(prefix + first)
            }
        }
        return children.sorted().map { URL(fileURLWithPath: $0) }
    }

    func stat(_ url: URL) throws -> FileStat {
        if let f = files[url.path] { return FileStat(modified: f.modified, size: f.data.count) }
        if isDirectory(url.path) { return FileStat(modified: .distantPast, size: 0) }
        throw CocoaError(.fileReadNoSuchFile)
    }

    func read(_ url: URL) throws -> Data {
        readCount[url.path, default: 0] += 1
        guard !failReads.contains(url.path) else { throw CocoaError(.fileReadNoPermission) }
        guard let f = files[url.path] else { throw CocoaError(.fileReadNoSuchFile) }
        return f.data
    }

    func readTail(_ url: URL, maxBytes: Int) throws -> Data {
        readCount[url.path, default: 0] += 1
        guard !failReads.contains(url.path) else { throw CocoaError(.fileReadNoPermission) }
        guard let f = files[url.path] else { throw CocoaError(.fileReadNoSuchFile) }
        return f.data.count > maxBytes ? f.data.suffix(maxBytes) : f.data
    }

    func processAlive(_ pid: Int32) -> Bool {
        alivePids.contains(pid)
    }
}
