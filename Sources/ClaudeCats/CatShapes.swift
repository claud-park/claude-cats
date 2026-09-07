import AppKit

/// 고양이 아트의 상자 크기와 털색 팔레트. 도형 자체는 `CatArt.generated.swift` 에 있다
/// (Design/cats/*.svg → scripts/generate-cat-art.sh).
enum CatShapes {
    static let boxSize: CGFloat = 64

    /// 세션마다 하나씩 고르는 털색. `fur` 는 몸통, `furDark` 는 꼬리 끝 그림자.
    /// 인덱스는 `paletteIndex % palette.count`.
    static let palette: [(fur: NSColor, furDark: NSColor)] = [
        (fur(0.55, 0.50, 0.44), fur(0.39, 0.35, 0.30)),   // 회갈색 태비
        (fur(0.36, 0.37, 0.40), fur(0.25, 0.26, 0.29)),   // 진회색
        (fur(0.87, 0.53, 0.22), fur(0.68, 0.38, 0.13)),   // 치즈 태비
        (fur(0.18, 0.18, 0.20), fur(0.10, 0.10, 0.12)),   // 검정
        (fur(0.51, 0.36, 0.25), fur(0.36, 0.25, 0.17)),   // 갈색
        (fur(0.85, 0.78, 0.66), fur(0.68, 0.60, 0.48)),   // 크림
        (fur(0.55, 0.60, 0.66), fur(0.39, 0.44, 0.50)),   // 블루그레이
        (fur(0.80, 0.55, 0.47), fur(0.62, 0.39, 0.32)),   // 진저로즈
    ]

    private static func fur(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
