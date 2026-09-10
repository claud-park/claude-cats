import Testing
@testable import ClaudeCatsCore

@Suite struct CatConceptTests {
    @Test func rawValuesAreStableStorageKeys() {
        // rawValue 는 UserDefaults 저장값·소스/생성 파일 이름과 묶여 있다 — 바꾸면 안 된다.
        #expect(CatConcept.team.rawValue == "team")
        #expect(CatConcept.kenji.rawValue == "kenji")
        #expect(CatConcept.monggle.rawValue == "monggle")
        #expect(CatConcept.pparit.rawValue == "pparit")
        #expect(CatConcept.allCases.count == 4)
    }

    @Test func titlesAreTheUserFacingNames() {
        // 내부 식별자(team/kenji/monggle/pparit)와 다른, 메뉴·UI 표기.
        #expect(CatConcept.team.title == "푹신캣")
        #expect(CatConcept.kenji.title == "동글캣")
        #expect(CatConcept.monggle.title == "몽글개")
        #expect(CatConcept.pparit.title == "빠릿개")
        #expect(Set(CatConcept.allCases.map(\.title)).count == 4)
    }

    // MARK: - stored

    @Test func missingOrUnknownValueFallsBackToTeam() {
        #expect(CatConcept.stored(nil) == .team)
        #expect(CatConcept.stored("") == .team)
        #expect(CatConcept.stored("동글") == .team)
    }

    @Test func storedRoundTripsEveryCase() {
        for concept in CatConcept.allCases {
            #expect(CatConcept.stored(concept.rawValue) == concept)
        }
    }

    // MARK: - menuEntries

    @Test func menuEntriesMarkExactlyOne() {
        for concept in CatConcept.allCases {
            let entries = CatConcept.menuEntries(selected: concept)
            #expect(entries.count == 4)
            #expect(entries.filter(\.isSelected).count == 1)
            #expect(entries.first(where: \.isSelected)?.concept == concept)
        }
    }

    @Test func menuEntriesKeepDeclarationOrder() {
        let entries = CatConcept.menuEntries(selected: .team)
        #expect(entries.map(\.concept) == CatConcept.allCases)
        #expect(entries.map(\.title) == CatConcept.allCases.map(\.title))
    }
}
