import CoreGraphics

/// 창은 화면 전체(`frame`)를 덮되, 고양이는 Dock 에 가리지 않는 영역(`visibleFrame`)
/// 위에 놓는다. 그 "바닥에서 얼마나 띄울지"를 계산하는 순수 로직.
///
/// 창을 `visibleFrame` 으로 줄이지 않는 이유는 이 창이 **바탕화면 레이어**이기 때문이다 —
/// 화면 전체를 덮고 있어야 좌표계가 흔들리지 않고, Dock 이 숨겨졌다 나타나도 창을
/// 다시 잡을 필요가 없다. 대신 배치만 Dock 높이만큼 올린다.
public enum LayoutInsets {
    /// Dock 이 먹은 화면 아래쪽 높이 + `base`(기본 여백).
    ///
    /// - `visibleFrame.minY` 가 `frame.minY` 보다 위에 있을 때만(= 하단 Dock) 그 차이를 더한다.
    ///   Dock 이 좌·우에 있거나 숨겨져 있으면 두 값이 같아 `base` 그대로다.
    /// - 메뉴바는 `maxY` 쪽이라 여기 영향을 주지 않는다.
    /// - 어떤 좌표 조합에서도 음수가 되지 않는다(보조 디스플레이의 음수 origin 포함).
    public static func bottomInset(frame: CGRect, visibleFrame: CGRect, base: CGFloat) -> CGFloat {
        let occluded = max(0, visibleFrame.minY - frame.minY)
        return occluded + max(0, base)
    }
}
