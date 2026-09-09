import Foundation

/// 창 레벨을 AppKit 없이 기술한다. 실제 `NSWindow.Level` 매핑은 앱 타깃(`DesktopWindow`)에 있다.
public enum WindowLevelOffset: Equatable, Sendable {
    /// 바탕화면 아이콘 레벨(`CGWindowLevelForKey(.desktopIconWindow)`) 기준 상대값.
    case desktopIcon(offset: Int)
    /// 일반 앱 창보다 위(`NSWindow.Level.floating`).
    case floating
}

/// 고양이 창을 어느 높이에 둘지. 메뉴바의 `표시 위치` 하위 메뉴가 고르고
/// `UserDefaults` 의 `windowPlacement` 에 raw value 로 저장된다.
public enum WindowPlacement: String, CaseIterable, Sendable {
    /// 바탕화면 위 · 아이콘 아래(기본값). 창을 다 치워야 보인다.
    case desktop
    /// 바탕화면 아이콘 위 · 모든 앱 창 아래. 아이콘에 가리지 않는다.
    case aboveIcons
    /// 일반 창보다 위. 클릭은 통과한다(`ignoresMouseEvents`).
    case alwaysOnTop

    public var title: String {
        switch self {
        case .desktop: "바탕화면 (아이콘 아래)"
        case .aboveIcons: "창 아래 (아이콘 위)"
        case .alwaysOnTop: "항상 위"
        }
    }

    public var levelOffset: WindowLevelOffset {
        switch self {
        case .desktop: .desktopIcon(offset: -1)
        case .aboveIcons: .desktopIcon(offset: 1)
        case .alwaysOnTop: .floating
        }
    }

    /// 저장값 → 선택. 키가 없거나 모르는 값이면 기본값(`.desktop`).
    public static func stored(_ rawValue: String?) -> WindowPlacement {
        rawValue.flatMap(WindowPlacement.init(rawValue:)) ?? .desktop
    }

    /// 메뉴 표시용 항목들. 정확히 하나가 선택된다.
    public static func menuEntries(
        selected: WindowPlacement
    ) -> [(title: String, placement: WindowPlacement, isSelected: Bool)] {
        allCases.map { (title: $0.title, placement: $0, isSelected: $0 == selected) }
    }
}
