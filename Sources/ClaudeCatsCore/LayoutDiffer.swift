public struct LayoutDiff: Sendable, Equatable {
    public var added: [CatPlacement]
    public var removed: [String]
    public var updated: [CatPlacement]

    public init(added: [CatPlacement], removed: [String], updated: [CatPlacement]) {
        self.added = added
        self.removed = removed
        self.updated = updated
    }

    public var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && updated.isEmpty
    }
}

public enum LayoutDiffer {
    public static func diff(from old: Layout, to new: Layout) -> LayoutDiff {
        var oldById: [String: CatPlacement] = [:]
        for cat in old.cats { oldById[cat.id] = cat }
        let newIds = Set(new.cats.map(\.id))

        var added: [CatPlacement] = []
        var updated: [CatPlacement] = []
        for cat in new.cats {
            if let previous = oldById[cat.id] {
                if previous != cat { updated.append(cat) }
            } else {
                added.append(cat)
            }
        }
        let removed = old.cats.map(\.id).filter { !newIds.contains($0) }
        return LayoutDiff(added: added, removed: removed, updated: updated)
    }
}
