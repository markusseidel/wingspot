import Foundation
import Testing
import WingspotCore

struct KmlAirportVector: Decodable, Sendable {
    let iata: String?
    let icao: String?
    let name: String?
    let city: String?
}

struct KmlVector: Decodable, Sendable, CustomTestStringConvertible {
    let file: String
    let error: String?
    let title: String?
    let flightNumber: String?
    let airline: String?
    let origin: KmlAirportVector?
    let destination: KmlAirportVector?
    let departureDate: String?
    let departureTime: String?
    let arrivalTime: String?
    let aircraftTypeCode: String?
    let aircraftTypeName: String?
    let registration: String?
    let flightLink: String?
    let trackSource: String?
    let trackPoints: Int?
    let trackFirst: [Double]?
    let trackLast: [Double]?

    var testDescription: String { file }
}

struct KmlVectors: Decodable { let cases: [KmlVector] }

private func kmlText(_ file: String) -> String {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<6 { url.deleteLastPathComponent() }
    url.append(path: "contracts/test-vectors/kml/\(file)")
    return try! String(contentsOf: url, encoding: .utf8)
}

@Suite struct KmlFlightTests {
    static let vectors = TestVectors.load("kml-flights", as: KmlVectors.self)

    private func check(_ airport: KmlAirport?, _ expected: KmlAirportVector?, _ label: String) {
        #expect(airport?.iata == expected?.iata, "\(label) iata")
        #expect(airport?.icao == expected?.icao, "\(label) icao")
        #expect(airport?.name == expected?.name, "\(label) name")
        #expect(airport?.city == expected?.city, "\(label) city")
    }

    @Test(arguments: vectors.cases)
    func readsTheFile(_ vector: KmlVector) throws {
        if let error = vector.error {
            #expect(error == "notKml")
            #expect(throws: KmlFlightError.notKml) { try KmlFlightParser.parse(kmlText(vector.file)) }
            return
        }
        let flight = try KmlFlightParser.parse(kmlText(vector.file))
        #expect(flight.title == vector.title)
        #expect(flight.flightNumber == vector.flightNumber)
        #expect(flight.airline == vector.airline)
        check(flight.origin, vector.origin, "origin")
        check(flight.destination, vector.destination, "destination")
        #expect(flight.departureDate == vector.departureDate)
        #expect(flight.departureTime == vector.departureTime)
        #expect(flight.arrivalTime == vector.arrivalTime)
        #expect(flight.aircraftTypeCode == vector.aircraftTypeCode)
        #expect(flight.aircraftTypeName == vector.aircraftTypeName)
        #expect(flight.registration == vector.registration)
        #expect(flight.flightLink == vector.flightLink)
        #expect(flight.trackSource.rawValue == vector.trackSource)
        #expect(flight.track.count == vector.trackPoints)
        if let first = vector.trackFirst, let last = vector.trackLast {
            #expect(flight.track.first == GeoCoordinate(latitude: first[1], longitude: first[0]))
            #expect(flight.track.last == GeoCoordinate(latitude: last[1], longitude: last[0]))
        }
    }

    @Test func theDateLineTrackKeepsItsRawLongitudes() throws {
        let flight = try KmlFlightParser.parse(kmlText("date-line.kml"))
        #expect(FlightTrack.crossesAntimeridian(flight.track))
        #expect(flight.track.contains { $0.longitude >= 179 } && flight.track.contains { $0.longitude < -170 })
    }

    @Test func aMissingFieldNeverStopsTheImport() throws {
        let minimal = "<kml><Document><Placemark><description>nothing useful</description></Placemark></Document></kml>"
        let flight = try KmlFlightParser.parse(minimal)
        #expect(flight.flightNumber == nil && flight.origin == nil && flight.track.isEmpty && flight.trackSource == .none)
    }

    @Test func positionsOutsideTheEarthAreSkipped() {
        let points = KmlFlightParser.parseCoordinates("10,20,0 200,20,0 10,95,0 bad 11,21 12,22,500\n13,23")
        #expect(points.map(\.longitude) == [10, 11, 12, 13])
    }

    @Test func aDescriptionInAnEntityEscapedFormAndInCdataReadTheSame() throws {
        let escaped = "<kml><Document><Placemark><description>From: &lt;b&gt;Test Airport (ABC)&lt;/b&gt;</description></Placemark></Document></kml>"
        let cdata = "<kml><Document><Placemark><description><![CDATA[From: <b>Test Airport (ABC)</b>]]></description></Placemark></Document></kml>"
        #expect(try KmlFlightParser.parse(escaped).origin == KmlFlightParser.parse(cdata).origin)
        #expect(try KmlFlightParser.parse(cdata).origin == KmlAirport(iata: "ABC", icao: nil, name: "Test Airport", city: nil))
    }

    @Test func aLongTrackOfFiftyThousandPositionsIsRead() throws {
        let line = (0..<50_000).map { "\(Double($0) * 0.0001 - 10),\(45 + Double($0 % 100) * 0.0001),9000" }.joined(separator: " ")
        let flight = try KmlFlightParser.parse("<kml><Document><Placemark><LineString><coordinates>\(line)</coordinates></LineString></Placemark></Document></kml>")
        #expect(flight.track.count == 50_000)
    }

    @Test func aLinkWithAnIdIsNotAFlightNumber() throws {
        let kml = "<kml><Document><Placemark><description>&lt;a href=\"https://www.flightradar24.com/flight/3f2a1b9c4d\"&gt;x&lt;/a&gt;</description></Placemark></Document></kml>"
        let flight = try KmlFlightParser.parse(kml)
        #expect(flight.flightNumber == nil)
        #expect(flight.flightLink == "https://www.flightradar24.com/flight/3f2a1b9c4d")
    }

    @Test func theDepartureDayIsADateOnTheCalendarAndNeverInTheFuture() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22))!
        var flight = KmlFlight()
        #expect(flight.departureDay(today: today, calendar: calendar) == nil)
        flight.departureDate = "2026-11-02"
        #expect(flight.departureDay(today: today, calendar: calendar) == calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)))
        flight.departureDate = "2027-01-05"
        #expect(flight.departureDay(today: today, calendar: calendar) == today)
        flight.departureDate = "not a date"
        #expect(flight.departureDay(today: today, calendar: calendar) == nil)
    }
}
