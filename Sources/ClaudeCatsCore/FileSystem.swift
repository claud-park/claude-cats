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
    /// 파일 끝에서 최대 maxBytes 만. transcript 는 수 MB 라 통째로 읽지 않는다.
    /// 앞쪽이 UTF-8 문자 중간에서 잘릴 수 있으니 호출자가 첫 줄을 버려야 한다.
    func readTail(_ url: URL, maxBytes: Int) throws -> Data
    /// 파일 하나를 지운다. 없으면 throw. (훅 이벤트 파일은 한 번 읽고 지운다.)
    func remove(_ url: URL) throws
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

    public func readTail(_ url: URL, maxBytes: Int) throws -> Data {
        guard maxBytes > 0 else { return Data() }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try handle.seek(toOffset: offset)
        // transcript 는 계속 append 된다. seek 와 read 사이에 파일이 자라면
        // readToEnd() 는 maxBytes 를 넘겨 읽는다 — 그래서 길이를 명시한다.
        let wanted = min(maxBytes, Int(size - offset))
        return try handle.read(upToCount: wanted) ?? Data()
    }

    public func remove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func processAlive(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
