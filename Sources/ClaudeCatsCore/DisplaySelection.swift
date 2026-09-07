import Foundation

/// 한 대의 디스플레이. AppKit 의존 없이 이름과 "메인 여부"만 들고 온다.
public struct DisplayInfo: Equatable, Sendable {
    public let name: String
    public let isMain: Bool

    public init(name: String, isMain: Bool) {
        self.name = name
        self.isMain = isMain
    }
}

/// 고양이를 어느 디스플레이에 그릴지 고르는 순수 로직.
/// 한 번에 한 화면만 쓴다 — 선택은 "이름" 하나로 저장된다(디스플레이 ID 는 재부팅·재연결로 바뀐다).
public enum DisplaySelection {
    /// preferredName == nil → 메인. 이름이 일치하는 디스플레이가 있으면 그것, 없으면 메인(폴백).
    /// 같은 이름이 여러 개면 첫 번째를 쓴다. 연결된 디스플레이가 없으면 nil.
    public static func resolve(preferredName: String?, available: [DisplayInfo]) -> DisplayInfo? {
        guard !available.isEmpty else { return nil }
        let main = available.first(where: \.isMain) ?? available[0]
        guard let preferredName else { return main }
        return available.first { $0.name == preferredName } ?? main
    }

    /// 메뉴 표시용 항목들. 첫 항목은 항상 "자동 (메인 디스플레이)"(name == nil).
    /// 선택한 이름이 연결돼 있지 않으면 목록 끝에 "<name> (연결 안 됨)" 을 selected 로 덧붙인다.
    /// 어떤 경우에도 selected 는 정확히 하나다.
    public static func menuEntries(
        preferredName: String?,
        available: [DisplayInfo]
    ) -> [(title: String, name: String?, isSelected: Bool)] {
        var entries: [(title: String, name: String?, isSelected: Bool)] = [
            (title: "자동 (메인 디스플레이)", name: nil, isSelected: preferredName == nil)
        ]

        var matched = false
        for display in available {
            // 같은 이름이 둘 이상이면 resolve 와 같이 첫 번째만 체크한다.
            let isSelected = !matched && display.name == preferredName
            if isSelected { matched = true }
            entries.append((title: display.name, name: display.name, isSelected: isSelected))
        }

        if let preferredName, !matched {
            entries.append((title: "\(preferredName) (연결 안 됨)", name: preferredName, isSelected: true))
        }
        return entries
    }
}
