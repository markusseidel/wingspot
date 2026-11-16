import Foundation
import Testing
@testable import Account

private actor FakeAnnouncements: AnnouncementBackend {
    var items: [Announcement]
    var failing = false
    init(_ items: [Announcement]) { self.items = items }
    func set(_ items: [Announcement]) { self.items = items }
    func fail(_ on: Bool) { failing = on }
    func announcements() throws -> [Announcement] {
        if failing { throw AccountError.offline }
        return items
    }
}

private let first = Announcement(
    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")!, titleEN: "Small list", bodyEN: "The type list stays small.",
    titleDE: "Kleine Liste", bodyDE: "Die Typenliste bleibt klein."
)
private let second = Announcement(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000a2")!, titleEN: "English only", bodyEN: "No translation.")

private func freshDefaults() -> UserDefaults {
    let suite = "announcement-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Test func theServersRowsDecode() throws {
    let json = Data("""
    [{"id":"00000000-0000-0000-0000-0000000000a1","title_en":"T","body_en":"B","title_de":null,"body_de":null,
      "created_at":"2026-11-16T10:00:00+00:00","expires_at":null,"something_new":1}]
    """.utf8)
    let items = try JSONDecoder().decode([Announcement].self, from: json)
    #expect(items.map(\.titleEN) == ["T"])
    #expect(items[0].titleDE == nil)
}

@Test func germanIsUsedWhenThereIsAnyElseEnglish() {
    #expect(first.text(language: "de").title == "Kleine Liste")
    #expect(first.text(language: "en").title == "Small list")
    #expect(first.text(language: "fr").body == "The type list stays small.")
    #expect(second.text(language: "de").title == "English only")
}

@MainActor @Test func refreshShowsWhatTheServerSent() async {
    let store = AnnouncementStore(backend: FakeAnnouncements([first, second]), defaults: freshDefaults())
    #expect(store.visible.isEmpty)
    await store.refresh()
    #expect(store.visible.map(\.id) == [first.id, second.id])
}

@MainActor @Test func aDismissedOneStaysGoneAfterARestart() async {
    let defaults = freshDefaults()
    let backend = FakeAnnouncements([first, second])
    let store = AnnouncementStore(backend: backend, defaults: defaults)
    await store.refresh()
    store.dismiss(first.id)
    #expect(store.visible.map(\.id) == [second.id])
    let restarted = AnnouncementStore(backend: backend, defaults: defaults)
    await restarted.refresh()
    #expect(restarted.visible.map(\.id) == [second.id])
}

@MainActor @Test func theLastListShowsOfflineAndAFailedRefreshKeepsIt() async {
    let defaults = freshDefaults()
    let backend = FakeAnnouncements([first])
    await AnnouncementStore(backend: backend, defaults: defaults).refresh()
    await backend.fail(true)
    let offline = AnnouncementStore(backend: backend, defaults: defaults)
    #expect(offline.visible.map(\.id) == [first.id])
    await offline.refresh()
    #expect(offline.visible.map(\.id) == [first.id])
}

@MainActor @Test func anAnnouncementTakenDownDisappearsAndItsDismissalIsForgotten() async {
    let defaults = freshDefaults()
    let backend = FakeAnnouncements([first, second])
    let store = AnnouncementStore(backend: backend, defaults: defaults)
    await store.refresh()
    store.dismiss(first.id)
    await backend.set([second])
    await store.refresh()
    #expect(store.visible.map(\.id) == [second.id])
    #expect(defaults.stringArray(forKey: "announcementsDismissed") == [])
}
