import Foundation
import Testing
@testable import Account

private actor FakeNotes: ReleaseNotesBackend {
    var items: [ReleaseNote]
    var failing = false
    init(_ items: [ReleaseNote]) { self.items = items }
    func fail(_ on: Bool) { failing = on }
    func releaseNotes(platform: String) throws -> [ReleaseNote] {
        if failing { throw AccountError.offline }
        return items
    }
}

private let seven = ReleaseNote(version: "0.2.0", build: 2026112307, titleEN: "Seven", bodyEN: "- one\n- two", titleDE: "Sieben", bodyDE: "- eins\n- zwei")
private let eight = ReleaseNote(version: "0.2.0", build: 2026112308, titleEN: "Eight", bodyEN: "- three")
private let nine = ReleaseNote(version: "0.2.0", build: 2026112309, titleEN: "Nine", bodyEN: "- four", releasedAt: Date())

private func freshDefaults() -> UserDefaults {
    let suite = "release-notes-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Test func theReleaseNoteRowsDecode() throws {
    let json = Data("""
    [{"id":"00000000-0000-0000-0000-0000000000a1","version":"0.2.0","build":2026112308,"kind":"beta","title_en":"T","body_en":"- B",
      "title_de":null,"body_de":null,"released_at":"2026-11-23T10:00:00+00:00","something_new":1}]
    """.utf8)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let items = try decoder.decode([ReleaseNote].self, from: json)
    #expect(items.map(\.build) == [2026112308])
    #expect(items[0].isBeta)
    #expect(items[0].titleDE == nil)
}

@Test func bulletsBecomeLines() {
    #expect(ReleaseNote.lines(of: "- one\n\n  - two \nplain") == ["one", "two", "plain"])
}

@Test func releaseNoteGermanOrEnglish() {
    #expect(seven.text(language: "de").title == "Sieben")
    #expect(seven.text(language: "de").lines == ["eins", "zwei"])
    #expect(seven.text(language: "en").title == "Seven")
    #expect(eight.text(language: "de").title == "Eight")
}

@MainActor @Test func theNewestBuildComesFirstAndTheInstalledOneSplitsTheList() async {
    let store = ReleaseNotesStore(backend: FakeNotes([seven, nine, eight]), defaults: freshDefaults())
    await store.refresh()
    #expect(store.notes.map(\.build) == [2026112309, 2026112308, 2026112307])
    #expect(store.newer(than: 2026112308).map(\.build) == [2026112309])
    #expect(store.installedAndOlder(than: 2026112308).map(\.build) == [2026112308, 2026112307])
}

@MainActor @Test func theLastListSurvivesAnOfflineStart() async {
    let defaults = freshDefaults()
    let backend = FakeNotes([seven, eight])
    let online = ReleaseNotesStore(backend: backend, defaults: defaults)
    await online.refresh()
    await backend.fail(true)
    let offline = ReleaseNotesStore(backend: backend, defaults: defaults)
    #expect(offline.notes.map(\.build) == [2026112308, 2026112307])
    await offline.refresh()
    #expect(offline.loadFailed)
    #expect(offline.notes.count == 2)
}
