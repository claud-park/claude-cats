import Testing
import Foundation
@testable import ClaudeCatsCore

@Suite struct SceneTests {
    let screen = CGSize(width: 1440, height: 900)   // slotCount = 10

    func session(_ name: String, status: Status = .idle, subagents: [Subagent] = [],
                 title: String? = nil) -> Session {
        Session(id: "id-\(name)", pid: 1, name: name, cwd: "/", status: status,
                subagents: subagents, title: title)
    }

    func sub(_ id: String) -> Subagent {
        Subagent(id: id, description: "", lastActivity: .now)
    }

    func layout(_ sessions: [Session], animations: Bool = true) -> Layout {
        Scene.layout(Snapshot(sessions: sessions, takenAt: .now), screenSize: screen, animationsEnabled: animations)
    }

    @Test func fnv1aIsStable() {
        #expect(StableHash.fnv1a("") == 0xcbf29ce484222325)
        #expect(StableHash.fnv1a("a") == 0xaf63dc4c8601ec8c)
    }

    @Test func deterministicForSameInput() {
        let s = [session("alpha", status: .busy), session("beta"), session("gamma")]
        #expect(layout(s) == layout(s))
    }

    @Test func poseAndLabelFollowStatus() {
        let l = layout([session("busy1", status: .busy), session("idle1", status: .idle)])
        let busy = l.cats.first { $0.label == "busy1" }!
        let idle = l.cats.first { $0.label == "idle1" }!
        #expect(busy.pose == .sitting && busy.animated == true)
        #expect(idle.pose == .sleeping && idle.animated == false)
        #expect(busy.scale == 1 && busy.id == "id-busy1")
    }

    @Test func animationsDisabledTurnsOffAnimatedFlag() {
        let l = layout([session("b", status: .busy, subagents: [sub("x")])], animations: false)
        #expect(l.cats.allSatisfy { $0.animated == false })
        #expect(l.cats.first { $0.label == "b" }?.pose == .sitting)
    }

    @Test func originsAlignToSlotsAndBottomInset() {
        let l = layout([session("only")])
        let cat = l.cats[0]
        #expect(cat.origin.y == 40)
        #expect((cat.origin.x - 16).truncatingRemainder(dividingBy: 140) == 0)
        #expect(cat.origin.x >= 16 && cat.origin.x < 1440)
    }

    @Test func collisionsProbeToDistinctSlotsInSameRow() {
        // 슬롯 10개에 세션 10개: 충돌이 나도 전부 첫 줄(y == 40), x 는 서로 다름
        let s = (0..<10).map { session("s\($0)") }
        let l = layout(s)
        #expect(l.cats.allSatisfy { $0.origin.y == 40 })
        #expect(Set(l.cats.map(\.origin.x)).count == 10)
    }

    @Test func overflowGoesToSecondRow() {
        let s = (0..<11).map { session("s\($0)") }
        let l = layout(s)
        #expect(l.cats.filter { $0.origin.y == 140 }.count == 1)
        #expect(l.cats.filter { $0.origin.y == 40 }.count == 10)
    }

    @Test func kittensSitRightOfParentWithSameColorAndHalfScale() {
        let l = layout([session("p", status: .busy, subagents: [sub("k1"), sub("k2")])])
        let parent = l.cats.first { $0.id == "id-p" }!
        let k1 = l.cats.first { $0.id == "id-p/k1" }!
        let k2 = l.cats.first { $0.id == "id-p/k2" }!
        #expect(k1.scale == 0.5 && k1.label == nil && k1.pose == .sitting && k1.animated)
        #expect(k1.paletteIndex == parent.paletteIndex)
        #expect(k1.origin == CGPoint(x: parent.origin.x + 64 + 24, y: parent.origin.y))
        #expect(k2.origin == CGPoint(x: k1.origin.x + 10, y: k1.origin.y + 10))
        #expect(k1.overflowCount == 0 && k2.overflowCount == 0)
    }

    @Test func atMostThreeKittensThenOverflowBadge() {
        let subs = ["a", "b", "c", "d", "e"].map(sub)
        let l = layout([session("p", status: .busy, subagents: subs)])
        let kittens = l.cats.filter { $0.id.hasPrefix("id-p/") }
        #expect(kittens.count == 3)
        #expect(kittens.map(\.overflowCount) == [0, 0, 2])
    }

    @Test func sessionTitleBecomesBubbleAndKittensHaveNone() {
        let l = layout([session("p", status: .busy, subagents: [sub("k1")], title: "wallpaper app")])
        #expect(l.cats.first { $0.id == "id-p" }?.bubble == "wallpaper app")
        #expect(l.cats.first { $0.id == "id-p/k1" }?.bubble == nil)
    }

    @Test func missingOrEmptyTitleGivesNoBubble() {
        let l = layout([session("none"), session("empty", title: "")])
        #expect(l.cats.first { $0.id == "id-none" }?.bubble == nil)
        #expect(l.cats.first { $0.id == "id-empty" }?.bubble == nil)
    }

    @Test func bubbleChangeChangesLayoutEquality() {
        #expect(layout([session("a", title: "one")]) != layout([session("a", title: "two")]))
    }

    @Test func paletteIndexWithinRangeAndStable() {
        let a = layout([session("obsidian-71")]).cats[0].paletteIndex
        let b = layout([session("obsidian-71"), session("other")]).cats.first { $0.label == "obsidian-71" }!.paletteIndex
        #expect(a == b && (0..<8).contains(a))
    }

    /// paletteSize 0 이면 `% 0` 이라 트랩한다. 0 은 1 로 보고 살아남아야 한다.
    @Test func zeroPaletteSizeDoesNotTrap() {
        var config = SceneConfig()
        config.paletteSize = 0
        let l = Scene.layout(Snapshot(sessions: [session("a")], takenAt: .now),
                             screenSize: screen, animationsEnabled: false, config: config)
        #expect(l.cats[0].paletteIndex == 0)
    }
}
