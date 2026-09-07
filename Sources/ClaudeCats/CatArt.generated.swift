// GENERATED — edit Design/cats/*.svg and run scripts/generate-cat-art.sh
// 좌표는 64×64 박스, AppKit 방향(y 위로)으로 이미 뒤집혀 있다.
import CoreGraphics
import QuartzCore

/// SVG 의 `#FUR`/`#FURDARK` 플레이스홀더는 런타임 팔레트에서 색을 받는다.
enum CatArtColor: Equatable, Sendable {
    case fur
    case furDark
    case fixed(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
}

/// CGPath 는 불변이라 값처럼 공유해도 안전하다(생성 후 아무도 변형하지 않는다).
struct CatArtLayer: @unchecked Sendable {
    let path: CGPath
    let fill: CatArtColor?
    let stroke: CatArtColor?
    let lineWidth: CGFloat
    let lineCap: CAShapeLayerLineCap
    let opacity: Float
}

enum CatArt {
    static let sittingBody: [CatArtLayer] = [
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 15, y: 20))
                p.addCurve(to: CGPoint(x: 21, y: 34), control1: CGPoint(x: 13, y: 26), control2: CGPoint(x: 15, y: 32))
                p.addCurve(to: CGPoint(x: 32, y: 35), control1: CGPoint(x: 24, y: 36), control2: CGPoint(x: 28, y: 35))
                p.addCurve(to: CGPoint(x: 43, y: 34), control1: CGPoint(x: 36, y: 35), control2: CGPoint(x: 40, y: 36))
                p.addCurve(to: CGPoint(x: 49, y: 20), control1: CGPoint(x: 49, y: 32), control2: CGPoint(x: 51, y: 26))
                p.addCurve(to: CGPoint(x: 48, y: 6), control1: CGPoint(x: 51, y: 16), control2: CGPoint(x: 51, y: 10))
                p.addCurve(to: CGPoint(x: 32, y: 3), control1: CGPoint(x: 46, y: 3), control2: CGPoint(x: 40, y: 3))
                p.addCurve(to: CGPoint(x: 16, y: 6), control1: CGPoint(x: 24, y: 3), control2: CGPoint(x: 18, y: 3))
                p.addCurve(to: CGPoint(x: 15, y: 20), control1: CGPoint(x: 13, y: 10), control2: CGPoint(x: 13, y: 16))
                p.closeSubpath()
                return p
            }(),
            fill: .fur,
            stroke: nil,
            lineWidth: 0,
            lineCap: .butt,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 25, y: 31))
                p.addCurve(to: CGPoint(x: 39, y: 31), control1: CGPoint(x: 28, y: 33), control2: CGPoint(x: 36, y: 33))
                p.addCurve(to: CGPoint(x: 40, y: 7), control1: CGPoint(x: 43, y: 25), control2: CGPoint(x: 43, y: 14))
                p.addCurve(to: CGPoint(x: 24, y: 7), control1: CGPoint(x: 37, y: 5), control2: CGPoint(x: 27, y: 5))
                p.addCurve(to: CGPoint(x: 25, y: 31), control1: CGPoint(x: 21, y: 14), control2: CGPoint(x: 21, y: 25))
                p.closeSubpath()
                p.move(to: CGPoint(x: 17, y: 6))
                p.addCurve(to: CGPoint(x: 25, y: 9), control1: CGPoint(x: 17, y: 9), control2: CGPoint(x: 22, y: 10))
                p.addCurve(to: CGPoint(x: 30, y: 5), control1: CGPoint(x: 28, y: 10), control2: CGPoint(x: 31, y: 8))
                p.addCurve(to: CGPoint(x: 17, y: 6), control1: CGPoint(x: 30, y: 2), control2: CGPoint(x: 18, y: 2))
                p.closeSubpath()
                p.move(to: CGPoint(x: 34, y: 5))
                p.addCurve(to: CGPoint(x: 39, y: 9), control1: CGPoint(x: 33, y: 8), control2: CGPoint(x: 36, y: 10))
                p.addCurve(to: CGPoint(x: 47, y: 6), control1: CGPoint(x: 42, y: 10), control2: CGPoint(x: 47, y: 9))
                p.addCurve(to: CGPoint(x: 34, y: 5), control1: CGPoint(x: 46, y: 2), control2: CGPoint(x: 34, y: 2))
                p.closeSubpath()
                return p
            }(),
            fill: .fixed(r: 0.9529, g: 0.9373, b: 0.9098, a: 1),
            stroke: nil,
            lineWidth: 0,
            lineCap: .butt,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 21.5, y: 3.5))
                p.addLine(to: CGPoint(x: 21.5, y: 2.2))
                p.move(to: CGPoint(x: 24.5, y: 3))
                p.addLine(to: CGPoint(x: 24.5, y: 1.7))
                p.move(to: CGPoint(x: 27.5, y: 3.5))
                p.addLine(to: CGPoint(x: 27.5, y: 2.2))
                p.move(to: CGPoint(x: 36.5, y: 3.5))
                p.addLine(to: CGPoint(x: 36.5, y: 2.2))
                p.move(to: CGPoint(x: 39.5, y: 3))
                p.addLine(to: CGPoint(x: 39.5, y: 1.7))
                p.move(to: CGPoint(x: 42.5, y: 3.5))
                p.addLine(to: CGPoint(x: 42.5, y: 2.2))
                return p
            }(),
            fill: nil,
            stroke: .fixed(r: 0.1333, g: 0.1216, b: 0.1333, a: 1),
            lineWidth: 0.8,
            lineCap: .round,
            opacity: 0.45
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 18, y: 45))
                p.addLine(to: CGPoint(x: 19, y: 61))
                p.addLine(to: CGPoint(x: 30, y: 52))
                p.closeSubpath()
                p.move(to: CGPoint(x: 46, y: 45))
                p.addLine(to: CGPoint(x: 45, y: 61))
                p.addLine(to: CGPoint(x: 34, y: 52))
                p.closeSubpath()
                return p
            }(),
            fill: .fur,
            stroke: nil,
            lineWidth: 0,
            lineCap: .butt,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 20.5, y: 48.5))
                p.addLine(to: CGPoint(x: 21, y: 57))
                p.addLine(to: CGPoint(x: 27.5, y: 51.5))
                p.closeSubpath()
                p.move(to: CGPoint(x: 43.5, y: 48.5))
                p.addLine(to: CGPoint(x: 43, y: 57))
                p.addLine(to: CGPoint(x: 36.5, y: 51.5))
                p.closeSubpath()
                return p
            }(),
            fill: .fixed(r: 0.8863, g: 0.6392, b: 0.6392, a: 1),
            stroke: nil,
            lineWidth: 0,
            lineCap: .butt,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 17, y: 41))
                p.addCurve(to: CGPoint(x: 32, y: 54), control1: CGPoint(x: 17, y: 50), control2: CGPoint(x: 23, y: 54))
                p.addCurve(to: CGPoint(x: 47, y: 41), control1: CGPoint(x: 41, y: 54), control2: CGPoint(x: 47, y: 50))
                p.addCurve(to: CGPoint(x: 40, y: 28), control1: CGPoint(x: 48, y: 35), control2: CGPoint(x: 45, y: 30))
                p.addCurve(to: CGPoint(x: 24, y: 28), control1: CGPoint(x: 36, y: 26), control2: CGPoint(x: 28, y: 26))
                p.addCurve(to: CGPoint(x: 17, y: 41), control1: CGPoint(x: 19, y: 30), control2: CGPoint(x: 16, y: 35))
                p.closeSubpath()
                return p
            }(),
            fill: .fur,
            stroke: nil,
            lineWidth: 0,
            lineCap: .butt,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 32, y: 51.5))
                p.addLine(to: CGPoint(x: 29.5, y: 40.5))
                p.addCurve(to: CGPoint(x: 26, y: 30.5), control1: CGPoint(x: 25.5, y: 39.5), control2: CGPoint(x: 24, y: 35))
                p.addCurve(to: CGPoint(x: 38, y: 30.5), control1: CGPoint(x: 28, y: 27.5), control2: CGPoint(x: 36, y: 27.5))
                p.addCurve(to: CGPoint(x: 34.5, y: 40.5), control1: CGPoint(x: 40, y: 35), control2: CGPoint(x: 38.5, y: 39.5))
                p.closeSubpath()
                return p
            }(),
            fill: .fixed(r: 0.9529, g: 0.9373, b: 0.9098, a: 1),
            stroke: nil,
            lineWidth: 0,
            lineCap: .butt,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 29.4, y: 39.5))
                p.addCurve(to: CGPoint(x: 26, y: 35.7), control1: CGPoint(x: 29.4, y: 37.4013), control2: CGPoint(x: 27.8778, y: 35.7))
                p.addCurve(to: CGPoint(x: 22.6, y: 39.5), control1: CGPoint(x: 24.1222, y: 35.7), control2: CGPoint(x: 22.6, y: 37.4013))
                p.addCurve(to: CGPoint(x: 26, y: 43.3), control1: CGPoint(x: 22.6, y: 41.5987), control2: CGPoint(x: 24.1222, y: 43.3))
                p.addCurve(to: CGPoint(x: 29.4, y: 39.5), control1: CGPoint(x: 27.8778, y: 43.3), control2: CGPoint(x: 29.4, y: 41.5987))
                p.closeSubpath()
                p.move(to: CGPoint(x: 41.4, y: 39.5))
                p.addCurve(to: CGPoint(x: 38, y: 35.7), control1: CGPoint(x: 41.4, y: 37.4013), control2: CGPoint(x: 39.8778, y: 35.7))
                p.addCurve(to: CGPoint(x: 34.6, y: 39.5), control1: CGPoint(x: 36.1222, y: 35.7), control2: CGPoint(x: 34.6, y: 37.4013))
                p.addCurve(to: CGPoint(x: 38, y: 43.3), control1: CGPoint(x: 34.6, y: 41.5987), control2: CGPoint(x: 36.1222, y: 43.3))
                p.addCurve(to: CGPoint(x: 41.4, y: 39.5), control1: CGPoint(x: 39.8778, y: 43.3), control2: CGPoint(x: 41.4, y: 41.5987))
                p.closeSubpath()
                return p
            }(),
            fill: .fixed(r: 0.7882, g: 0.7059, b: 0.3451, a: 1),
            stroke: nil,
            lineWidth: 0,
            lineCap: .butt,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 28.3, y: 39.2))
                p.addCurve(to: CGPoint(x: 26, y: 36.5), control1: CGPoint(x: 28.3, y: 37.7088), control2: CGPoint(x: 27.2703, y: 36.5))
                p.addCurve(to: CGPoint(x: 23.7, y: 39.2), control1: CGPoint(x: 24.7297, y: 36.5), control2: CGPoint(x: 23.7, y: 37.7088))
                p.addCurve(to: CGPoint(x: 26, y: 41.9), control1: CGPoint(x: 23.7, y: 40.6912), control2: CGPoint(x: 24.7297, y: 41.9))
                p.addCurve(to: CGPoint(x: 28.3, y: 39.2), control1: CGPoint(x: 27.2703, y: 41.9), control2: CGPoint(x: 28.3, y: 40.6912))
                p.closeSubpath()
                p.move(to: CGPoint(x: 40.3, y: 39.2))
                p.addCurve(to: CGPoint(x: 38, y: 36.5), control1: CGPoint(x: 40.3, y: 37.7088), control2: CGPoint(x: 39.2703, y: 36.5))
                p.addCurve(to: CGPoint(x: 35.7, y: 39.2), control1: CGPoint(x: 36.7297, y: 36.5), control2: CGPoint(x: 35.7, y: 37.7088))
                p.addCurve(to: CGPoint(x: 38, y: 41.9), control1: CGPoint(x: 35.7, y: 40.6912), control2: CGPoint(x: 36.7297, y: 41.9))
                p.addCurve(to: CGPoint(x: 40.3, y: 39.2), control1: CGPoint(x: 39.2703, y: 41.9), control2: CGPoint(x: 40.3, y: 40.6912))
                p.closeSubpath()
                return p
            }(),
            fill: .fixed(r: 0.1333, g: 0.1216, b: 0.1333, a: 1),
            stroke: nil,
            lineWidth: 0,
            lineCap: .butt,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 28, y: 40.5))
                p.addCurve(to: CGPoint(x: 27, y: 39.5), control1: CGPoint(x: 28, y: 39.9477), control2: CGPoint(x: 27.5523, y: 39.5))
                p.addCurve(to: CGPoint(x: 26, y: 40.5), control1: CGPoint(x: 26.4477, y: 39.5), control2: CGPoint(x: 26, y: 39.9477))
                p.addCurve(to: CGPoint(x: 27, y: 41.5), control1: CGPoint(x: 26, y: 41.0523), control2: CGPoint(x: 26.4477, y: 41.5))
                p.addCurve(to: CGPoint(x: 28, y: 40.5), control1: CGPoint(x: 27.5523, y: 41.5), control2: CGPoint(x: 28, y: 41.0523))
                p.closeSubpath()
                p.move(to: CGPoint(x: 40, y: 40.5))
                p.addCurve(to: CGPoint(x: 39, y: 39.5), control1: CGPoint(x: 40, y: 39.9477), control2: CGPoint(x: 39.5523, y: 39.5))
                p.addCurve(to: CGPoint(x: 38, y: 40.5), control1: CGPoint(x: 38.4477, y: 39.5), control2: CGPoint(x: 38, y: 39.9477))
                p.addCurve(to: CGPoint(x: 39, y: 41.5), control1: CGPoint(x: 38, y: 41.0523), control2: CGPoint(x: 38.4477, y: 41.5))
                p.addCurve(to: CGPoint(x: 40, y: 40.5), control1: CGPoint(x: 39.5523, y: 41.5), control2: CGPoint(x: 40, y: 41.0523))
                p.closeSubpath()
                return p
            }(),
            fill: .fixed(r: 1, g: 1, b: 1, a: 1),
            stroke: nil,
            lineWidth: 0,
            lineCap: .butt,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 30.5, y: 34.5))
                p.addLine(to: CGPoint(x: 33.5, y: 34.5))
                p.addLine(to: CGPoint(x: 32, y: 32.5))
                p.closeSubpath()
                return p
            }(),
            fill: .fixed(r: 0.8392, g: 0.5608, b: 0.5608, a: 1),
            stroke: nil,
            lineWidth: 0,
            lineCap: .butt,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 32, y: 32.5))
                p.addLine(to: CGPoint(x: 32, y: 31))
                p.move(to: CGPoint(x: 32, y: 31))
                p.addCurve(to: CGPoint(x: 28.5, y: 30.5), control1: CGPoint(x: 30.6667, y: 29.6667), control2: CGPoint(x: 29.5, y: 29.5))
                p.move(to: CGPoint(x: 32, y: 31))
                p.addCurve(to: CGPoint(x: 35.5, y: 30.5), control1: CGPoint(x: 33.3333, y: 29.6667), control2: CGPoint(x: 34.5, y: 29.5))
                return p
            }(),
            fill: nil,
            stroke: .fixed(r: 0.1333, g: 0.1216, b: 0.1333, a: 1),
            lineWidth: 0.8,
            lineCap: .round,
            opacity: 0.7
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 28, y: 33))
                p.addLine(to: CGPoint(x: 18, y: 35))
                p.move(to: CGPoint(x: 28, y: 31.5))
                p.addLine(to: CGPoint(x: 17, y: 31))
                p.move(to: CGPoint(x: 36, y: 33))
                p.addLine(to: CGPoint(x: 46, y: 35))
                p.move(to: CGPoint(x: 36, y: 31.5))
                p.addLine(to: CGPoint(x: 47, y: 31))
                return p
            }(),
            fill: nil,
            stroke: .fixed(r: 0.9098, g: 0.8941, b: 0.8627, a: 1),
            lineWidth: 0.7,
            lineCap: .round,
            opacity: 0.85
        ),
    ]

    static let sittingTailA: [CatArtLayer] = [
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 49, y: 14))
                p.addCurve(to: CGPoint(x: 60, y: 32), control1: CGPoint(x: 59, y: 15.3333), control2: CGPoint(x: 62.6667, y: 21.3333))
                return p
            }(),
            fill: nil,
            stroke: .fur,
            lineWidth: 6.5,
            lineCap: .round,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 60.5, y: 29))
                p.addLine(to: CGPoint(x: 60, y: 32.5))
                return p
            }(),
            fill: nil,
            stroke: .furDark,
            lineWidth: 6,
            lineCap: .round,
            opacity: 1
        ),
    ]

    static let sittingTailB: [CatArtLayer] = [
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 49, y: 14))
                p.addCurve(to: CGPoint(x: 62, y: 2), control1: CGPoint(x: 59, y: 11.3333), control2: CGPoint(x: 63.3333, y: 7.3333))
                return p
            }(),
            fill: nil,
            stroke: .fur,
            lineWidth: 6.5,
            lineCap: .round,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 62, y: 5.5))
                p.addLine(to: CGPoint(x: 62, y: 2))
                return p
            }(),
            fill: nil,
            stroke: .furDark,
            lineWidth: 6,
            lineCap: .round,
            opacity: 1
        ),
    ]

    static let sleepingBody: [CatArtLayer] = [
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 14, y: 14))
                p.addCurve(to: CGPoint(x: 30, y: 35), control1: CGPoint(x: 10, y: 22), control2: CGPoint(x: 16, y: 32))
                p.addCurve(to: CGPoint(x: 60, y: 20), control1: CGPoint(x: 44, y: 38), control2: CGPoint(x: 58, y: 32))
                p.addCurve(to: CGPoint(x: 42, y: 6), control1: CGPoint(x: 61, y: 12), control2: CGPoint(x: 54, y: 6))
                p.addLine(to: CGPoint(x: 22, y: 6))
                p.addCurve(to: CGPoint(x: 14, y: 14), control1: CGPoint(x: 17, y: 7), control2: CGPoint(x: 15, y: 10))
                p.closeSubpath()
                return p
            }(),
            fill: .fur,
            stroke: nil,
            lineWidth: 0,
            lineCap: .butt,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 18, y: 16))
                p.addCurve(to: CGPoint(x: 34, y: 18), control1: CGPoint(x: 20, y: 20), control2: CGPoint(x: 28, y: 21))
                p.addCurve(to: CGPoint(x: 30, y: 7), control1: CGPoint(x: 36, y: 14), control2: CGPoint(x: 34, y: 8))
                p.addLine(to: CGPoint(x: 22, y: 7))
                p.addCurve(to: CGPoint(x: 18, y: 16), control1: CGPoint(x: 18, y: 8), control2: CGPoint(x: 17, y: 12))
                p.closeSubpath()
                return p
            }(),
            fill: .fixed(r: 0.9529, g: 0.9373, b: 0.9098, a: 1),
            stroke: nil,
            lineWidth: 0,
            lineCap: .butt,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 58, y: 18))
                p.addCurve(to: CGPoint(x: 40, y: 2), control1: CGPoint(x: 62, y: 8), control2: CGPoint(x: 52, y: 1.5))
                p.addLine(to: CGPoint(x: 27, y: 2.5))
                return p
            }(),
            fill: nil,
            stroke: .fur,
            lineWidth: 6.5,
            lineCap: .round,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 31, y: 2.4))
                p.addLine(to: CGPoint(x: 27, y: 2.5))
                return p
            }(),
            fill: nil,
            stroke: .furDark,
            lineWidth: 6,
            lineCap: .round,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 22, y: 9))
                p.addCurve(to: CGPoint(x: 30, y: 11), control1: CGPoint(x: 22, y: 12), control2: CGPoint(x: 27, y: 12))
                p.addCurve(to: CGPoint(x: 34, y: 7), control1: CGPoint(x: 33, y: 12), control2: CGPoint(x: 35, y: 10))
                p.addCurve(to: CGPoint(x: 22, y: 9), control1: CGPoint(x: 33, y: 5), control2: CGPoint(x: 23, y: 5))
                p.closeSubpath()
                return p
            }(),
            fill: .fixed(r: 0.9529, g: 0.9373, b: 0.9098, a: 1),
            stroke: nil,
            lineWidth: 0,
            lineCap: .butt,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 25.5, y: 6.5))
                p.addLine(to: CGPoint(x: 25.5, y: 5.3))
                p.move(to: CGPoint(x: 28, y: 6))
                p.addLine(to: CGPoint(x: 28, y: 4.8))
                p.move(to: CGPoint(x: 30.5, y: 6.5))
                p.addLine(to: CGPoint(x: 30.5, y: 5.3))
                return p
            }(),
            fill: nil,
            stroke: .fixed(r: 0.1333, g: 0.1216, b: 0.1333, a: 1),
            lineWidth: 0.7,
            lineCap: .round,
            opacity: 0.4
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 11, y: 29))
                p.addLine(to: CGPoint(x: 10, y: 40))
                p.addLine(to: CGPoint(x: 19, y: 34))
                p.closeSubpath()
                p.move(to: CGPoint(x: 22, y: 33))
                p.addLine(to: CGPoint(x: 26, y: 43))
                p.addLine(to: CGPoint(x: 30, y: 34))
                p.closeSubpath()
                return p
            }(),
            fill: .fur,
            stroke: nil,
            lineWidth: 0,
            lineCap: .butt,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 12.5, y: 31))
                p.addLine(to: CGPoint(x: 12.5, y: 37))
                p.addLine(to: CGPoint(x: 17.5, y: 33.5))
                p.closeSubpath()
                p.move(to: CGPoint(x: 23.5, y: 34.5))
                p.addLine(to: CGPoint(x: 26, y: 39.5))
                p.addLine(to: CGPoint(x: 28.5, y: 34.5))
                p.closeSubpath()
                return p
            }(),
            fill: .fixed(r: 0.8863, g: 0.6392, b: 0.6392, a: 1),
            stroke: nil,
            lineWidth: 0,
            lineCap: .butt,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 7, y: 22))
                p.addCurve(to: CGPoint(x: 20, y: 34), control1: CGPoint(x: 7, y: 30), control2: CGPoint(x: 12, y: 34))
                p.addCurve(to: CGPoint(x: 32, y: 22), control1: CGPoint(x: 28, y: 34), control2: CGPoint(x: 33, y: 29))
                p.addCurve(to: CGPoint(x: 19, y: 13), control1: CGPoint(x: 31, y: 16), control2: CGPoint(x: 26, y: 13))
                p.addCurve(to: CGPoint(x: 7, y: 22), control1: CGPoint(x: 12, y: 13), control2: CGPoint(x: 7, y: 16))
                p.closeSubpath()
                return p
            }(),
            fill: .fur,
            stroke: nil,
            lineWidth: 0,
            lineCap: .butt,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 10, y: 20))
                p.addCurve(to: CGPoint(x: 21, y: 23), control1: CGPoint(x: 11, y: 24), control2: CGPoint(x: 17, y: 25))
                p.addCurve(to: CGPoint(x: 18, y: 14), control1: CGPoint(x: 23, y: 20), control2: CGPoint(x: 22, y: 15))
                p.addCurve(to: CGPoint(x: 10, y: 20), control1: CGPoint(x: 13, y: 14), control2: CGPoint(x: 10, y: 16))
                p.closeSubpath()
                return p
            }(),
            fill: .fixed(r: 0.9529, g: 0.9373, b: 0.9098, a: 1),
            stroke: nil,
            lineWidth: 0,
            lineCap: .butt,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 12, y: 24))
                p.addCurve(to: CGPoint(x: 17, y: 24), control1: CGPoint(x: 13.6667, y: 22.8), control2: CGPoint(x: 15.3333, y: 22.8))
                p.move(to: CGPoint(x: 20, y: 25))
                p.addCurve(to: CGPoint(x: 25, y: 25), control1: CGPoint(x: 21.6667, y: 23.8), control2: CGPoint(x: 23.3333, y: 23.8))
                return p
            }(),
            fill: nil,
            stroke: .fixed(r: 0.1333, g: 0.1216, b: 0.1333, a: 1),
            lineWidth: 1,
            lineCap: .round,
            opacity: 0.8
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 13, y: 19.5))
                p.addLine(to: CGPoint(x: 16, y: 19.5))
                p.addLine(to: CGPoint(x: 14.5, y: 17.7))
                p.closeSubpath()
                return p
            }(),
            fill: .fixed(r: 0.8392, g: 0.5608, b: 0.5608, a: 1),
            stroke: nil,
            lineWidth: 0,
            lineCap: .butt,
            opacity: 1
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 14.5, y: 17.7))
                p.addCurve(to: CGPoint(x: 11.5, y: 17.2), control1: CGPoint(x: 13.5, y: 16.7), control2: CGPoint(x: 12.5, y: 16.5333))
                return p
            }(),
            fill: nil,
            stroke: .fixed(r: 0.1333, g: 0.1216, b: 0.1333, a: 1),
            lineWidth: 0.7,
            lineCap: .round,
            opacity: 0.6
        ),
        CatArtLayer(
            path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 11, y: 18))
                p.addLine(to: CGPoint(x: 4, y: 19))
                p.move(to: CGPoint(x: 11, y: 16.5))
                p.addLine(to: CGPoint(x: 4, y: 15))
                return p
            }(),
            fill: nil,
            stroke: .fixed(r: 0.9098, g: 0.8941, b: 0.8627, a: 1),
            lineWidth: 0.7,
            lineCap: .round,
            opacity: 0.85
        ),
    ]
}
