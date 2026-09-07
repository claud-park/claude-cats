import Testing
import Foundation
@testable import ClaudeCatsCore

@Suite struct FakeFileSystemTests {
    @Test func listReturnsDirectChildrenOnly() throws {
        let fs = FakeFileSystem()
        fs.add("/root/a.json", "{}", modified: .now)
        fs.add("/root/sub/b.json", "{}", modified: .now)
        let names = try fs.list(URL(fileURLWithPath: "/root")).map(\.lastPathComponent)
        #expect(names == ["a.json", "sub"])
    }

    @Test func listMissingDirThrows() {
        let fs = FakeFileSystem()
        #expect(throws: (any Error).self) { try fs.list(URL(fileURLWithPath: "/nope")) }
    }

    @Test func statWorksForFilesAndDirectories() throws {
        let fs = FakeFileSystem()
        let t = Date(timeIntervalSince1970: 1000)
        fs.add("/root/sub/b.json", "{\"a\":1}", modified: t)
        #expect(try fs.stat(URL(fileURLWithPath: "/root/sub/b.json")) == FileStat(modified: t, size: 7))
        _ = try fs.stat(URL(fileURLWithPath: "/root/sub"))
        #expect(throws: (any Error).self) { try fs.stat(URL(fileURLWithPath: "/root/zzz")) }
    }

    @Test func readCountsReads() throws {
        let fs = FakeFileSystem()
        fs.add("/f", "hi", modified: .now)
        _ = try fs.read(URL(fileURLWithPath: "/f"))
        _ = try fs.read(URL(fileURLWithPath: "/f"))
        #expect(fs.readCount["/f"] == 2)
    }
}
