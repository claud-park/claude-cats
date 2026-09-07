import AppKit
import ClaudeCatsCore

/// 지금 연결된 디스플레이 목록을 코어의 `DisplayInfo` 로 바꿔주는 단 하나의 지점.
/// 창(DesktopWindow)과 메뉴(StatusMenu)가 같은 목록·같은 순서를 보게 하려고 공유한다.
enum DisplayCatalog {
    /// 스펙의 "메인 디스플레이" = 원점을 포함한 주 디스플레이(`screens.first`).
    /// `NSScreen.main` 은 키보드 포커스가 있는 화면이라 다르다 — 포커스 따라 고양이가 옮겨다닌다.
    @MainActor
    static func current() -> [DisplayInfo] {
        NSScreen.screens.enumerated().map { index, screen in
            DisplayInfo(name: screen.localizedName, isMain: index == 0)
        }
    }
}
