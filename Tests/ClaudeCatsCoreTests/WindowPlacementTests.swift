import Testing
@testable import ClaudeCatsCore

@Suite struct WindowPlacementTests {
    @Test func rawValuesAreStableStorageKeys() {
        #expect(WindowPlacement.desktop.rawValue == "desktop")
        #expect(WindowPlacement.aboveIcons.rawValue == "aboveIcons")
        #expect(WindowPlacement.alwaysOnTop.rawValue == "alwaysOnTop")
        #expect(WindowPlacement.allCases.count == 3)
    }

    @Test func titlesAreDistinct() {
        let titles = WindowPlacement.allCases.map(\.title)
        #expect(titles == ["바탕화면 (아이콘 아래)", "창 아래 (아이콘 위)", "항상 위"])
        #expect(Set(titles).count == 3)
    }

    @Test func levelOffsets() {
        #expect(WindowPlacement.desktop.levelOffset == .desktopIcon(offset: -1))
        #expect(WindowPlacement.aboveIcons.levelOffset == .desktopIcon(offset: 1))
        #expect(WindowPlacement.alwaysOnTop.levelOffset == .floating)
    }

    /// 아이콘 아래 < 아이콘 레벨 < 아이콘 위. 오프셋 부호가 뒤집히면 여기서 걸린다.
    @Test func desktopIsBelowAboveIcons() {
        guard case let .desktopIcon(below) = WindowPlacement.desktop.levelOffset,
              case let .desktopIcon(above) = WindowPlacement.aboveIcons.levelOffset else {
            Issue.record("두 항목 모두 바탕화면 아이콘 기준이어야 한다")
            return
        }
        #expect(below < 0)
        #expect(above > 0)
        #expect(below < above)
    }

    // MARK: - stored

    @Test func missingOrUnknownValueFallsBackToDesktop() {
        #expect(WindowPlacement.stored(nil) == .desktop)
        #expect(WindowPlacement.stored("") == .desktop)
        #expect(WindowPlacement.stored("하늘 위") == .desktop)
    }

    @Test func storedRoundTripsEveryCase() {
        for placement in WindowPlacement.allCases {
            #expect(WindowPlacement.stored(placement.rawValue) == placement)
        }
    }

    // MARK: - menuEntries

    @Test func menuEntriesMarkExactlyOne() {
        for placement in WindowPlacement.allCases {
            let entries = WindowPlacement.menuEntries(selected: placement)
            #expect(entries.count == 3)
            #expect(entries.filter(\.isSelected).count == 1)
            #expect(entries.first(where: \.isSelected)?.placement == placement)
        }
    }

    @Test func menuEntriesKeepDeclarationOrder() {
        let entries = WindowPlacement.menuEntries(selected: .desktop)
        #expect(entries.map(\.placement) == WindowPlacement.allCases)
        #expect(entries.map(\.title) == WindowPlacement.allCases.map(\.title))
    }
}
