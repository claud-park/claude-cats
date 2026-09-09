// GENERATED — edit Design/cats/*.svg and run scripts/generate-cat-art.sh
// 여기에는 타입과 컨셉별 아트 묶음(CatArtSet)만 있다. 컨셉·포즈별 도형은
// CatArt.<컨셉>.<포즈>.generated.swift 로 나뉜다(그림 하나만 고쳐도 그 파일만 다시 컴파일되게 — issue #4).
import ClaudeCatsCore
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

/// 한 컨셉(고양이 종류)의 네 포즈 아트. `recolorable` 이 false 면 팔레트 색을 입히지 않는다
/// (켄지/동글캣처럼 색이 고정인 고양이). 꼬리 프레임이 없는 컨셉은 Tail 배열이 비고
/// `sittingTailAboveBody` 가 false 다.
struct CatArtSet: Sendable {
    let sittingBody: [CatArtLayer]
    let sittingTailA: [CatArtLayer]
    let sittingTailB: [CatArtLayer]
    let sleepingBody: [CatArtLayer]
    let alertBody: [CatArtLayer]
    let alertTailA: [CatArtLayer]
    let alertTailB: [CatArtLayer]
    let sittingTop: CGFloat
    let sleepingTop: CGFloat
    let alertTop: CGFloat
    let sittingTailAboveBody: Bool
    let alertTailAboveBody: Bool
    let recolorable: Bool
}

enum CatArt {
    static let team = CatArtSet(
        sittingBody: teamSittingBody,
        sittingTailA: teamSittingTailA,
        sittingTailB: teamSittingTailB,
        sleepingBody: teamSleepingBody,
        alertBody: teamAlertBody,
        alertTailA: teamAlertTailA,
        alertTailB: teamAlertTailB,
        sittingTop: teamSittingTop,
        sleepingTop: teamSleepingTop,
        alertTop: teamAlertTop,
        sittingTailAboveBody: teamSittingTailAboveBody,
        alertTailAboveBody: teamAlertTailAboveBody,
        recolorable: true
    )

    static let kenji = CatArtSet(
        sittingBody: kenjiSittingBody,
        sittingTailA: [],
        sittingTailB: [],
        sleepingBody: kenjiSleepingBody,
        alertBody: kenjiSittingBody,
        alertTailA: [],
        alertTailB: [],
        sittingTop: kenjiSittingTop,
        sleepingTop: kenjiSleepingTop,
        alertTop: kenjiSittingTop,
        sittingTailAboveBody: false,
        alertTailAboveBody: false,
        recolorable: true
    )

    static let monggle = CatArtSet(
        sittingBody: monggleSittingBody,
        sittingTailA: [],
        sittingTailB: [],
        sleepingBody: monggleSleepingBody,
        alertBody: monggleSittingBody,
        alertTailA: [],
        alertTailB: [],
        sittingTop: monggleSittingTop,
        sleepingTop: monggleSleepingTop,
        alertTop: monggleSittingTop,
        sittingTailAboveBody: false,
        alertTailAboveBody: false,
        recolorable: true
    )

    /// 고양이 종류에 맞는 아트 묶음. 메뉴바 `고양이 종류` 선택이 이 값을 고른다.
    static func set(_ concept: CatConcept) -> CatArtSet {
        switch concept {
        case .team: return team
        case .kenji: return kenji
        case .monggle: return monggle
        }
    }
}
