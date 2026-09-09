import Foundation

/// 어떤 고양이 그림(고양이 종류)을 그릴지. 메뉴바의 `고양이 종류` 하위 메뉴가 고르고
/// `UserDefaults` 의 `catConcept` 에 raw value 로 저장된다.
///
/// 내부 식별자(rawValue)와 사용자 표시 이름(title)은 다르다 — 소스·생성 파일·저장값을
/// 갈아엎지 않으려고 내부 이름은 그대로 둔다:
///   - `team`  = **푹신캣** (기본. 8색 팔레트로 세션마다 색이 달라지는, 색을 바꿀 수 있는 고양이)
///   - `kenji` = **동글캣** (특정한 회색 스코티시폴드풍 고양이. 색이 고정이라 모두 같게 보인다)
public enum CatConcept: String, CaseIterable, Sendable {
    /// 기본 팀 고양이(푹신캣). 팔레트로 색을 입힌다(`CatArtSet.recolorable == true`).
    case team
    /// 켄지(동글캣). 색이 고정이고 꼬리 프레임이 없어 꼬리를 흔들지 않는다.
    case kenji

    /// 메뉴·UI 에 보이는 이름. 내부 식별자와 달리 사용자용 표기다.
    public var title: String {
        switch self {
        case .team: "푹신캣"
        case .kenji: "동글캣"
        }
    }

    /// 저장값 → 선택. 키가 없거나 모르는 값이면 기본값(`.team` = 푹신캣).
    public static func stored(_ rawValue: String?) -> CatConcept {
        rawValue.flatMap(CatConcept.init(rawValue:)) ?? .team
    }

    /// 메뉴 표시용 항목들. 정확히 하나가 선택된다(선언 순서를 지킨다).
    public static func menuEntries(
        selected: CatConcept
    ) -> [(title: String, concept: CatConcept, isSelected: Bool)] {
        allCases.map { (title: $0.title, concept: $0, isSelected: $0 == selected) }
    }
}
