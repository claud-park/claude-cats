import Testing
import Foundation
@testable import ClaudeCatsCore

@Suite struct LayoutDifferTests {
    func cat(_ id: String, x: CGFloat = 0, pose: Pose = .sitting) -> CatPlacement {
        CatPlacement(id: id, origin: CGPoint(x: x, y: 40), scale: 1, pose: pose,
                     paletteIndex: 0, label: id, animated: false, overflowCount: 0)
    }

    @Test func emptyToEmptyIsEmptyDiff() {
        let d = LayoutDiffer.diff(from: Layout(cats: []), to: Layout(cats: []))
        #expect(d == LayoutDiff(added: [], removed: [], updated: []))
    }

    @Test func detectsAddedRemovedUpdatedAndIgnoresUnchanged() {
        let old = Layout(cats: [cat("a"), cat("b"), cat("c", pose: .sleeping)])
        let new = Layout(cats: [cat("a"), cat("c", pose: .sitting), cat("d", x: 10)])
        let d = LayoutDiffer.diff(from: old, to: new)
        #expect(d.added == [cat("d", x: 10)])
        #expect(d.removed == ["b"])
        #expect(d.updated == [cat("c", pose: .sitting)])
    }

    @Test func preservesNewLayoutOrderForAdded() {
        let new = Layout(cats: [cat("z"), cat("a")])
        let d = LayoutDiffer.diff(from: Layout(cats: []), to: new)
        #expect(d.added.map(\.id) == ["z", "a"])
    }
}
