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

    /// Keyboard Shortcuts shows its English ids translated; every one needs Korean.
    @MainActor @Test func everyShortcutNameHasKorean() throws {
        let korean = try #require(L10n.koreanBundle)
        let missing = ManualKeys.shortcutNames.filter { L10n.text($0, bundle: korean) == $0 }
        #expect(missing.isEmpty, "add with scripts/l10n.py manual, then translate: \(missing)")
    }

    /// Canvas Size keeps its fill choices in English as tags; the picker shows them translated.
    @MainActor @Test func everyCanvasFillChoiceHasKorean() throws {
        let korean = try #require(L10n.koreanBundle)
        let missing = ManualKeys.canvasExtensionChoices.filter { L10n.text($0, bundle: korean) == $0 }
        #expect(missing.isEmpty, "add with scripts/l10n.py manual, then translate: \(missing)")
    }

    /// The save panel's format menu and Finder's Kind column show the document types' names.
    @Test func documentTypeNamesHaveKorean() throws {
        let korean = try #require(L10n.koreanBundle)
        let name = korean.localizedString(forKey: "Compositor Project", value: nil, table: "InfoPlist")
        #expect(name != "Compositor Project")
    }
}
