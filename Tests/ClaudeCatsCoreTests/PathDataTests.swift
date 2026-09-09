import CoreGraphics
import Testing
@testable import ClaudeCatsCore

/// 생성된 아트가 싣는 `[명령코드, 좌표...]` 배열 → CGPath 디코더.
/// 온전한 입력은 정확히 펴야 하고, 망가진 입력에서는 크래시 없이 멈춰야 한다.
@Suite struct PathDataTests {
    /// CGPath 를 비교하기 좋은 문자열 목록으로 편다.
    private func elements(_ path: CGPath) -> [String] {
        // applyWithBlock 의 블록은 escaping 취급이라 지역 var 을 못 잡는다. 상자에 담는다.
        final class Sink { var items: [String] = [] }
        let sink = Sink()
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            func point(_ index: Int) -> String {
                let value = element.points[index]
                return "\(value.x) \(value.y)"
            }
            switch element.type {
            case .moveToPoint: sink.items.append("M \(point(0))")
            case .addLineToPoint: sink.items.append("L \(point(0))")
            case .addQuadCurveToPoint: sink.items.append("Q \(point(0)) \(point(1))")
            case .addCurveToPoint: sink.items.append("C \(point(0)) \(point(1)) \(point(2))")
            case .closeSubpath: sink.items.append("Z")
            @unknown default: sink.items.append("?")
            }
        }
        return sink.items
    }

    @Test func buildsAClosedSquare() {
        let path = PathData.build([0, 0, 0, 1, 10, 0, 1, 10, 10, 1, 0, 10, 3])
        #expect(elements(path) == ["M 0.0 0.0", "L 10.0 0.0", "L 10.0 10.0", "L 0.0 10.0", "Z"])
        #expect(path.boundingBox == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test func buildsACubicWithControlPointsInOrder() {
        // 인코딩 순서는 제어점1, 제어점2, 끝점이다.
        let path = PathData.build([0, 0, 0, 2, 0, 8, 8, 8, 8, 0])
        #expect(elements(path) == ["M 0.0 0.0", "C 0.0 8.0 8.0 8.0 8.0 0.0"])
    }

    @Test func closeStartsANewSubpathForTheNextMove() {
        let path = PathData.build([0, 0, 0, 1, 4, 0, 3, 0, 8, 8, 1, 12, 8])
        #expect(elements(path) == ["M 0.0 0.0", "L 4.0 0.0", "Z", "M 8.0 8.0", "L 12.0 8.0"])
    }

    @Test func emptyDataGivesAnEmptyPath() {
        #expect(PathData.build([]).isEmpty)
    }

    /// 잘린 배열: 마지막 cubic 이 좌표 6개를 못 채우면 거기서 멈춘다.
    @Test func truncatedCubicStopsCleanly() {
        let path = PathData.build([0, 0, 0, 1, 10, 0, 2, 1, 1, 2])
        #expect(elements(path) == ["M 0.0 0.0", "L 10.0 0.0"])
    }

    /// 잘린 배열: move 가 좌표 2개를 못 채워도 마찬가지다.
    @Test func truncatedMoveStopsCleanly() {
        let path = PathData.build([0, 0, 0, 1, 10, 0, 0, 5])
        #expect(elements(path) == ["M 0.0 0.0", "L 10.0 0.0"])
    }

    @Test func unknownOpcodeStopsCleanly() {
        let path = PathData.build([0, 0, 0, 9, 1, 5, 5])
        #expect(elements(path) == ["M 0.0 0.0"])
    }

    /// 시작점 없이 선부터 나오는 배열도 CoreGraphics 를 건드리지 않고 멈춘다.
    @Test func lineBeforeAnyMoveStopsCleanly() {
        #expect(PathData.build([1, 5, 5]).isEmpty)
        #expect(PathData.build([2, 1, 1, 2, 2, 3, 3]).isEmpty)
        #expect(PathData.build([3]).isEmpty)
    }

    /// NaN 이 명령코드 자리에 오면 어떤 case 와도 같지 않다 — 거기서 멈추되,
    /// 그전까지 그린 경로는 살아 있어야 한다.
    @Test func nanOpcodeStopsWithoutLosingWhatCameBefore() {
        let path = PathData.build([0, 0, 0, Float.nan, 1, 1])
        #expect(!path.isEmpty)
        #expect(elements(path) == ["M 0.0 0.0"])
    }

    /// 좌표 자리의 NaN 은 CoreGraphics 가 알아서 삼킨다. 크래시만 안 나면 된다.
    @Test func nanCoordinateDoesNotCrash() {
        let path = PathData.build([0, 0, 0, 1, Float.nan, 4, 1, 8, 8])
        #expect(!path.isEmpty)
    }

    /// 실제로 커밋된 생성물 조각(`CatArt.sleeping.generated.swift` 의 `sleepingBody7`).
    /// 생성기가 내보내는 형식이 바뀌면 여기서 걸린다.
    @Test func decodesARealGeneratedArray() {
        let sleepingBody7: [Float] = [
            0, 18.69, 14.34,
            1, 18.21, 14.02,
            2, 16.67, 12.99, 14.85, 12.44, 13, 12.44,
            0, 23.8, 17.38,
            2, 25.58, 17.8, 27.1, 18.96, 27.97, 20.58,
            1, 28.19, 20.99,
        ]
        let path = PathData.build(sleepingBody7)
        #expect(elements(path).count == 6)          // 서브패스 2개, 명령 6개
        #expect(elements(path).filter { $0.hasPrefix("M") }.count == 2)

        let box = path.boundingBox
        func rounded(_ value: CGFloat) -> CGFloat { (value * 100).rounded() / 100 }
        #expect(rounded(box.minX) == 13.00)
        #expect(rounded(box.minY) == 12.44)
        #expect(rounded(box.maxX) == 28.19)
        #expect(rounded(box.maxY) == 20.99)
    }
}
