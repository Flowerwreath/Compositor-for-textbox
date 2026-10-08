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
}
