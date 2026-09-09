import CoreGraphics
import Testing
@testable import ClaudeCatsCore

@Suite struct LayoutInsetsTests {
    private let base: CGFloat = 40   // SceneConfig().bottomInset

    /// 주 디스플레이 1800x1169, 하단 Dock 70pt.
    @Test func bottomDockAddsItsHeight() {
        let frame = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let visible = CGRect(x: 0, y: 70, width: 1800, height: 1074)   // 위는 메뉴바가 먹었다
        #expect(LayoutInsets.bottomInset(frame: frame, visibleFrame: visible, base: base) == 110)
    }

    /// Dock 이 좌·우에 있으면 minY 가 같다 — 기본 여백만 남는다.
    @Test func sideDockKeepsBaseInset() {
        let frame = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let left = CGRect(x: 80, y: 0, width: 1720, height: 1144)
        let right = CGRect(x: 0, y: 0, width: 1720, height: 1144)
        #expect(LayoutInsets.bottomInset(frame: frame, visibleFrame: left, base: base) == 40)
        #expect(LayoutInsets.bottomInset(frame: frame, visibleFrame: right, base: base) == 40)
    }

    /// Dock 자동 숨김 → visibleFrame 바닥이 frame 바닥과 같아진다.
    @Test func hiddenDockKeepsBaseInset() {
        let frame = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let visible = CGRect(x: 0, y: 0, width: 1800, height: 1144)
        #expect(LayoutInsets.bottomInset(frame: frame, visibleFrame: visible, base: base) == 40)
    }

    /// 보조 디스플레이는 origin 이 0 이 아니다 — 절대 좌표가 아니라 차이만 센다.
    @Test func secondaryScreenUsesRelativeOffset() {
        let frame = CGRect(x: 1800, y: -400, width: 2560, height: 1440)
        let visible = CGRect(x: 1800, y: -330, width: 2560, height: 1345)
        #expect(LayoutInsets.bottomInset(frame: frame, visibleFrame: visible, base: base) == 110)
    }

    /// visibleFrame 바닥이 frame 바닥보다 아래인 이상한 조합에서도 음수가 되지 않는다.
    @Test func visibleFrameBelowFrameNeverGoesNegative() {
        let frame = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let visible = CGRect(x: 0, y: -50, width: 1800, height: 1169)
        #expect(LayoutInsets.bottomInset(frame: frame, visibleFrame: visible, base: base) == 40)
    }

    @Test func negativeBaseIsClampedToZero() {
        let frame = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let visible = CGRect(x: 0, y: 70, width: 1800, height: 1074)
        #expect(LayoutInsets.bottomInset(frame: frame, visibleFrame: visible, base: -10) == 70)
    }

    /// Scene 이 이 값을 그대로 쓰므로, 기본 여백은 SceneConfig 와 같아야 한다.
    @Test func baseMatchesSceneConfigDefault() {
        #expect(SceneConfig().bottomInset == base)
    }
}
