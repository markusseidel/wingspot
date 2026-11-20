import Foundation
import Testing
@testable import Account

@Suite struct ActivityTests {
    private func decode(_ json: String) throws -> [ActivityItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ActivityItem].self, from: Data(json.utf8))
    }

    @Test func anInboxRowIsReadFromTheServerAnswer() throws {
        let items = try decode("""
        [{"id":"11111111-1111-1111-1111-111111111111","kind":"salute","actor_id":"22222222-2222-2222-2222-222222222222",
          "username":"anna","display_name":"Anna K","checkin_id":"33333333-3333-3333-3333-333333333333",
          "subject":"FRA → JFK","snippet":null,"created_at":"2026-11-21T10:00:00Z","is_read":false}]
        """)
        #expect(items.count == 1)
        #expect(items[0].kind == "salute")
        #expect(items[0].who == "Anna K")
        #expect(items[0].subject == "FRA → JFK")
        #expect(items[0].isRead == false)
        #expect(items[0].checkInID != nil)
    }

    @Test func theNameFallsBackToTheUsername() throws {
        let items = try decode("""
        [{"id":"11111111-1111-1111-1111-111111111111","kind":"follow","actor_id":"22222222-2222-2222-2222-222222222222",
          "username":"anna","display_name":null,"checkin_id":null,"subject":null,"snippet":null,
          "created_at":"2026-11-21T10:00:00Z","is_read":true}]
        """)
        #expect(items[0].who == "anna")
        #expect(items[0].checkInID == nil)
    }
}

@Suite struct CommentExtraTests {
    private actor Backend: ReactionBackend {
        var saluteCalls: [(Bool, UUID)] = []
        var failSalute = false
        func setSalute(_ on: Bool, checkIn: UUID, as me: UUID) async throws {}
        func comments(checkIn: UUID) async throws -> [CheckInComment] { [] }
        func addComment(_ body: String, checkIn: UUID, as me: UUID) async throws -> CheckInComment {
            CheckInComment(id: UUID(), userID: me, username: "me", body: body, createdAt: Date())
        }
        func deleteComment(_ id: UUID) async throws {}
        func report(_ kind: ReportKind, target: UUID, reason: String) async throws -> ReportOutcome { fatalError() }
        func setCommentSalute(_ on: Bool, comment: UUID) async throws {
            if failSalute { throw AccountError.unknown }
            saluteCalls.append((on, comment))
        }
        func makeFail() { failSalute = true }
    }

    @MainActor @Test func aCommentSaluteIsCountedAtOnceAndGoesBackWhenItFails() async {
        let backend = Backend()
        let store = CheckInCommentStore(checkIn: UUID(), backend: backend, userID: { UUID() })
        let comment = CheckInComment(id: UUID(), userID: UUID(), username: "anna", body: "hi", createdAt: Date())
        await store.toggleSalute(comment)
        #expect(store.extras[comment.id]?.salutes == 1)
        #expect(store.extras[comment.id]?.saluted == true)
        await store.toggleSalute(comment)
        #expect(store.extras[comment.id]?.salutes == 0)
        #expect(store.extras[comment.id]?.saluted == false)
        await backend.makeFail()
        await store.toggleSalute(comment)
        #expect(store.extras[comment.id]?.salutes == 0)
        #expect(store.extras[comment.id]?.saluted == false)
    }

    @Test func theExtrasAreReadFromTheServerAnswer() throws {
        let json = #"{"id":"11111111-1111-1111-1111-111111111111","username":"max"}"#
        let mention = try JSONDecoder().decode(CommentMention.self, from: Data(json.utf8))
        #expect(mention.username == "max")
    }
}
