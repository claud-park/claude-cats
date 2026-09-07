import AppKit
import ClaudeCatsCore

/// 고양이 한 마리. 서브레이어: 꼬리 2프레임(몸 뒤) → 몸 → 라벨 → 배지 → 말풍선.
/// 몸·꼬리는 `CatArt`(Design/cats/*.svg 에서 생성) 의 도형 목록을 CAShapeLayer 로 펼친 것이다.
/// 모든 프로퍼티 변경은 호출자가 CATransaction 액션을 끈 상태에서 한다.
/// 메인 스레드에서만 사용한다 (DesktopWindow 가 유일한 호출자)
final class CatLayer: CALayer {
    private(set) var placement: CatPlacement
    /// 아트 레이어를 담는 그릇. 포즈가 바뀌면 안을 비우고 다시 채운다.
    private let tailA = CALayer()
    private let tailB = CALayer()
    private let bodyLayer = CALayer()
    private let labelLayer = CATextLayer()
    private let badgeLayer = CATextLayer()
    /// 머리 위 말풍선. 정적이다 — bubble 문자열이 바뀔 때만 path·문자열을 다시 만든다.
    private let bubbleLayer = CAShapeLayer()
    private let bubbleTextLayer = CATextLayer()
    /// 팔레트가 바뀌면 색만 갈아끼울 자리들(경로는 그대로 둔다).
    private var furSlots: [(layer: CAShapeLayer, isStroke: Bool)] = []
    private var furDarkSlots: [(layer: CAShapeLayer, isStroke: Bool)] = []
    private var tailToggle = false
    /// 최초 apply 는 모든 서브레이어를 채워야 한다. 이후로는 바뀐 것만 건드린다.
    private var hasApplied = false

    init(placement: CatPlacement, contentsScale: CGFloat) {
        self.placement = placement
        super.init()
        anchorPoint = .zero
        bounds = CGRect(x: 0, y: 0, width: CatShapes.boxSize, height: CatShapes.boxSize)
        self.contentsScale = contentsScale

        labelLayer.frame = CGRect(x: -38, y: -18, width: 140, height: 16)
        labelLayer.alignmentMode = .center
        labelLayer.contentsScale = contentsScale
        labelLayer.isWrapped = false
        labelLayer.truncationMode = .end

        // 배지는 새끼(scale 0.5)에만 붙는다. 왼쪽 가운데를 기준으로 역보정 확대한다.
        badgeLayer.anchorPoint = CGPoint(x: 0, y: 0.5)
        badgeLayer.frame = CGRect(x: 40, y: 48, width: 40, height: 16)
        badgeLayer.alignmentMode = .left
        badgeLayer.contentsScale = contentsScale

        // 말풍선은 고양이 상자와 같은 좌표계에서 그린다(경로 좌표 = 고양이 좌표).
        bubbleLayer.anchorPoint = .zero
        bubbleLayer.bounds = bounds
        bubbleLayer.position = .zero
        bubbleLayer.fillColor = NSColor.white.withAlphaComponent(0.95).cgColor
        bubbleLayer.strokeColor = nil
        bubbleLayer.contentsScale = contentsScale

        bubbleTextLayer.alignmentMode = .center
        bubbleTextLayer.isWrapped = false
        bubbleTextLayer.truncationMode = .end
        bubbleTextLayer.contentsScale = contentsScale

        [tailA, tailB, bodyLayer, labelLayer, badgeLayer, bubbleLayer, bubbleTextLayer].forEach(addSublayer)
        apply(placement)
    }

    override init(layer: Any) {
        // presentation layer 복사용. 우리는 애니메이션 프로퍼티를 쓰지 않으므로 원본 값 복사만.
        let other = layer as! CatLayer
        self.placement = other.placement
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// 바뀐 프로퍼티만 다시 쓴다. 도형 생성과 문자열 조판이 제일 비싸므로
    /// pose / paletteIndex / label / overflowCount 가 실제로 달라졌을 때만 손댄다.
    func apply(_ p: CatPlacement) {
        let previous = placement
        let first = !hasApplied
        hasApplied = true
        placement = p

        // 위치·크기는 매번 싼 값 대입이라 조건 없이 쓴다.
        position = p.origin
        transform = CATransform3DMakeScale(p.scale, p.scale, 1)
        // 새끼는 0.5 배로 줄어드니 배지만 역보정해 11pt 로 보이게 한다.
        let inverse = p.scale > 0 ? 1 / p.scale : 1
        badgeLayer.transform = CATransform3DMakeScale(inverse, inverse, 1)

        let poseChanged = first || p.pose != previous.pose
        let colorChanged = first || p.paletteIndex != previous.paletteIndex

        if poseChanged {
            rebuildArt(for: p.pose)
        }

        if colorChanged || poseChanged {
            let colors = CatShapes.palette[p.paletteIndex % CatShapes.palette.count]
            paint(furSlots, with: colors.fur.cgColor)
            paint(furDarkSlots, with: colors.furDark.cgColor)
        }

        if first || p.label != previous.label {
            labelLayer.string = p.label.map { Self.outlinedLabel($0, maxWidth: labelLayer.bounds.width) }
            labelLayer.isHidden = p.label == nil
        }

        if first || p.overflowCount != previous.overflowCount {
            badgeLayer.string = p.overflowCount > 0
                ? Self.outlinedLabel("+\(p.overflowCount)", maxWidth: badgeLayer.bounds.width)
                : nil
            badgeLayer.isHidden = p.overflowCount == 0
        }

        if first || p.bubble != previous.bubble {
            applyBubble(p.bubble)
        }
    }

    /// 디스플레이 backing scale 이 바뀌면 자신과 모든 하위 레이어에 새 스케일을 내린다.
    func setContentsScale(_ scale: CGFloat) {
        guard contentsScale != scale else { return }
        contentsScale = scale
        Self.setContentsScale(scale, on: sublayers)
    }

    private static func setContentsScale(_ scale: CGFloat, on layers: [CALayer]?) {
        for layer in layers ?? [] {
            layer.contentsScale = scale
            setContentsScale(scale, on: layer.sublayers)
        }
    }

    func tickTail() {
        guard placement.pose == .sitting else { return }
        tailToggle.toggle()
        tailA.isHidden = tailToggle
        tailB.isHidden = !tailToggle
    }

    // MARK: - 아트 구성

    /// 포즈 변경은 드물다. 그때만 몸·꼬리 서브레이어를 통째로 다시 만든다.
    private func rebuildArt(for pose: Pose) {
        for container in [bodyLayer, tailA, tailB] {
            container.sublayers?.forEach { $0.removeFromSuperlayer() }
        }
        furSlots.removeAll()
        furDarkSlots.removeAll()

        switch pose {
        case .sitting:
            build(CatArt.sittingBody, into: bodyLayer)
            build(CatArt.sittingTailA, into: tailA)
            build(CatArt.sittingTailB, into: tailB)
            tailA.isHidden = false
            tailB.isHidden = true
        case .sleeping:
            // idle 은 꼬리가 몸에 붙은 정지 그림이라 프레임 레이어를 쓰지 않는다.
            build(CatArt.sleepingBody, into: bodyLayer)
            tailA.isHidden = true
            tailB.isHidden = true
        }
        tailToggle = false
    }

    private func build(_ art: [CatArtLayer], into container: CALayer) {
        for piece in art {
            let shape = CAShapeLayer()
            shape.path = piece.path
            shape.lineWidth = piece.lineWidth
            shape.lineCap = piece.lineCap
            shape.lineJoin = .round
            shape.opacity = piece.opacity
            shape.contentsScale = contentsScale
            shape.fillColor = resolve(piece.fill, on: shape, isStroke: false)
            shape.strokeColor = resolve(piece.stroke, on: shape, isStroke: true)
            container.addSublayer(shape)
        }
    }

    /// 고정색은 지금 정하고, 팔레트 색은 자리만 기억해 뒀다가 apply 에서 칠한다.
    private func resolve(_ color: CatArtColor?, on shape: CAShapeLayer, isStroke: Bool) -> CGColor? {
        switch color {
        case .none:
            return nil
        case .fixed(let r, let g, let b, let a):
            return CGColor(srgbRed: r, green: g, blue: b, alpha: a)
        case .fur:
            furSlots.append((shape, isStroke))
            return nil
        case .furDark:
            furDarkSlots.append((shape, isStroke))
            return nil
        }
    }

    private func paint(_ slots: [(layer: CAShapeLayer, isStroke: Bool)], with color: CGColor) {
        for slot in slots {
            if slot.isStroke {
                slot.layer.strokeColor = color
            } else {
                slot.layer.fillColor = color
            }
        }
    }

    // MARK: - 말풍선

    /// 고양이 좌표계 기준 치수. 폭 최대 130 은 슬롯 폭 140 보다 좁아 이웃과 겹치지 않는다.
    private enum Bubble {
        static let centerX: CGFloat = 32
        static let tipY: CGFloat = 66      // 아래 꼭지 끝(머리 바로 위)
        static let notch: CGFloat = 5      // 꼭지 높이
        static let height: CGFloat = 18
        static let maxWidth: CGFloat = 130
        static let padding: CGFloat = 16   // 좌우 합계
        static let corner: CGFloat = 6
        static let fontSize: CGFloat = 10
    }

    private func applyBubble(_ text: String?) {
        guard let text else {
            bubbleLayer.isHidden = true
            bubbleTextLayer.isHidden = true
            bubbleTextLayer.string = nil
            bubbleLayer.path = nil
            return
        }
        let attributed = Self.fitted(text, maxWidth: Bubble.maxWidth - Bubble.padding, Self.attributedBubble)
        let width = min(Bubble.maxWidth, ceil(attributed.size().width) + Bubble.padding)
        let bottom = Bubble.tipY + Bubble.notch

        bubbleLayer.path = Self.bubblePath(width: width)
        bubbleTextLayer.string = attributed
        bubbleTextLayer.frame = CGRect(
            x: Bubble.centerX - width / 2 + Bubble.padding / 2,
            y: bottom + 1,
            width: width - Bubble.padding,
            height: 14
        )
        bubbleLayer.isHidden = false
        bubbleTextLayer.isHidden = false
    }

    /// 둥근 사각형 + 아래로 뻗은 삼각 꼭지를 한 경로에 담는다.
    /// 꼭지 밑변을 사각형 안쪽으로 0.5 겹쳐 이음매가 보이지 않게 한다.
    private static func bubblePath(width: CGFloat) -> CGPath {
        let bottom = Bubble.tipY + Bubble.notch
        let rect = CGRect(x: Bubble.centerX - width / 2, y: bottom, width: width, height: Bubble.height)
        let path = CGMutablePath()
        path.addRoundedRect(in: rect, cornerWidth: Bubble.corner, cornerHeight: Bubble.corner)
        path.move(to: CGPoint(x: Bubble.centerX - 5, y: bottom + 0.5))
        path.addLine(to: CGPoint(x: Bubble.centerX, y: Bubble.tipY))
        path.addLine(to: CGPoint(x: Bubble.centerX + 5, y: bottom + 0.5))
        path.closeSubpath()
        return path
    }

    private static func attributedBubble(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: Bubble.fontSize),
            .foregroundColor: NSColor(srgbRed: 0x22 / 255, green: 0x1F / 255, blue: 0x22 / 255, alpha: 1),
        ])
    }

    // MARK: - 라벨

    /// 흰 글자 + 검은 외곽선(배경 박스 없음). 음수 strokeWidth = fill + stroke.
    private static func outlinedLabel(_ text: String, maxWidth: CGFloat) -> NSAttributedString {
        fitted(text, maxWidth: maxWidth, attributedLabel)
    }

    /// CATextLayer 는 truncationMode 를 .end 로 둬도 폭을 넘는 attributed string 을
    /// 아예 그리지 않는다(음수 strokeWidth 조합에서 재현: 렌더 픽셀 0). 그래서
    /// 레이어에 맡기지 않고 문자열을 직접 잘라서 넘긴다.
    private static func fitted(
        _ text: String, maxWidth: CGFloat, _ make: (String) -> NSAttributedString
    ) -> NSAttributedString {
        var result = make(text)
        guard result.size().width > maxWidth else { return result }
        var chars = Array(text)
        while chars.count > 1 {
            chars.removeLast()
            result = make(String(chars) + "…")
            if result.size().width <= maxWidth { break }
        }
        return result
    }

    private static func attributedLabel(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black.withAlphaComponent(0.85),
            .strokeWidth: -3,
        ])
    }
}
