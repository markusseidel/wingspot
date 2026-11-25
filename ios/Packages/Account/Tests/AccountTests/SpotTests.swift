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
        #expect(read("https://maps.apple.com/place?coordinate=51.280503,6.769860&name=x")?.1 == 6.76986)
    }

    @Test func coordinatesWithCommaDecimalsAndCompassLettersAreRead() {
        let found = read("51,28050° N, 6,76986° O.")
        #expect(found?.0 == 51.2805)
        #expect(found?.1 == 6.76986)
        #expect(read("33,9° S 18,4° E")?.0 == -33.9)
        #expect(read("40.7 N, 74.0 W")?.1 == -74.0)
        #expect(read("51,2805 6,76986")?.1 == 6.76986)
    }

    @Test func textWithoutAPositionOrWithAnImpossibleOneIsRefused() {
        #expect(read("https://maps.app.goo.gl/abc123") == nil)
        #expect(read("hello") == nil)
        #expect(read("95.0, 8.5") == nil)
        #expect(read("50.0, 190.5") == nil)
    }

    @Test func aSuggestedPlaceIsSentWithTheNamesTheServerExpects() throws {
        let data = try JSONEncoder().encode(NewSpot(name: "Deck", latitude: 50.1, longitude: 8.6, description: "About", bestTime: "Morning", facing: "South", tips: "Parking"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["p_name"] as? String == "Deck")
        #expect(json["p_best_time"] as? String == "Morning")
        #expect(json["p_description"] as? String == "About")
        #expect(json["p_facing"] as? String == "South")
        #expect(json["p_tips"] as? String == "Parking")
        #expect(json["tips"] == nil)
    }

    @Test func anAnswerIsReadForAddedDuplicateAndRefused() throws {
        let added = try JSONDecoder().decode(NewSpotAnswer.self, from: Data(#"{"status":"pending","id":7,"airport_id":3}"#.utf8))
        #expect(added == NewSpotAnswer(status: "pending", id: 7, code: nil))
        let refused = try JSONDecoder().decode(NewSpotAnswer.self, from: Data(#"{"status":"rejected","code":"no_airport_nearby"}"#.utf8))
        #expect(refused.code == "no_airport_nearby")
    }

    @Test func aWaitingPlaceAndADecisionAreRead() throws {
        let json = #"{"id":4,"name":"Terrace","latitude":50.1,"longitude":8.6,"description":null,"best_time":"Morning","facing":null,"tips":null,"legal_notes":null,"airport_id":3,"airport_name":"Frankfurt","airport_code":"FRA","author_id":null,"author_username":"anna","author_name":null,"created_at":"2026-11-21T17:59:27+00:00"}"#
        let spot = try JSONDecoder().decode(PendingSpot.self, from: Data(json.utf8))
        #expect(spot.airportCode == "FRA")
        #expect(spot.bestTime == "Morning")
        #expect(spot.authorUsername == "anna")
        let answer = try JSONDecoder().decode(ReviewAnswer.self, from: Data(#"{"status":"rejected","code":"not_pending"}"#.utf8))
        #expect(answer.code == "not_pending")
    }

    /// A sighting with its own place and no session has no visit (#331).
    @Test func aSightingWithItsOwnPlaceAndNoVisitIsRead() throws {
        let alone = try JSONDecoder().decode(CheckInSpot.self, from: Data(#"{"visit_id":null,"spot_id":7,"spot_name":"North fence","sightings":null}"#.utf8))
        #expect(alone.visitID == nil)
        #expect(alone.spotName == "North fence")
        let visit = try JSONDecoder().decode(CheckInSpot.self, from: Data(#"{"visit_id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","spot_id":7,"spot_name":"North fence","sightings":2}"#.utf8))
        #expect(visit.visitID != nil)
    }
}

/// What `get_companion_requests`, `find_matching_flight` and `replace_flight_data` send back (#273).
@Suite struct CompanionTests {
    @Test func aRequestIsReadFromTheServersAnswer() throws {
        let json = #"[{"checkin_id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","author_id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","username":"jan","display_name":"Jan","kind":"flown","occurred_at":"2026-08-12T12:00:00+00:00","flight_number":"LH400","origin_id":1,"destination_id":2,"origin_code":"FRA","destination_code":"JFK","airport_id":null,"airport_code":null,"distance_km":6200,"requested_at":"2026-08-13T08:00:00.123456+00:00"}]"#
        let requests = try JSONDecoder().decode([CompanionRequest].self, from: Data(json.utf8))
        let request = try #require(requests.first)
        #expect(request.who == "Jan" && request.title == "FRA → JFK" && request.flightNumber == "LH400" && request.distanceKm == 6200)
        #expect(request.requestedAt != nil)
        let visit = #"[{"checkin_id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","author_id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","username":"jan","display_name":null,"kind":"airport","occurred_at":"2026-08-13T09:00:00+00:00","flight_number":null,"origin_id":null,"destination_id":null,"origin_code":null,"destination_code":null,"airport_id":3,"airport_code":"LHR","distance_km":null,"requested_at":"2026-08-13T09:01:00+00:00"}]"#
        let visits = try JSONDecoder().decode([CompanionRequest].self, from: Data(visit.utf8))
        #expect(visits.first?.who == "jan" && visits.first?.title == "LHR")
    }

    @Test func aMatchAndTheReplacedFactsAreRead() throws {
        let match = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","reason":"route","seconds_apart":18000,"flight_number":"UA900","occurred_at":"2026-08-12T17:00:00+00:00","origin_code":"FRA","destination_code":"JFK"}]"#
        let found = try JSONDecoder().decode([MatchingFlight].self, from: Data(match.utf8))
        #expect(found.first?.reason == "route" && found.first?.secondsApart == 18000 && found.first?.originCode == "FRA")
        let facts = #"{"flight_number":"LH500","origin_id":1,"destination_id":2,"occurred_at":"2026-09-01T12:00:00+00:00","registration":null,"type_icao":"A388","distance_km":6200}"#
        let replaced = try JSONDecoder().decode(ReplacedFlight?.self, from: Data(facts.utf8))
        #expect(replaced?.flightNumber == "LH500" && replaced?.typeICAO == "A388" && replaced?.registration == nil)
        #expect(try JSONDecoder().decode(ReplacedFlight?.self, from: Data("null".utf8)) == nil)
    }
}
