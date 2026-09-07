import Testing
@testable import ClaudeCatsCore

@Suite struct DisplaySelectionTests {
    private let builtIn = DisplayInfo(name: "Built-in Retina Display", isMain: true)
    private let external = DisplayInfo(name: "DELL U2720Q", isMain: false)

    private var two: [DisplayInfo] { [builtIn, external] }

    // MARK: - resolve

    @Test func nilPreferenceUsesMain() {
        #expect(DisplaySelection.resolve(preferredName: nil, available: two) == builtIn)
    }

    @Test func matchingNameUsesThatDisplay() {
        #expect(DisplaySelection.resolve(preferredName: "DELL U2720Q", available: two) == external)
    }

    @Test func missingNameFallsBackToMain() {
        let resolved = DisplaySelection.resolve(preferredName: "사라진 모니터", available: two)
        #expect(resolved == builtIn)
        #expect(resolved != nil)
    }

    @Test func emptyAvailableIsNil() {
        #expect(DisplaySelection.resolve(preferredName: nil, available: []) == nil)
        #expect(DisplaySelection.resolve(preferredName: "DELL U2720Q", available: []) == nil)
    }

    @Test func noMainFlagFallsBackToFirst() {
        let list = [external, DisplayInfo(name: "LG HDR 4K", isMain: false)]
        #expect(DisplaySelection.resolve(preferredName: nil, available: list) == external)
    }

    @Test func duplicateNamesPickTheFirst() {
        let list = [
            builtIn,
            DisplayInfo(name: "LG HDR 4K", isMain: false),
            DisplayInfo(name: "LG HDR 4K", isMain: false),
        ]
        let resolved = DisplaySelection.resolve(preferredName: "LG HDR 4K", available: list)
        #expect(resolved == list[1])
    }

    // MARK: - menuEntries

    @Test func entriesStartWithAutomatic() {
        let entries = DisplaySelection.menuEntries(preferredName: nil, available: two)
        #expect(entries.count == 3)
        #expect(entries[0].title == "자동 (메인 디스플레이)")
        #expect(entries[0].name == nil)
        #expect(entries[0].isSelected)
        #expect(entries[1].name == "Built-in Retina Display")
        #expect(entries[2].name == "DELL U2720Q")
        #expect(entries.filter(\.isSelected).count == 1)
    }

    @Test func entriesMarkTheChosenDisplay() {
        let entries = DisplaySelection.menuEntries(preferredName: "DELL U2720Q", available: two)
        #expect(entries.count == 3)
        #expect(!entries[0].isSelected)
        #expect(entries[2].isSelected)
        #expect(entries.filter(\.isSelected).count == 1)
    }

    @Test func disconnectedPreferenceGetsExtraEntry() {
        let entries = DisplaySelection.menuEntries(preferredName: "사라진 모니터", available: two)
        #expect(entries.count == 4)
        #expect(entries[3].title == "사라진 모니터 (연결 안 됨)")
        #expect(entries[3].name == "사라진 모니터")
        #expect(entries[3].isSelected)
        #expect(!entries[0].isSelected)
        #expect(entries.filter(\.isSelected).count == 1)
    }

    @Test func emptyAvailableStillHasAutomatic() {
        let auto = DisplaySelection.menuEntries(preferredName: nil, available: [])
        #expect(auto.count == 1)
        #expect(auto[0].isSelected)

        let stale = DisplaySelection.menuEntries(preferredName: "사라진 모니터", available: [])
        #expect(stale.count == 2)
        #expect(stale[1].title == "사라진 모니터 (연결 안 됨)")
        #expect(stale.filter(\.isSelected).count == 1)
    }

    @Test func duplicateNamesSelectOnlyOneEntry() {
        let list = [
            builtIn,
            DisplayInfo(name: "LG HDR 4K", isMain: false),
            DisplayInfo(name: "LG HDR 4K", isMain: false),
        ]
        let entries = DisplaySelection.menuEntries(preferredName: "LG HDR 4K", available: list)
        #expect(entries.count == 4)
        #expect(entries[2].isSelected)
        #expect(!entries[3].isSelected)
        #expect(entries.filter(\.isSelected).count == 1)
    }
}
