import Foundation
import Testing
@testable import Account

@Suite struct SpotTests {
    private func read(_ text: String) -> (Double, Double)? {
        MapsLink.coordinate(in: text).map { ($0.latitude, $0.longitude) }
    }

    @Test func aGoogleMapsLinkGivesThePlaceNotTheView() {
        let link = "https://www.google.com/maps/place/Terminal+2/@50.0452,8.5705,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d50.0461!4d8.5712"
        let found = read(link)
        #expect(found?.0 == 50.0461)
        #expect(found?.1 == 8.5712)
    }

    @Test func otherCommonLinksAreRead() {
        #expect(read("https://www.google.com/maps/@50.04,8.57,15z")?.0 == 50.04)
        #expect(read("https://maps.apple.com/?ll=50.1,8.6&q=Deck")?.1 == 8.6)
        #expect(read("https://www.google.com/maps/search/?api=1&query=50.2%2C8.7")?.1 == 8.7)
        #expect(read("50.05, -8.5")?.1 == -8.5)
    }

    @Test func textWithoutAPositionOrWithAnImpossibleOneIsRefused() {
        #expect(read("https://maps.app.goo.gl/abc123") == nil)
        #expect(read("hello") == nil)
        #expect(read("95.0, 8.5") == nil)
        #expect(read("50.0, 190.5") == nil)
    }

    @Test func aSuggestedPlaceIsSentWithTheNamesTheServerExpects() throws {
        let data = try JSONEncoder().encode(NewSpot(name: "Deck", latitude: 50.1, longitude: 8.6, bestTime: "Morning"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["p_name"] as? String == "Deck")
        #expect(json["p_best_time"] as? String == "Morning")
        #expect(json["p_tips"] == nil)
    }

    @Test func anAnswerIsReadForAddedDuplicateAndRefused() throws {
        let added = try JSONDecoder().decode(NewSpotAnswer.self, from: Data(#"{"status":"pending","id":7,"airport_id":3}"#.utf8))
        #expect(added == NewSpotAnswer(status: "pending", id: 7, code: nil))
        let refused = try JSONDecoder().decode(NewSpotAnswer.self, from: Data(#"{"status":"rejected","code":"no_airport_nearby"}"#.utf8))
        #expect(refused.code == "no_airport_nearby")
    }
}
