import AppKit
import ClaudeCatsCore

enum CatShapes {
    static let boxSize: CGFloat = 64

    static let palette: [NSColor] = [
        NSColor(red: 0.95, green: 0.62, blue: 0.25, alpha: 1),  // 치즈
        NSColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1),  // 검정
        NSColor(red: 0.93, green: 0.92, blue: 0.88, alpha: 1),  // 흰
        NSColor(red: 0.55, green: 0.56, blue: 0.60, alpha: 1),  // 회색
        NSColor(red: 0.60, green: 0.42, blue: 0.28, alpha: 1),  // 갈색
        NSColor(red: 0.86, green: 0.74, blue: 0.55, alpha: 1),  // 크림
        NSColor(red: 0.45, green: 0.38, blue: 0.52, alpha: 1),  // 라일락
        NSColor(red: 0.80, green: 0.50, blue: 0.42, alpha: 1),  // 살구
    ]

    static let eyeColor = NSColor(red: 0.12, green: 0.10, blue: 0.12, alpha: 1)

    /// 좌표계: 64×64, 원점 좌하단(AppKit).
    static func body(_ pose: Pose) -> CGPath {
        let path = CGMutablePath()
        switch pose {
        case .sitting:
            path.addEllipse(in: CGRect(x: 14, y: 4, width: 36, height: 34))          // 몸
            path.addEllipse(in: CGRect(x: 18, y: 30, width: 28, height: 28))         // 머리
            path.move(to: CGPoint(x: 20, y: 50)); path.addLine(to: CGPoint(x: 23, y: 63)); path.addLine(to: CGPoint(x: 30, y: 55)); path.closeSubpath()
            path.move(to: CGPoint(x: 44, y: 50)); path.addLine(to: CGPoint(x: 41, y: 63)); path.addLine(to: CGPoint(x: 34, y: 55)); path.closeSubpath()
        case .sleeping:
            path.addEllipse(in: CGRect(x: 6, y: 4, width: 52, height: 26))           // 웅크린 몸
            path.addEllipse(in: CGRect(x: 34, y: 12, width: 24, height: 24))         // 머리(오른쪽 위)
            path.move(to: CGPoint(x: 38, y: 30)); path.addLine(to: CGPoint(x: 39, y: 40)); path.addLine(to: CGPoint(x: 46, y: 34)); path.closeSubpath()
            path.move(to: CGPoint(x: 56, y: 30)); path.addLine(to: CGPoint(x: 57, y: 40)); path.addLine(to: CGPoint(x: 50, y: 34)); path.closeSubpath()
        }
        return path
    }

    static func eyes(_ pose: Pose) -> CGPath {
        let path = CGMutablePath()
        switch pose {
        case .sitting:
            path.addEllipse(in: CGRect(x: 25, y: 42, width: 4, height: 5))
            path.addEllipse(in: CGRect(x: 35, y: 42, width: 4, height: 5))
        case .sleeping:
            path.move(to: CGPoint(x: 40, y: 23)); path.addLine(to: CGPoint(x: 45, y: 23))
            path.move(to: CGPoint(x: 49, y: 23)); path.addLine(to: CGPoint(x: 54, y: 23))
        }
        return path
    }

    static func tail(_ pose: Pose, frame: Int) -> CGPath {
        let path = CGMutablePath()
        switch pose {
        case .sitting:
            path.move(to: CGPoint(x: 46, y: 10))
            if frame == 0 {
                path.addQuadCurve(to: CGPoint(x: 62, y: 26), control: CGPoint(x: 64, y: 8))
            } else {
                path.addQuadCurve(to: CGPoint(x: 60, y: 6), control: CGPoint(x: 62, y: 20))
            }
        case .sleeping:
            path.move(to: CGPoint(x: 12, y: 10))
            path.addQuadCurve(to: CGPoint(x: 30, y: 6), control: CGPoint(x: 4, y: 0))
        }
        return path
    }
}
