import Foundation

// `stat` C 함수는 `RealFileSystem.stat(_:)` 메서드와 이름이 겹쳐 일반적인 방식으로는
// 참조할 수 없다(타입 이니셜라이저 `stat.init()` 과도 모호해짐). 심볼을 직접 바인딩해 우회한다.
@_silgen_name("stat")
private func c_stat(_ path: UnsafePointer<Int8>, _ buf: UnsafeMutablePointer<Darwin.stat>) -> Int32

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
        var st = Darwin.stat()
        guard url.path.withCString({ c_stat($0, &st) }) == 0 else {
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
