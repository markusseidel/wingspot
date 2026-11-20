import Foundation
import Testing
@testable import Account

@Suite struct InviteTests {
    @Test func aCodeInALinkIsFound() {
        #expect(InviteLink.code(in: URL(string: "wingspot://invite/abcd2345")!) == "ABCD2345")
        #expect(InviteLink.code(in: URL(string: "wingspot://auth-callback?code=xyz")!) == nil)
        #expect(InviteLink.code(in: URL(string: "wingspot://invite/short")!) == nil)
        #expect(InviteLink.code(in: URL(string: "https://example.com/invite/ABCD2345")!) == nil)
    }

    @Test func aTypedCodeIsMadeTidyOrRefused() {
        #expect(InviteLink.clean("  abcd2345 \n") == "ABCD2345")
        #expect(InviteLink.clean("ABCD234") == nil)
        #expect(InviteLink.clean("ABCD2O45") == nil)
    }

    @Test func theLinkOfACodeRoundTrips() {
        let url = InviteLink.url(for: "ABCD2345")!
        #expect(url.absoluteString == "wingspot://invite/ABCD2345")
        #expect(InviteLink.code(in: url) == "ABCD2345")
    }

    @Test func aSuggestionIsReadFromTheServerAnswer() throws {
        let json = #"[{"user_id":"11111111-1111-1111-1111-111111111111","username":"anna","display_name":null,"reason":"tagged","mutual":0}]"#
        let rows = try JSONDecoder().decode([PersonSuggestion].self, from: Data(json.utf8))
        #expect(rows[0].name == "anna")
        #expect(rows[0].reason == "tagged")
    }
}
