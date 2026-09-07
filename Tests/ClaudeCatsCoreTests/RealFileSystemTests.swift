import Testing
import Foundation
@testable import ClaudeCatsCore

/// FakeFileSystem 이 아니라 진짜 파일에 대고 readTail 경계를 확인한다.
@Suite struct RealFileSystemTests {
    let fs = RealFileSystem()

    /// 임시 디렉터리에 파일 하나 만들고 readTail 결과를 돌려준다. 끝나면 지운다.
    func tail(_ text: String, maxBytes: Int) throws -> Data {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-cats-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("t.jsonl")
        try Data(text.utf8).write(to: file)
        return try fs.readTail(file, maxBytes: maxBytes)
    }

    @Test func readTailReturnsLastBytesWhenFileIsLonger() throws {
        let data = try tail("0123456789", maxBytes: 4)
        #expect(data == Data("6789".utf8))
        #expect(data.count == 4)
    }

    @Test func readTailReturnsWholeFileWhenShorterThanMax() throws {
        #expect(try tail("abc", maxBytes: 4) == Data("abc".utf8))
    }

    @Test func readTailOnEmptyFileReturnsEmpty() throws {
        #expect(try tail("", maxBytes: 4).isEmpty)
    }

    /// 꼬리 크기와 파일 크기가 정확히 같은 경계.
    @Test func readTailExactSize() throws {
        #expect(try tail("abcd", maxBytes: 4) == Data("abcd".utf8))
    }

    @Test func readTailWithZeroMaxBytesReturnsEmpty() throws {
        #expect(try tail("abcd", maxBytes: 0).isEmpty)
    }

    @Test func statReportsSizeAndReadReturnsWholeFile() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-cats-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("t.jsonl")
        try Data("hello".utf8).write(to: file)
        #expect(try fs.stat(file).size == 5)
        #expect(try fs.read(file) == Data("hello".utf8))
    }

    @Test func readTailOnMissingFileThrows() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("claude-cats-missing-" + UUID().uuidString)
        #expect(throws: (any Error).self) { try fs.readTail(missing, maxBytes: 16) }
    }
}
