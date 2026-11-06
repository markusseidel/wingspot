import Foundation
import Testing
@testable import Account

private actor FakeBackend: AccountBackend {
    var sessionUser: UUID?
    var profile: Profile?
    var loadError: AccountError?
    var dropSessionOnLoad = false
    var linkError: AccountError?
    var saveError: AccountError?
    private(set) var sentEmails: [(email: String, language: String?)] = []
    private(set) var signInLinks: [URL] = []

    init(sessionUser: UUID? = nil, profile: Profile? = nil) {
        self.sessionUser = sessionUser
        self.profile = profile
    }

    func fail(load: AccountError? = nil, link: AccountError? = nil, save: AccountError? = nil) {
        loadError = load
        linkError = link
        saveError = save
    }

    func rejectSession() {
        dropSessionOnLoad = true
        loadError = .unknown
    }

    func currentUserID() -> UUID? { sessionUser }

    func accessToken() -> String? { sessionUser == nil ? nil : "token-for-\(sessionUser!)" }

    func sendSignInLink(email: String, language: String?) {
        sentEmails.append((email, language))
    }

    private(set) var appleTokens: [(token: String, nonce: String)] = []
    var appleError: AccountError?

    func failApple(_ error: AccountError?) { appleError = error }

    func signInWithApple(idToken: String, nonce: String) throws -> UUID {
        appleTokens.append((idToken, nonce))
        if let appleError { throw appleError }
        let id = profile?.id ?? UUID()
        sessionUser = id
        return id
    }

    func completeSignIn(from url: URL) throws -> UUID {
        signInLinks.append(url)
        if let linkError { throw linkError }
        let id = profile?.id ?? UUID()
        sessionUser = id
        return id
    }

    func loadProfile(id: UUID) throws -> Profile {
        if dropSessionOnLoad { sessionUser = nil }
        if let loadError { throw loadError }
        return profile ?? Profile(id: id, username: "user_0123456789abcdef012345678")
    }

    func saveProfile(_ profile: Profile) throws {
        if let saveError { throw saveError }
        self.profile = profile
    }

    func signOut() {
        sessionUser = nil
    }
}

@MainActor
struct AccountStoreTests {
    private let link = URL(string: "wingspot://auth-callback?code=abc")!

    @Test func startsSignedOutWithoutASession() async {
        let store = AccountStore(backend: FakeBackend())
        #expect(store.state == .loading)
        await store.start()
        #expect(store.state == .signedOut)
    }

    @Test func restoresTheSessionAndProfile() async {
        let id = UUID()
        let profile = Profile(id: id, username: "spotter")
        let store = AccountStore(backend: FakeBackend(sessionUser: id, profile: profile))
        await store.start()
        #expect(store.state == .signedIn(profile))
    }

    @Test func staysSignedInWhileOffline() async {
        let backend = FakeBackend(sessionUser: UUID())
        await backend.fail(load: .offline)
        let store = AccountStore(backend: backend)
        await store.start()
        #expect(store.state == .signedIn(nil))
        #expect(!store.needsProfileSetup)
    }

    @Test func signsOutWhenTheServerRejectedTheSession() async {
        let backend = FakeBackend(sessionUser: UUID())
        await backend.rejectSession()
        let store = AccountStore(backend: backend)
        await store.start()
        #expect(store.state == .signedOut)
    }

    @Test func knowsTheUserFromTheStoredSessionEvenOffline() async {
        let id = UUID()
        let backend = FakeBackend(sessionUser: id)
        await backend.fail(load: .offline)
        let store = AccountStore(backend: backend)
        #expect(store.userID == nil)
        await store.start()
        #expect(store.userID == id)
    }

    @Test func hasNoUserIDWhenSignedOutOrTheSessionWasRejected() async {
        let store = AccountStore(backend: FakeBackend())
        await store.start()
        #expect(store.userID == nil)

        let backend = FakeBackend(sessionUser: UUID())
        await backend.rejectSession()
        let rejected = AccountStore(backend: backend)
        await rejected.start()
        #expect(rejected.userID == nil)
    }

    @Test func theUserIDFollowsSignInAndSignOut() async throws {
        let store = AccountStore(backend: FakeBackend())
        await store.start()
        #expect(await store.handle(link))
        let id = try #require(store.userID)
        #expect(await store.accessToken() == "token-for-\(id)")

        try await store.signOut()
        #expect(store.userID == nil)
        #expect(await store.accessToken() == nil)
    }

    @Test func signingInWithAppleStartsASessionAndKeepsTheNameOnce() async throws {
        let backend = FakeBackend()
        let store = AccountStore(backend: backend)
        await store.start()

        try await store.signInWithApple(idToken: "token", nonce: "raw-nonce", fullName: "  Ana Pilot \n")

        let sent = await backend.appleTokens
        #expect(sent.count == 1 && sent[0].token == "token" && sent[0].nonce == "raw-nonce")
        #expect(store.userID != nil)
        #expect(store.state != .signedOut)
        #expect(store.takeSuggestedName() == "Ana Pilot")
        #expect(store.takeSuggestedName() == nil, "the name is used once")
    }

    @Test func appleWithoutANameLeavesNoSuggestion() async throws {
        let store = AccountStore(backend: FakeBackend())
        try await store.signInWithApple(idToken: "t", nonce: "n", fullName: nil)
        #expect(store.takeSuggestedName() == nil)
        try await store.signInWithApple(idToken: "t", nonce: "n", fullName: "   ")
        #expect(store.takeSuggestedName() == nil)
    }

    @Test func aFailedAppleSignInChangesNothing() async {
        let backend = FakeBackend()
        await backend.failApple(.appleUnavailable)
        let store = AccountStore(backend: backend)
        await store.start()

        await #expect(throws: AccountError.appleUnavailable) {
            try await store.signInWithApple(idToken: "t", nonce: "n", fullName: "Ana")
        }

        #expect(store.state == .signedOut)
        #expect(store.userID == nil)
        #expect(store.takeSuggestedName() == nil)
    }

    @Test func trimsTheEmailAndPassesTheLanguage() async throws {
        let backend = FakeBackend()
        let store = AccountStore(backend: backend)
        try await store.sendSignInLink(email: "  ana@example.com\n", language: "de")
        let sent = await backend.sentEmails
        #expect(sent.first?.email == "ana@example.com")
        #expect(sent.first?.language == "de")
    }

    @Test func rejectsAnImplausibleEmailWithoutCallingTheBackend() async {
        let backend = FakeBackend()
        let store = AccountStore(backend: backend)
        await #expect(throws: AccountError.invalidEmail) {
            try await store.sendSignInLink(email: "not-an-email", language: nil)
        }
        #expect(await backend.sentEmails.isEmpty)
    }

    @Test func aSignInLinkSignsInAndAsksForAUsername() async {
        let store = AccountStore(backend: FakeBackend())
        await store.start()
        #expect(await store.handle(link))
        #expect(store.profile != nil)
        #expect(store.needsProfileSetup)
    }

    @Test func ignoresOtherLinks() async {
        let backend = FakeBackend()
        let store = AccountStore(backend: backend)
        await store.start()
        #expect(await !store.handle(URL(string: "wingspot://u/spotter")!))
        #expect(await !store.handle(URL(string: "https://auth-callback/?code=abc")!))
        #expect(store.state == .signedOut)
        #expect(await backend.signInLinks.isEmpty)
    }

    @Test func aBadLinkKeepsTheUserSignedOutAndReportsIt() async {
        let backend = FakeBackend()
        await backend.fail(link: .invalidLink)
        let store = AccountStore(backend: backend)
        await store.start()
        #expect(await store.handle(link))
        #expect(store.state == .signedOut)
        #expect(store.linkError == .invalidLink)
    }

    @Test func savesAProfile() async throws {
        let id = UUID()
        let backend = FakeBackend(sessionUser: id, profile: Profile(id: id, username: "user_0123456789abcdef012345678"))
        let store = AccountStore(backend: backend)
        await store.start()
        #expect(store.needsProfileSetup)

        let chosen = Profile(id: id, username: "spotter", displayName: "Ana", homeAirportID: 2212)
        try await store.save(chosen)

        #expect(store.state == .signedIn(chosen))
        #expect(!store.needsProfileSetup)
        #expect(await backend.profile == chosen)
    }

    @Test func aTakenUsernameKeepsTheOldProfile() async {
        let id = UUID()
        let old = Profile(id: id, username: "spotter")
        let backend = FakeBackend(sessionUser: id, profile: old)
        await backend.fail(save: .usernameTaken)
        let store = AccountStore(backend: backend)
        await store.start()

        await #expect(throws: AccountError.usernameTaken) {
            try await store.save(Profile(id: id, username: "taken"))
        }
        #expect(store.state == .signedIn(old))
    }

    @Test func rejectsAnInvalidUsernameWithoutCallingTheBackend() async {
        let id = UUID()
        let old = Profile(id: id, username: "spotter")
        let backend = FakeBackend(sessionUser: id, profile: old)
        let store = AccountStore(backend: backend)
        await store.start()

        await #expect(throws: AccountError.invalidUsername) {
            try await store.save(Profile(id: id, username: "No Spaces"))
        }
        #expect(await backend.profile == old)
    }

    @Test func signOutEndsTheSession() async throws {
        let id = UUID()
        let backend = FakeBackend(sessionUser: id, profile: Profile(id: id, username: "spotter"))
        let store = AccountStore(backend: backend)
        await store.start()
        try await store.signOut()
        #expect(store.state == .signedOut)
        #expect(await backend.sessionUser == nil)
    }
}

struct ProfileRulesTests {
    @Test(arguments: [
        ("user_0123456789abcdef012345678", false),
        ("user_ana", true),
        ("spotter", true),
    ])
    func recognizesGeneratedUsernames(username: String, chosen: Bool) {
        #expect(Profile(id: UUID(), username: username).hasChosenUsername == chosen)
    }

    @Test(arguments: [
        ("abc", true), ("spotter_1", true), (String(repeating: "a", count: 30), true),
        ("ab", false), (String(repeating: "a", count: 31), false),
        ("Spotter", false), ("with space", false), ("müller", false), ("a-b", false),
    ])
    func usernameRuleMatchesTheDatabase(username: String, valid: Bool) {
        #expect(Username.isValid(username) == valid)
    }

    @Test func normalizesTypedUsernames() {
        #expect(Username.normalized("  Spotter_1\n") == "spotter_1")
    }

    @Test(arguments: [
        ("ana@example.com", true), (" ana@example.co.uk ", true),
        ("", false), ("ana", false), ("ana@example", false), ("a b@example.com", false), ("a@b@example.com", false),
    ])
    func checksEmailAddresses(email: String, plausible: Bool) {
        #expect(EmailAddress.isPlausible(email) == plausible)
    }
}
