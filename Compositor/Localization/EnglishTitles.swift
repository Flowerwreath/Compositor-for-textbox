import Foundation

/// The English behind translated menu titles, so the command palette finds "필터 › 가우시안 흐림 효과…" by "blur" too.
nonisolated struct EnglishTitles {
    /// Translation → English key.
    private let english: [String: String]

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

    /// `table` maps English keys to translations, as a `.strings` file does. When two keys share a translation, the
    /// first in sorted order wins, so the result doesn't depend on dictionary order.
    init(table: [String: String]) {
        var english: [String: String] = [:]
        for key in table.keys.sorted() {
            guard let value = table[key], value != key, english[value] == nil else { continue }
            english[value] = key
        }
        self.english = english
    }

    /// One title in English: as it is, or without the trailing "…" a format such as "%@…" added.
    func english(for title: String) -> String? {
        if let key = english[title] { return key }
        if title.hasSuffix("…"), let key = english[String(title.dropLast())] { return key + "…" }
        return nil
    }

    /// A menu path in English, part by part, keeping parts that have no English; nil when no part has any.
    func english(forPath titles: [String]) -> String? {
        let parts = titles.map(english(for:))
        guard parts.contains(where: { $0 != nil }) else { return nil }
        return zip(titles, parts).map { $1 ?? $0 }.joined(separator: " › ")
    }
}
