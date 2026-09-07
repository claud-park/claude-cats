import Foundation
import CoreGraphics

public enum Pose: Sendable, Equatable {
    case sitting
    case sleeping
}

public struct CatPlacement: Sendable, Equatable, Identifiable {
    public var id: String
    public var origin: CGPoint
    public var scale: CGFloat
    public var pose: Pose
    public var paletteIndex: Int
    public var label: String?
    public var animated: Bool
    public var overflowCount: Int
    /// 머리 위 말풍선 문구(세션 제목). 새끼와 제목 없는 세션은 nil.
    public var bubble: String?

    public init(id: String, origin: CGPoint, scale: CGFloat, pose: Pose, paletteIndex: Int,
                label: String?, animated: Bool, overflowCount: Int, bubble: String? = nil) {
        self.id = id
        self.origin = origin
        self.scale = scale
        self.pose = pose
        self.paletteIndex = paletteIndex
        self.label = label
        self.animated = animated
        self.overflowCount = overflowCount
        self.bubble = bubble
    }
}

public struct Layout: Sendable, Equatable {
    public var cats: [CatPlacement]
    public init(cats: [CatPlacement]) { self.cats = cats }
}

public struct SceneConfig: Sendable {
    public var slotWidth: CGFloat = 140
    public var bottomInset: CGFloat = 40
    public var rowHeight: CGFloat = 100
    public var catWidth: CGFloat = 64
    public var slotPadding: CGFloat = 16
    public var kittenGap: CGFloat = 24
    public var kittenStack: CGFloat = 10
    public var maxKittens: Int = 3
    public var paletteSize: Int = 8
    public init() {}
}

public enum Scene {
    public static func layout(
        _ snapshot: Snapshot,
        screenSize: CGSize,
        animationsEnabled: Bool,
        config: SceneConfig = SceneConfig()
    ) -> Layout {
        let slotCount = max(1, Int(screenSize.width / config.slotWidth))
        var occupied = Set<Int>()   // row * slotCount + col
        var cats: [CatPlacement] = []

        for session in snapshot.sessions {
            let hash = StableHash.fnv1a(session.name)
            let base = Int(hash % UInt64(slotCount))
            let slot = findSlot(base: base, slotCount: slotCount, occupied: occupied)
            occupied.insert(slot)

            let row = slot / slotCount
            let col = slot % slotCount
            let origin = CGPoint(
                x: CGFloat(col) * config.slotWidth + config.slotPadding,
                y: config.bottomInset + CGFloat(row) * config.rowHeight
            )
            let paletteIndex = Int(hash % UInt64(config.paletteSize))
            let pose: Pose = session.status == .busy ? .sitting : .sleeping

            let title = session.title.flatMap { $0.isEmpty ? nil : $0 }
            cats.append(CatPlacement(
                id: session.id, origin: origin, scale: 1, pose: pose,
                paletteIndex: paletteIndex, label: session.name,
                animated: pose == .sitting && animationsEnabled, overflowCount: 0,
                bubble: title
            ))

            let shown = session.subagents.prefix(config.maxKittens)
            for (i, sub) in shown.enumerated() {
                let isLast = i == config.maxKittens - 1
                let overflow = isLast ? max(0, session.subagents.count - config.maxKittens) : 0
                cats.append(CatPlacement(
                    id: session.id + "/" + sub.id,
                    origin: CGPoint(
                        x: origin.x + config.catWidth + config.kittenGap + CGFloat(i) * config.kittenStack,
                        y: origin.y + CGFloat(i) * config.kittenStack
                    ),
                    scale: 0.5, pose: .sitting, paletteIndex: paletteIndex,
                    label: nil, animated: animationsEnabled, overflowCount: overflow
                ))
            }
        }
        return Layout(cats: cats)
    }

    /// 같은 줄에서 오른쪽으로 선형 탐사(끝에 닿으면 줄 처음으로 감). 줄이 꽉 차면 다음 줄.
    private static func findSlot(base: Int, slotCount: Int, occupied: Set<Int>) -> Int {
        var row = 0
        while true {
            for k in 0..<slotCount {
                let slot = row * slotCount + (base + k) % slotCount
                if !occupied.contains(slot) { return slot }
            }
            row += 1
        }
    }
}
