import AppKit

/// 고양이 아트의 상자 크기와 털색 팔레트. 도형 자체는 `CatArt.<포즈>.generated.swift` 에 있다
/// (Design/cats/*.svg → scripts/generate-cat-art.sh).
enum CatShapes {
    static let boxSize: CGFloat = 64

    /// 세션마다 하나씩 고르는 털색 3쌍. `fur` 는 몸통, `furDark` 는 그림자(귀 안쪽·목덜미),
    /// `furLight` 는 하이라이트다. 인덱스는 `paletteIndex % palette.count`.
    ///
    /// 0번은 원본 그림의 색 그대로다 — 그 세 색의 정본은 `scripts/generate-cat-art.sh` 의
    /// `FUR` / `FUR_DARK` / `FUR_LIGHT` 이고, 임포터가 그 값을 플레이스홀더로 바꾼다.
    /// 나머지 7쌍은 0번의 명도 관계를 유지한다 — 어두운 색은 약 15% 어둡게(×0.815),
    /// 밝은 색은 흰색 쪽으로 약 27% 끌어올린다.
    static let palette: [(fur: NSColor, furDark: NSColor, furLight: NSColor)] = [
        // 원본 갈회색 (generate-cat-art.sh 의 FUR 3종)
        (fur(0.490, 0.424, 0.384), fur(0.400, 0.345, 0.310), fur(0.627, 0.565, 0.518)),
        // 진회색
        (fur(0.360, 0.370, 0.400), fur(0.293, 0.302, 0.326), fur(0.533, 0.540, 0.562)),
        // 치즈 태비
        (fur(0.870, 0.530, 0.220), fur(0.709, 0.432, 0.179), fur(0.905, 0.657, 0.431)),
        // 검정
        (fur(0.180, 0.180, 0.200), fur(0.147, 0.147, 0.163), fur(0.401, 0.401, 0.416)),
        // 크림
        (fur(0.850, 0.780, 0.660), fur(0.693, 0.636, 0.538), fur(0.891, 0.839, 0.752)),
        // 블루그레이
        (fur(0.550, 0.600, 0.660), fur(0.448, 0.489, 0.538), fur(0.672, 0.708, 0.752)),
        // 진저
        (fur(0.800, 0.550, 0.470), fur(0.652, 0.448, 0.383), fur(0.854, 0.671, 0.613)),
        // 다크 초콜릿
        (fur(0.350, 0.260, 0.210), fur(0.285, 0.212, 0.171), fur(0.526, 0.460, 0.423)),
    ]

    private static func fur(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
