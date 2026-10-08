import Foundation
import Testing
@testable import Compositor

struct LocalizationTests {
    /// Tests compare English titles ("Flip Horizontal"), so they run in English even on a Mac set to Korean, while
    /// the app itself carries Korean.
    @Test func testsRunInEnglishWithKoreanAvailable() {
        #expect(Bundle.main.localizations.contains("ko"))
        #expect(Bundle.main.preferredLocalizations.first == "en")
    }

    @Test func lookupFallsBackToTheEnglishKey() throws {
        let korean = try #require(L10n.koreanBundle)
        #expect(L10n.text("Cancel", bundle: korean) == "취소")
        #expect(L10n.text("Not a key in the catalog", bundle: korean) == "Not a key in the catalog")
        #expect(L10n.text("Cancel") == "Cancel", "tests run in English")
    }

    /// Names are made and checked through one closure, so "레이어 1" is skipped in Korean as "Layer 1" is in English.
    @Test func freeNamesSkipTakenOnesInTheSameLanguage() {
        #expect(L10n.firstFreeName({ "레이어 \($0)" }, avoiding: ["레이어 1", "Layer 2"]) == "레이어 2")
        #expect(L10n.firstFreeName({ "Layer \($0)" }, avoiding: []) == "Layer 1")
    }
}
