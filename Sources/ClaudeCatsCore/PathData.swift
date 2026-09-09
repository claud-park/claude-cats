import CoreGraphics

/// 생성된 고양이 아트의 경로를 **코드가 아니라 데이터**로 싣기 위한 디코더.
///
/// `scripts/svg2swift.py` 는 경로 하나를 `[명령코드, 좌표...]` 가 이어 붙은 평평한
/// `[Float]` 로 내보내고, 여기서 한 번 `CGMutablePath` 로 편다. `p.addCurve(...)`
/// 문장 수천 개를 컴파일하는 대신 숫자 리터럴만 컴파일하게 되어 빌드가 크게 빨라진다.
///
/// | 코드 | 명령 | 뒤따르는 좌표 |
/// | --- | --- | --- |
/// | 0 | move | x, y |
/// | 1 | line | x, y |
/// | 2 | cubic | c1x, c1y, c2x, c2y, x, y |
/// | 3 | close | (없음) |
///
/// 좌표는 이미 64×64 상자·AppKit 방향(y 위로)이다. `Float` 로 충분하다 —
/// 값 범위가 0~64 이고 정밀도는 소수 2자리라, 2x 화면에서도 오차가 픽셀 아래다.
public enum PathData {
    public static let opMove: Float = 0
    public static let opLine: Float = 1
    public static let opCubic: Float = 2
    public static let opClose: Float = 3

    /// 인코딩된 경로 → `CGPath`. 배열이 중간에 잘렸거나, 모르는 명령코드가 나오거나,
    /// move 없이 line·cubic·close 가 먼저 나오면 그 자리에서 **조용히 멈춘다**
    /// (크래시 없이 거기까지 그린 경로를 돌려준다).
    /// 생성물은 항상 온전하므로, 이 관용은 손상된 입력에 대한 안전장치일 뿐이다.
    public static func build(_ d: [Float]) -> CGPath {
        let path = CGMutablePath()
        var i = 0
        let end = d.count
        while i < end {
            switch d[i] {
            case opMove:
                guard i + 2 < end else { return path }
                path.move(to: CGPoint(x: CGFloat(d[i + 1]), y: CGFloat(d[i + 2])))
                i += 3
            case opLine:
                guard i + 2 < end, !path.isEmpty else { return path }
                path.addLine(to: CGPoint(x: CGFloat(d[i + 1]), y: CGFloat(d[i + 2])))
                i += 3
            case opCubic:
                guard i + 6 < end, !path.isEmpty else { return path }
                path.addCurve(
                    to: CGPoint(x: CGFloat(d[i + 5]), y: CGFloat(d[i + 6])),
                    control1: CGPoint(x: CGFloat(d[i + 1]), y: CGFloat(d[i + 2])),
                    control2: CGPoint(x: CGFloat(d[i + 3]), y: CGFloat(d[i + 4]))
                )
                i += 7
            case opClose:
                guard !path.isEmpty else { return path }
                path.closeSubpath()
                i += 1
            default:
                return path
            }
        }
        return path
    }
}
