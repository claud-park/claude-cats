import Foundation
import ClaudeCatsCore

let home = FileManager.default.homeDirectoryForCurrentUser
let collector = StateCollector(fileSystem: RealFileSystem(), claudeDir: home.appendingPathComponent(".claude"))
let t0 = Date()
let snap = collector.collect(now: Date())
print("tick \(Int(Date().timeIntervalSince(t0) * 1000))ms")
for s in snap.sessions {
    print(s.status == .busy ? "●" : "○", s.name, s.subagents.map(\.id))
}
