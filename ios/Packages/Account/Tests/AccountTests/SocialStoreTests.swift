import Foundation
import Testing
@testable import Account

private actor FakeSocial: SocialBackend {
    var people: [PersonRecord]
    var following: [UUID] = []
    var followers: [UUID] = []
    var blocks: [UUID] = []
    var choice = SharingChoice.private
    private(set) var lastSearch: String?
    private(set) var applied: [(SharingChoice, Bool)] = []
    var error: AccountError?

    init(people: [PersonRecord]) { self.people = people }

    func set(following: [UUID] = [], followers: [UUID] = []) {
        self.following = following
        self.followers = followers
    }

    func fail(_ error: AccountError?) { self.error = error }

    func searchPeople(_ text: String, excluding me: UUID, limit: Int) throws -> [PersonRecord] {
        if let error { throw error }
        lastSearch = text
        return people.filter { $0.username.contains(text) && $0.id != me }
    }

    func relationships(of me: UUID, among ids: [UUID]) -> (following: Set<UUID>, followers: Set<UUID>) {
        (Set(following).intersection(ids), Set(followers).intersection(ids))
    }

    func followingIDs(of me: UUID) -> [UUID] { following }
    func followerIDs(of me: UUID) -> [UUID] { followers }
    func profiles(ids: [UUID]) -> [PersonRecord] { ids.compactMap { id in people.first { $0.id == id } } }

    func follow(_ id: UUID, as me: UUID) throws {
        if let error { throw error }
        if !following.contains(id) { following.append(id) }
    }

    func unfollow(_ id: UUID, as me: UUID) { following.removeAll { $0 == id } }

    func blockedPeople() -> [PersonRecord] { blocks.compactMap { id in people.first { $0.id == id } } }

    func block(_ id: UUID, as me: UUID) {
        blocks.append(id)
        following.removeAll { $0 == id }
        followers.removeAll { $0 == id }
    }

    func unblock(_ id: UUID, as me: UUID) { blocks.removeAll { $0 == id } }
    var settings = PrivacySettings()
    func privacy(of me: UUID) -> PrivacySettings { settings }
    func setPrivacy(_ settings: PrivacySettings, as me: UUID) { self.settings = settings }

    func sharing(of me: UUID) -> SharingChoice { choice }

    func setSharing(_ choice: SharingChoice, applyToExisting: Bool) -> Int {
        self.choice = choice
        applied.append((choice, applyToExisting))
        return applyToExisting ? 3 : 0
    }
}

private let me = UUID()
private let anna = PersonRecord(id: UUID(), username: "anna_spots", displayName: "Anna", isPrivate: false)
private let ben = PersonRecord(id: UUID(), username: "ben_b", displayName: nil, isPrivate: true)

@MainActor private func makeStore(_ backend: FakeSocial, signedIn: Bool = true) -> SocialStore {
    SocialStore(backend: backend, userID: { signedIn ? me : nil })
}

@MainActor @Test func searchAddsHowEachPersonRelatesToYou() async throws {
    let backend = FakeSocial(people: [anna, ben])
    await backend.set(following: [anna.id], followers: [anna.id, ben.id])
    let found = try await makeStore(backend).search("an")
    #expect(found.map(\.username) == ["anna_spots"])
    #expect(found.first?.isFollowing == true)
    #expect(found.first?.isFriend == true)

    let others = try await makeStore(backend).search("n_")
    #expect(others.first?.isFollowing == false)
    #expect(others.first?.followsYou == true)
    #expect(others.first?.isPrivate == true)
}

@MainActor @Test func searchCleansTheTextAndNeedsTwoLetters() async throws {
    let backend = FakeSocial(people: [anna])
    let store = makeStore(backend)
    #expect(try await store.search("a").isEmpty)
    #expect(await backend.lastSearch == nil)
    _ = try await store.search("  An%na,(x) ")
    #expect(await backend.lastSearch == "annax")
}

@MainActor @Test func searchNeedsASignedInUser() async {
    await #expect(throws: AccountError.unknown) {
        try await makeStore(FakeSocial(people: [anna]), signedIn: false).search("an")
    }
}

@MainActor @Test func followAndUnfollowChangeWhatTheListsShow() async throws {
    let backend = FakeSocial(people: [anna, ben])
    let store = makeStore(backend)
    try await store.follow(anna.id)
    try await store.follow(anna.id)
    #expect(try await store.following().map(\.username) == ["anna_spots"])
    try await store.unfollow(anna.id)
    #expect(try await store.following().isEmpty)
}

@MainActor @Test func blockingRemovesTheFollowAndListsTheBlockedPerson() async throws {
    let backend = FakeSocial(people: [anna, ben])
    await backend.set(following: [anna.id], followers: [anna.id])
    let store = makeStore(backend)
    try await store.block(anna.id)
    #expect(try await store.following().isEmpty)
    #expect(try await store.followers().isEmpty)
    #expect(try await store.blocked().map(\.username) == ["anna_spots"])
    try await store.unblock(anna.id)
    #expect(try await store.blocked().isEmpty)
}

@MainActor @Test func aPersonCanBeLookedUpAgain() async throws {
    let backend = FakeSocial(people: [anna])
    await backend.set(following: [anna.id])
    let person = try await makeStore(backend).person(anna.id)
    #expect(person?.isFollowing == true)
    #expect(try await makeStore(backend).person(UUID()) == nil)
}

@MainActor @Test func errorsReachTheCaller() async {
    let backend = FakeSocial(people: [anna])
    await backend.fail(.offline)
    await #expect(throws: AccountError.offline) { try await makeStore(backend).follow(anna.id) }
}

@MainActor @Test func theSharingChoiceCanBeReadAndChanged() async throws {
    let backend = FakeSocial(people: [])
    let store = makeStore(backend)
    #expect(try await store.sharing() == .private)
    #expect(try await store.setSharing(.friends, applyToExisting: true) == 3)
    #expect(try await store.sharing() == .friends)
    #expect(await backend.applied.count == 1)
}

@MainActor @Test func privacySettingsCanBeReadAndChanged() async throws {
    let store = makeStore(FakeSocial(people: []))
    #expect(try await store.privacy() == PrivacySettings())
    try await store.setPrivacy(PrivacySettings(isPrivate: true, postDelayMinutes: 360))
    #expect(try await store.privacy() == PrivacySettings(isPrivate: true, postDelayMinutes: 360))
    #expect(PrivacySettings.delayChoices.contains(360))
}
