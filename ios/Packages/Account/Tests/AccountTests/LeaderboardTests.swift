import Foundation
import Testing
@testable import Account

@Suite struct LeaderboardTests {
    @Test func aRowIsReadFromTheServerAnswer() throws {
        let json = """
        [{"user_id":"11111111-1111-1111-1111-111111111111","username":"anna","display_name":"Anna K","value":5400,"is_me":false},
         {"user_id":"22222222-2222-2222-2222-222222222222","username":"max","display_name":null,"value":500,"is_me":true}]
        """
        let rows = try JSONDecoder().decode([LeaderboardRow].self, from: Data(json.utf8))
        #expect(rows.count == 2)
        #expect(rows[0].name == "Anna K")
        #expect(rows[0].value == 5400)
        #expect(rows[1].name == "max")
        #expect(rows[1].isMe)
    }
}
