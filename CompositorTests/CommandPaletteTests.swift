import AppKit
import Testing
@testable import Compositor

@MainActor
struct CommandPaletteTests {
    private func entry(_ id: String, enabled: Bool = true) -> CommandPaletteEntry {
        CommandPaletteEntry(id: id, shortcut: nil, isEnabled: enabled, perform: {})
    }

    @Test func lettersInOrderMatchAndWordStartsCount() {
        #expect(CommandPaletteSearch.score("gb", in: "Filter › Gaussian Blur…") != nil)
        #expect(CommandPaletteSearch.score("BLUR", in: "Filter › Gaussian Blur…") != nil, "case doesn't matter")
        #expect(CommandPaletteSearch.score("bg", in: "Filter › Gaussian Blur…") == nil, "letters must come in order")
        #expect(CommandPaletteSearch.score("", in: "Anything") == 0)
        let wordStarts = CommandPaletteSearch.score("gb", in: "Filter › Gaussian Blur…")!
        let midWord = CommandPaletteSearch.score("gb", in: "Edit › Debug Tab")!
        #expect(wordStarts > midWord)
    }

    @Test func rankingPutsTheBestAndEnabledFirst() {
        let entries = [entry("Edit › Paste"), entry("Layer › Flip Layer Horizontal"),
                       entry("Filter › Gaussian Blur…"), entry("Filter › Motion Blur…"),
                       entry("Edit › Undo", enabled: false), entry("Image › Levels…")]
        #expect(CommandPaletteSearch.rank(entries, query: "gau").first?.id == "Filter › Gaussian Blur…")
        #expect(CommandPaletteSearch.rank(entries, query: "blur").map(\.id) == ["Filter › Gaussian Blur…", "Filter › Motion Blur…"]
                || CommandPaletteSearch.rank(entries, query: "blur").map(\.id) == ["Filter › Motion Blur…", "Filter › Gaussian Blur…"])
        #expect(CommandPaletteSearch.rank(entries, query: "fl").first?.id == "Layer › Flip Layer Horizontal")
        // No query: everything, enabled first, in menu order.
        let all = CommandPaletteSearch.rank(entries, query: "")
        #expect(all.count == entries.count && all.last?.id == "Edit › Undo" && all.first?.id == "Edit › Paste")
        #expect(CommandPaletteSearch.rank(entries, query: "e u").map(\.id).last == "Edit › Undo", "disabled after enabled")
    }

    /// Typing a tool's name finds the tool first, not a long title that happens to hold its letters scattered.
    @Test func wholeWordsBeatScatteredLetters() {
        let entries = [entry("Layer › New Adjustment Layer › Hue/Saturation…"), entry("Tool › Lasso"), entry("Tool › Polygonal Lasso")]
        #expect(CommandPaletteSearch.rank(entries, query: "lasso").map(\.id) == ["Tool › Lasso", "Tool › Polygonal Lasso",
                                                                               "Layer › New Adjustment Layer › Hue/Saturation…"])
        let model = CommandPaletteModel(entries: entries)
        model.query = "lasso"
        model.move(by: 1)
        model.query = "lasso"
        #expect(model.selected?.id == "Tool › Polygonal Lasso", "Return writing the same text back keeps the choice")
    }

    /// Each typed word starting a word ranks a title high, the shortest first: "new layer" is New Blank Layer.
    @Test func typedWordsStartingWords() {
        let entries = [entry("Layer › New Adjustment Layer › Curves…"), entry("Layer › New Adjustment Layer › Exposure…"),
                       entry("Layer › Duplicate Layer"), entry("Layer › New Blank Layer")]
        #expect(CommandPaletteSearch.rank(entries, query: "new layer").first?.id == "Layer › New Blank Layer")
    }

    /// Against the app's own SwiftUI menu bar, not a hand-built one: its commands are listed, disabled ones greyed
    /// (SwiftUI takes their action away), and running one runs its SwiftUI action.
    @Test func realMenuBarRunsItsCommands() async throws {
        let bar = try #require(NSApp.mainMenu)
        func entries() -> [CommandPaletteEntry] { CommandPaletteMenu.entries(in: bar, skipping: CommandPaletteController.skipped) }
        func gridState() -> NSControl.StateValue? {
            bar.items.first { $0.title == "View" }?.submenu?.items.first { $0.title == "Pixel Grid (800% and above)" }?.state
        }
        let listed = entries()
        let titles = Set(listed.map(\.title))
        #expect(titles.contains("Filter › Gaussian Blur…") && !titles.contains("View › Search Commands…"))
        // The test host has no document open, so Zoom In is disabled: listed, greyed.
        let zoom = try #require(listed.first { $0.title == "View › Zoom In" })
        #expect(!zoom.isEnabled)
        let grid = try #require(listed.first { $0.title == "View › Pixel Grid (800% and above)" })
        let before = try #require(gridState())
        grid.perform()
        try await Task.sleep(for: .milliseconds(300))
        let after = entries() // Reading the menu again refreshes it, as opening the palette does.
        #expect(gridState() != before, "the toggle's SwiftUI binding flipped")
        #expect(after.first { $0.title == grid.title }?.isOn != grid.isOn, "and the palette's checkmark follows it")
        grid.perform() // Put it back.
        try await Task.sleep(for: .milliseconds(300))
    }

    /// A Korean menu is still found by its English: "blur" finds 가우시안 흐림 효과, and so does "흐림".
    @Test func translatedEntriesAreFoundInEitherLanguage() {
        let english = EnglishTitles(table: ["Filter": "필터", "Gaussian Blur": "가우시안 흐림 효과",
                                            "Layer": "레이어", "Duplicate Layer": "레이어 복제"])
        #expect(english.english(forPath: ["필터", "가우시안 흐림 효과…"]) == "Filter › Gaussian Blur…")
        let blur = CommandPaletteEntry(id: "필터 › 가우시안 흐림 효과…",
                                       englishTitle: english.english(forPath: ["필터", "가우시안 흐림 효과…"]),
                                       shortcut: nil, isEnabled: true, perform: {})
        let duplicate = CommandPaletteEntry(id: "레이어 › 레이어 복제",
                                            englishTitle: english.english(forPath: ["레이어", "레이어 복제"]),
                                            shortcut: nil, isEnabled: true, perform: {})
        #expect(CommandPaletteSearch.rank([duplicate, blur], query: "blur").map(\.id) == [blur.id])
        #expect(CommandPaletteSearch.rank([duplicate, blur], query: "흐림").map(\.id) == [blur.id])
        #expect(CommandPaletteSearch.rank([blur, duplicate], query: "dup").first?.id == duplicate.id)
    }

    /// Running in English there's nothing to translate back, and search is as it was.
    @Test func withoutTranslationsThereIsNoEnglishPath() {
        let english = EnglishTitles(table: [:])
        #expect(english.english(forPath: ["Filter", "Gaussian Blur…"]) == nil)
        #expect(EnglishTitles(table: ["Same": "Same"]).english(for: "Same") == nil)
    }

    /// Window and Help are left out by menu, not by title, so they stay out once AppKit translates their titles.
    @Test func skippedMenusAreLeftOutWhateverTheirTitle() {
        let bar = NSMenu()
        for title in ["App", "편집", "윈도우"] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            submenu.addItem(NSMenuItem(title: "\(title) item", action: #selector(NSText.copy(_:)), keyEquivalent: ""))
            item.submenu = submenu
            bar.addItem(item)
        }
        let window = bar.items[2].submenu!
        let ids = CommandPaletteMenu.entries(in: bar, skipping: [], skippingMenus: [window]).map(\.id)
        #expect(ids == ["편집 › 편집 item"])
    }

    /// The menus skipped by identity are known to AppKit in the running app.
    @Test func appKitKnowsTheWindowAndHelpMenus() {
        #expect(NSApp.windowsMenu != nil)
        #expect(NSApp.helpMenu != nil)
    }

    /// Two English commands can share a translation (Zoom Out and Contract are both 축소); either English finds it.
    @Test func sharedTranslationsKeepEveryEnglishName() throws {
        let english = EnglishTitles(table: ["View": "보기", "Zoom Out": "축소", "Contract": "축소"])
        let zoomOut = CommandPaletteEntry(id: "보기 › 축소", englishTitle: english.english(forPath: ["보기", "축소"]),
                                          shortcut: nil, isEnabled: true, perform: {})
        #expect(CommandPaletteSearch.rank([zoomOut], query: "zoom out").map(\.id) == [zoomOut.id])
        #expect(CommandPaletteSearch.rank([zoomOut], query: "contract").map(\.id) == [zoomOut.id])
        // The shipped Korean catalog has such pairs: Invert and Inverse are both 반전.
        let korean = try #require(L10n.koreanBundle?.path(forResource: "Localizable", ofType: "strings"))
        let table = try #require(NSDictionary(contentsOfFile: korean) as? [String: String])
        let shipped = try #require(EnglishTitles(table: table).english(for: "반전"))
        #expect(shipped.contains("Invert") && shipped.contains("Inverse"))
    }
}
