import Testing
@testable import Account

@Suite struct CommentTextTests {
    @Test func theNameBeingTypedIsFound() {
        #expect(CommentText.activePrefix(in: "hello @Ma") == "ma")
        #expect(CommentText.activePrefix(in: "@") == "")
        #expect(CommentText.activePrefix(in: "hello") == nil)
        #expect(CommentText.activePrefix(in: "hello @max ") == nil)
        #expect(CommentText.activePrefix(in: "mail@max") == nil)
    }

    @Test func aChosenFriendReplacesWhatWasTyped() {
        #expect(CommentText.completing("hi @ma", with: "max_k") == "hi @max_k ")
        #expect(CommentText.completing("@", with: "anna") == "@anna ")
        #expect(CommentText.completing("hi", with: "anna") == "hi")
    }

    @Test func aReplyStartsWithTheName() {
        #expect(CommentText.replying(to: "anna", in: "") == "@anna ")
        #expect(CommentText.replying(to: "anna", in: "thanks") == "@anna thanks")
        #expect(CommentText.replying(to: "anna", in: "@Anna thanks") == "@Anna thanks")
    }

    @Test func mentionsAreFoundAtWordBoundaries() {
        let body = "Hi @Max and @maxine, not mail@max.de, @max!"
        let found = CommentText.mentionRanges(in: body, usernames: ["max", "maxine"])
        #expect(found.map(\.username) == ["max", "maxine", "max"])
        #expect(found.map { String(body[$0.range]) } == ["@Max", "@maxine", "@max"])
    }
}
