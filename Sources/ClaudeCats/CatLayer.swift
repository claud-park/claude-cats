import AppKit
import ClaudeCatsCore

/// 고양이 한 마리. 서브레이어: 꼬리 2장(몸 뒤) → 몸 → 눈 → 라벨 → 배지.
/// 모든 프로퍼티 변경은 호출자가 CATransaction 액션을 끈 상태에서 한다.
/// 메인 스레드에서만 사용한다 (DesktopWindow 가 유일한 호출자)
final class CatLayer: CALayer {
    private(set) var placement: CatPlacement
    private let tailA = CAShapeLayer()
    private let tailB = CAShapeLayer()
    private let bodyLayer = CAShapeLayer()
    private let eyesLayer = CAShapeLayer()
    private let labelLayer = CATextLayer()
    private let badgeLayer = CATextLayer()
    private var tailToggle = false

    init(placement: CatPlacement, contentsScale: CGFloat) {
        self.placement = placement
        super.init()
        anchorPoint = .zero
        bounds = CGRect(x: 0, y: 0, width: CatShapes.boxSize, height: CatShapes.boxSize)
        self.contentsScale = contentsScale

        for tail in [tailA, tailB] {
            tail.fillColor = nil
            tail.lineWidth = 6
            tail.lineCap = .round
            tail.contentsScale = contentsScale
        }
        eyesLayer.lineWidth = 2
        eyesLayer.lineCap = .round
        eyesLayer.contentsScale = contentsScale
        bodyLayer.contentsScale = contentsScale

        labelLayer.frame = CGRect(x: -38, y: -18, width: 140, height: 16)
        labelLayer.alignmentMode = .center
        labelLayer.contentsScale = contentsScale
        labelLayer.isWrapped = false
        labelLayer.truncationMode = .end

        badgeLayer.frame = CGRect(x: 40, y: 48, width: 40, height: 16)
        badgeLayer.alignmentMode = .left
        badgeLayer.contentsScale = contentsScale

        [tailA, tailB, bodyLayer, eyesLayer, labelLayer, badgeLayer].forEach(addSublayer)
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

    func apply(_ p: CatPlacement) {
        placement = p
        position = p.origin
        transform = CATransform3DMakeScale(p.scale, p.scale, 1)

        let color = CatShapes.palette[p.paletteIndex % CatShapes.palette.count].cgColor
        bodyLayer.path = CatShapes.body(p.pose)
        bodyLayer.fillColor = color

        eyesLayer.path = CatShapes.eyes(p.pose)
        eyesLayer.fillColor = p.pose == .sitting ? CatShapes.eyeColor.cgColor : nil
        eyesLayer.strokeColor = p.pose == .sleeping ? CatShapes.eyeColor.cgColor : nil

        tailA.path = CatShapes.tail(p.pose, frame: 0)
        tailB.path = CatShapes.tail(p.pose, frame: 1)
        tailA.strokeColor = color
        tailB.strokeColor = color
        tailToggle = false
        tailA.isHidden = false
        tailB.isHidden = true

        labelLayer.string = p.label.map { Self.outlinedLabel($0, maxWidth: labelLayer.bounds.width) }
        labelLayer.isHidden = p.label == nil

        badgeLayer.string = p.overflowCount > 0
            ? Self.outlinedLabel("+\(p.overflowCount)", maxWidth: badgeLayer.bounds.width)
            : nil
        badgeLayer.isHidden = p.overflowCount == 0
    }

    func tickTail() {
        guard placement.pose == .sitting else { return }
        tailToggle.toggle()
        tailA.isHidden = tailToggle
        tailB.isHidden = !tailToggle
    }

    /// 흰 글자 + 검은 외곽선(배경 박스 없음). 음수 strokeWidth = fill + stroke.
    ///
    /// CATextLayer 는 truncationMode 를 .end 로 둬도 폭을 넘는 attributed string 을
    /// 아예 그리지 않는다(음수 strokeWidth 조합에서 재현: 렌더 픽셀 0). 그래서
    /// 레이어에 맡기지 않고 문자열을 직접 잘라서 넘긴다.
    private static func outlinedLabel(_ text: String, maxWidth: CGFloat) -> NSAttributedString {
        var result = attributedLabel(text)
        guard result.size().width > maxWidth else { return result }
        var chars = Array(text)
        while chars.count > 1 {
            chars.removeLast()
            result = attributedLabel(String(chars) + "…")
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
