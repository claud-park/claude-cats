import Foundation
import CoreGraphics

public enum Pose: Sendable, Equatable {
    case sitting
    case sleeping
    /// 사용자 입력을 기다리는 중(권한 요청 등). 꼬리는 앉은 자세처럼 흔든다.
    case alert
}

/// 말풍선 색. 제목은 흰 바탕, 알림은 노란 바탕이다.
public enum BubbleStyle: Sendable, Equatable {
    case title
    case alert
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
    /// 머리 위 말풍선 문구(세션 제목 또는 알림). 새끼와 둘 다 없는 세션은 nil.
    public var bubble: String?
    public var bubbleStyle: BubbleStyle

    public init(id: String, origin: CGPoint, scale: CGFloat, pose: Pose, paletteIndex: Int,
                label: String?, animated: Bool, overflowCount: Int, bubble: String? = nil,
                bubbleStyle: BubbleStyle = .title) {
        self.id = id
        self.origin = origin
        self.scale = scale
        self.pose = pose
        self.paletteIndex = paletteIndex
        self.label = label
        self.animated = animated
        self.overflowCount = overflowCount
        self.bubble = bubble
        self.bubbleStyle = bubbleStyle
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
            // paletteSize 0 이면 % 가 트랩한다. 설정 실수로 앱이 죽지는 않게 한다.
            let paletteIndex = Int(hash % UInt64(max(1, config.paletteSize)))
            // 알림이 있으면 상태보다 알림이 먼저다 — 기다리는 고양이는 자지 않는다.
            let pose: Pose = session.alert != nil
                ? .alert
                : (session.status == .busy ? .sitting : .sleeping)

            let title = session.title.flatMap { $0.isEmpty ? nil : $0 }
            let bubble = session.alert.map(alertBubble) ?? title
            cats.append(CatPlacement(
                id: session.id, origin: origin, scale: 1, pose: pose,
                paletteIndex: paletteIndex, label: session.name,
                animated: pose != .sleeping && animationsEnabled, overflowCount: 0,
                bubble: bubble,
                bubbleStyle: session.alert != nil ? .alert : .title
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

    /// 알림 말풍선 문구. 권한 요청은 무엇을 하려는지가 제일 궁금하므로 메시지 앞부분을 붙인다.
    /// Claude 가 붙이는 영어 접두어("Claude needs your permission to ")는 벗기고 24자만 쓴다.
    static func alertBubble(_ alert: Alert) -> String {
        switch alert.kind {
        case .permission:
            // 뒤 공백은 먼저 잘라 두므로 접두어도 공백 없는 형태로 비교한다.
            let prefix = "Claude needs your permission to"
            var text = alert.message.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? "권한 요청 중" : "권한 요청: " + String(text.prefix(24))
        case .idle:
            return "입력 기다리는 중"
        case .agentNeedsInput:
            return "에이전트 입력 대기"
        }
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
