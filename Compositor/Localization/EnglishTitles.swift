import Foundation

/// The English behind translated menu titles, so the command palette finds "필터 › 가우시안 흐림 효과…" by "blur" too.
nonisolated struct EnglishTitles {
    /// Translation → every English key with that translation ("축소" is both Zoom Out and Contract), sorted.
    private let english: [String: [String]]

    /// From `bundle`'s `Localizable.strings` in its current language; empty when the app runs in English.
    init(bundle: Bundle = .main) {
        guard let language = bundle.preferredLocalizations.first, language != "en",
              let path = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil,
                                     forLocalization: language),
              let table = NSDictionary(contentsOfFile: path) as? [String: String] else {
            self.init(table: [:])
            return
        }
        self.init(table: table)
    }

    /// `table` maps English keys to translations, as a `.strings` file does.
    init(table: [String: String]) {
        var english: [String: [String]] = [:]
        for key in table.keys.sorted() {
            guard let value = table[key], value != key else { continue }
            english[value, default: []].append(key)
        }
        self.english = english
    }

    /// One title in English: as it is, or without the trailing "…" a format such as "%@…" added. A translation
    /// several English keys share gives all of them ("Contract / Zoom Out"), since this is only searched, never shown.
    func english(for title: String) -> String? {
        if let keys = english[title] { return keys.joined(separator: " / ") }
        if title.hasSuffix("…"), let keys = english[String(title.dropLast())] {
            return keys.map { $0 + "…" }.joined(separator: " / ")
        }
        return nil
    }

    /// A menu path in English, part by part, keeping parts that have no English; nil when no part has any.
    func english(forPath titles: [String]) -> String? {
        let parts = titles.map(english(for:))
        guard parts.contains(where: { $0 != nil }) else { return nil }
        return zip(titles, parts).map { $1 ?? $0 }.joined(separator: " › ")
    }
}
