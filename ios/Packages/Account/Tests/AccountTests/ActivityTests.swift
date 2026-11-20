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
