// GENERATED — edit Design/cats/*.svg and run scripts/generate-cat-art.sh
// 여기에는 타입과 별칭만 있다. 포즈별 도형은 CatArt.<포즈>.generated.swift 로 나뉜다
// (그림 한 포즈만 고쳐도 그 파일만 다시 컴파일되게 — issue #4).
import CoreGraphics
import QuartzCore

/// SVG 의 `#FUR`/`#FURDARK`/`#FURLIGHT` 플레이스홀더는 런타임 팔레트에서 색을 받는다.
enum CatArtColor: Equatable, Sendable {
    case fur
    case furDark
    case furLight
    case fixed(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
}

/// CGPath 는 불변이라 값처럼 공유해도 안전하다(생성 후 아무도 변형하지 않는다).
struct CatArtLayer: @unchecked Sendable {
    let path: CGPath
    let fill: CatArtColor?
    let stroke: CatArtColor?
    let lineWidth: CGFloat
    let lineCap: CAShapeLayerLineCap
    let lineJoin: CAShapeLayerLineJoin
    let fillRule: CAShapeLayerFillRule
    let opacity: Float
}

enum CatArt {
}
