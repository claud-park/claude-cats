import Foundation

/// 구조체 메서드 이름 `stat` 과의 충돌을 피하기 위한 파일 스코프 헬퍼.
private func posixStat(_ path: String) -> Darwin.stat? {
    var st = Darwin.stat()
    return stat(path, &st) == 0 ? st : nil
}

public struct FileStat: Sendable, Equatable {
    public var modified: Date
    public var size: Int

    public init(modified: Date, size: Int) {
        self.modified = modified
        self.size = size
    }
}

public protocol FileSystem: Sendable {
    /// 디렉터리의 직계 자식. 숨김 파일 제외. 디렉터리가 없으면 throw.
    func list(_ dir: URL) throws -> [URL]
    /// 파일·디렉터리 모두. 없으면 throw.
    func stat(_ url: URL) throws -> FileStat
    func read(_ url: URL) throws -> Data
    /// kill(pid, 0) 기준. EPERM 은 살아있는 것으로 본다.
    func processAlive(_ pid: Int32) -> Bool
}

public struct RealFileSystem: FileSystem {
    public init() {}

    public func list(_ dir: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
    }

    public func stat(_ url: URL) throws -> FileStat {
        guard let st = posixStat(url.path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let seconds = TimeInterval(st.st_mtimespec.tv_sec)
        let nanos = TimeInterval(st.st_mtimespec.tv_nsec) / 1_000_000_000
        return FileStat(modified: Date(timeIntervalSince1970: seconds + nanos), size: Int(st.st_size))
    }

    public func read(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func processAlive(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
