import Foundation

/// Text whose English is known only at run time, such as an enum's stored raw value or a shortcut's title, looked up
/// in the string catalog. The compiler can't extract these keys, so they're added to the catalog by hand
/// (`scripts/l10n.py manual`), and `ManualKeys` lists them so a test can check each has Korean.
nonisolated enum L10n {
    /// The translation of `english` in `bundle`'s current language, or `english` itself when there's none.
    static func text(_ english: String, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: english, value: english, table: nil)
    }

    /// The Korean translations, for tests that check the catalog while the app runs in English.
    static var koreanBundle: Bundle? {
        Bundle.main.path(forResource: "ko", ofType: "lproj").flatMap(Bundle.init(path:))
    }

    /// "Layer 1", "Layer 2", …: the first `name(n)` not in `taken`. Making and checking a name through the same closure
    /// keeps both in one language.
    static func firstFreeName(_ name: (Int) -> String, avoiding taken: Set<String>) -> String {
        var number = 1
        while taken.contains(name(number)) { number += 1 }
        return name(number)
    }
}

/// An enum the screen shows by name. Its raw value is English and stored in project files, so it's never translated
/// itself; `displayName` is what the screen shows.
nonisolated protocol LocalizedDisplayName: RawRepresentable, CaseIterable where RawValue == String {
    /// Every raw value, for the catalog check.
    static var displayKeys: [String] { get }
}

nonisolated extension LocalizedDisplayName {
    var displayName: String { L10n.text(rawValue) }
    /// The display name as a catalog resource, for names taken as `LocalizedStringResource` (undo names).
    var displayResource: LocalizedStringResource { LocalizedStringResource(String.LocalizationValue(rawValue)) }
    static var displayKeys: [String] { allCases.map(\.rawValue) }
}
