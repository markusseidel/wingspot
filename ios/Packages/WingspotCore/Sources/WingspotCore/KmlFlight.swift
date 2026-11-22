import Foundation

/// An airport as a KML file names it. Every part is optional.
public struct KmlAirport: Hashable, Sendable {
    public var iata: String?
    public var icao: String?
    public var name: String?
    public var city: String?

    public init(iata: String? = nil, icao: String? = nil, name: String? = nil, city: String? = nil) {
        self.iata = iata
        self.icao = icao
        self.name = name
        self.city = city
    }

    public var isEmpty: Bool { iata == nil && icao == nil && name == nil && city == nil }
}

/// Where the track of a flight was found.
public enum KmlTrackSource: String, Sendable {
    /// The longest line of positions in the file.
    case line
    /// The single position reports, sorted by their time stamp.
    case placemarks
    /// No usable track.
    case none
}

/// What a KML file of one flight says. **Every field is optional.** A field that was not found stays empty and never
/// stops the import. Times are kept as the text the file has, because the time zone of the times in the description is
/// not yet confirmed, and the person checks them on the review screen anyway.
public struct KmlFlight: Sendable {
    public var title: String?
    public var flightNumber: String?
    public var airline: String?
    public var origin: KmlAirport?
    public var destination: KmlAirport?
    /// `yyyy-MM-dd`, from the description or else from the first time stamp (UTC).
    public var departureDate: String?
    /// `HH:mm` as written in the file.
    public var departureTime: String?
    public var arrivalTime: String?
    public var aircraftTypeCode: String?
    public var aircraftTypeName: String?
    public var registration: String?
    /// The link to the flight in the file, as written. It tells two imports of the same flight apart.
    public var flightLink: String?
    /// The positions in the order they were flown, as in the file.
    public var track: [GeoCoordinate] = []
    public var trackSource: KmlTrackSource = .none

    public init() {}
}

extension KmlFlight {
    /// The day of the flight as a date on the calendar of the person, never after today, or nil if the file had no day.
    public func departureDay(today: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let text = departureDate else { return nil }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        return min(date, today)
    }
}

public enum KmlFlightError: Error, Equatable, Sendable {
    /// The text is not a KML file.
    case notKml
}

/// Reads a KML file of one flight, as exported by flight-tracking sites. The text inside `<description>` is HTML that no
/// one documents and that has already changed, so everything is looked up leniently and nothing is required. Two layouts
/// are known (a newer one with airport links and an older one with "From:" and "To:" lines). The same code runs on
/// Android and is checked against the made-up files in `contracts/test-vectors/kml`.
public enum KmlFlightParser {
    /// A block of positions with fewer points than this is the straight line from the origin to the destination, not a track.
    static let minimumLinePoints = 3

    public static func parse(_ text: String) throws -> KmlFlight {
        guard text.contains("<kml") || text.contains("<Document") || text.contains("<coordinates") else { throw KmlFlightError.notKml }
        var flight = KmlFlight()
        flight.title = elements("name", in: text).first.map(clean).flatMap { $0.isEmpty ? nil : $0 }
        let descriptions = elements("description", in: text).map(descriptionHtml)

        let (track, source) = findTrack(in: text)
        flight.track = track
        flight.trackSource = source
        let firstTime = elements("when", in: text).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.min()

        for html in descriptions { read(html, into: &flight) }
        if flight.departureDate == nil, let firstTime, let match = firstMatch("^(\\d{4}-\\d{2}-\\d{2})", in: firstTime) {
            flight.departureDate = match[1]
        }
        if flight.origin == nil || flight.destination == nil {
            let places = [flight.title].compactMap { $0 } + descriptions.map(plainText)
            for place in places {
                if let route = firstMatch("\\b([A-Z]{3})\\s*[-\u{2013}]\\s*([A-Z]{3})\\b", in: place) {
                    if flight.origin == nil { flight.origin = KmlAirport(iata: route[1]) }
                    if flight.destination == nil { flight.destination = KmlAirport(iata: route[2]) }
                    break
                }
            }
        }
        return flight
    }

    // MARK: Description

    private static func read(_ html: String, into flight: inout KmlFlight) {
        // The flight number and the link: ".../flight/xa123", ".../data/flights/xa123" or ".../XA123/3f2a1b9c".
        if flight.flightLink == nil {
            if let match = firstMatch("(https?://(?:www\\.)?flightradar24\\.com/(?:data/)?flights?/([A-Za-z0-9]+))", in: html) {
                flight.flightLink = match[1]
                flight.flightNumber = flight.flightNumber ?? flightNumber(match[2])
            } else if let match = firstMatch("(https?://(?:www\\.)?flightradar24\\.com/([A-Za-z0-9]{2,3}\\d{1,4}[A-Za-z]?)/[0-9a-fA-F]{6,})", in: html) {
                flight.flightLink = match[1]
                flight.flightNumber = flight.flightNumber ?? flightNumber(match[2])
            }
        }
        if flight.registration == nil, let match = firstMatch("/reg/([A-Za-z0-9-]{2,10})", in: html) {
            flight.registration = match[1].uppercased()
        }
        if flight.airline == nil, let match = firstMatch("Airline:\\s*<b>([^<]+)</b>", in: html) { flight.airline = clean(match[1]) }
        if flight.aircraftTypeCode == nil, let match = firstMatch("Aircraft:\\s*<b>([^<]*?)\\s*\\(([A-Za-z0-9]{2,4})\\)\\s*</b>", in: html) {
            flight.aircraftTypeName = nonEmpty(clean(match[1]))
            flight.aircraftTypeCode = match[2].uppercased()
        }

        // The older layout: "From: <b>Name (IATA)</b>", "To: ...", "Departure: <b>YYYY-MM-DD HH:MM</b>".
        if flight.origin == nil, let match = firstMatch("From:\\s*<b>([^<]*?)\\s*\\(([A-Za-z]{3,4})\\)\\s*</b>", in: html) {
            flight.origin = airport(name: match[1], code: match[2])
        }
        if flight.destination == nil, let match = firstMatch("To:\\s*<b>([^<]*?)\\s*\\(([A-Za-z]{3,4})\\)\\s*</b>", in: html) {
            flight.destination = airport(name: match[1], code: match[2])
        }
        if flight.departureDate == nil, let match = firstMatch("Departure:\\s*<b>\\s*(\\d{4}-\\d{2}-\\d{2})(?:[ T]+(\\d{1,2}:\\d{2}))?", in: html) {
            flight.departureDate = match[1]
            if flight.departureTime == nil, !match[2].isEmpty { flight.departureTime = match[2] }
        }

        // The newer layout: airport links with the name in `title`, then `<h3>IATA</h3>` and the city.
        if flight.origin == nil { flight.origin = linkedAirport("departures", in: html) }
        if flight.destination == nil { flight.destination = linkedAirport("arrivals", in: html) }
        if flight.departureTime == nil, let match = firstMatch("ATD\\s+(\\d{1,2}:\\d{2})", in: html) { flight.departureTime = match[1] }
        if flight.arrivalTime == nil, let match = firstMatch("ETA\\s+(\\d{1,2}:\\d{2})", in: html) { flight.arrivalTime = match[1] }
    }

    /// A flight number the server accepts (two letters or digits for the airline, then 1 to 4 digits and maybe a letter), or
    /// nil: the part of a link that is not one, such as an id, is not a flight number.
    private static func flightNumber(_ candidate: String) -> String? {
        let upper = candidate.uppercased()
        return firstMatch("^[A-Z0-9]{2}[0-9]{1,4}[A-Z]?$", in: upper) == nil ? nil : upper
    }

    private static func airport(name: String, code: String) -> KmlAirport {
        var result = KmlAirport(name: nonEmpty(clean(name)))
        if code.count == 3 { result.iata = code.uppercased() } else { result.icao = code.uppercased() }
        return result
    }

    private static func linkedAirport(_ direction: String, in html: String) -> KmlAirport? {
        guard let tag = firstMatch("<a\\s[^>]*href=\"[^\"]*/airports?/([A-Za-z0-9]+)/\(direction)\"[^>]*>", in: html) else { return nil }
        var result = KmlAirport()
        let code = tag[1]
        if code.count == 4 { result.icao = code.uppercased() }
        if let title = firstMatch("title=\"([^\"]*)\"", in: tag[0]) { result.name = nonEmpty(clean(title[1])) }
        let rest = String(html[html.range(of: tag[0])!.upperBound...].prefix(600))
        if let iata = firstMatch("<h3>\\s*([A-Za-z]{3})\\s*</h3>", in: rest) {
            result.iata = iata[1].uppercased()
            if let city = firstMatch("</h3>\\s*<[A-Za-z]+[^>]*>([^<]+)<", in: rest) { result.city = nonEmpty(clean(city[1])) }
        } else if code.count == 3 {
            result.iata = code.uppercased()
        }
        return result.isEmpty ? nil : result
    }

    // MARK: Track

    private static func findTrack(in text: String) -> ([GeoCoordinate], KmlTrackSource) {
        var best: [GeoCoordinate] = []
        for block in elements("coordinates", in: text) {
            let points = parseCoordinates(block)
            if points.count >= minimumLinePoints, points.count > best.count { best = points }
        }
        if !best.isEmpty { return (best, .line) }

        var reports: [(time: String, index: Int, point: GeoCoordinate)] = []
        for (index, placemark) in elements("Placemark", in: text).enumerated() {
            guard let time = elements("when", in: placemark).first?.trimmingCharacters(in: .whitespacesAndNewlines), !time.isEmpty,
                  let point = elements("coordinates", in: placemark).first.flatMap(parseCoordinates)?.first else { continue }
            reports.append((time, index, point))
        }
        if reports.count >= 2 {
            return (reports.sorted { ($0.time, $0.index) < ($1.time, $1.index) }.map(\.point), .placemarks)
        }
        return ([], .none)
    }

    /// `lon,lat[,altitude]` separated by white space. A position that is not a valid coordinate is skipped.
    public static func parseCoordinates(_ text: String) -> [GeoCoordinate] {
        var points: [GeoCoordinate] = []
        for token in text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" || $0 == "\t" }) {
            let parts = token.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count >= 2, let lon = Double(parts[0]), let lat = Double(parts[1]),
                  abs(lon) <= 180, abs(lat) <= 90 else { continue }
            points.append(GeoCoordinate(latitude: lat, longitude: lon))
        }
        return points
    }

    // MARK: Text helpers

    /// The text inside every `<name ...>...</name>`, in file order.
    static func elements(_ name: String, in text: String) -> [String] {
        var result: [String] = []
        var cursor = text.startIndex
        let open = "<\(name)", close = "</\(name)>"
        while let start = text.range(of: open, range: cursor..<text.endIndex) {
            let next = start.upperBound
            guard next < text.endIndex, [">", " ", "\n", "\r", "\t", "/"].contains(text[next]) else { cursor = next; continue }
            guard let tagEnd = text.range(of: ">", range: next..<text.endIndex) else { break }
            if text[text.index(before: tagEnd.lowerBound)] == "/" { cursor = tagEnd.upperBound; continue }
            guard let end = text.range(of: close, range: tagEnd.upperBound..<text.endIndex) else { break }
            result.append(String(text[tagEnd.upperBound..<end.lowerBound]))
            cursor = end.upperBound
        }
        return result
    }

    /// The HTML in a description: the inside of a CDATA section as it is, otherwise the text with its entities decoded.
    private static func descriptionHtml(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let open = trimmed.range(of: "<![CDATA["), let close = trimmed.range(of: "]]>", options: .backwards), open.upperBound <= close.lowerBound {
            return String(trimmed[open.upperBound..<close.lowerBound])
        }
        return unescape(trimmed)
    }

    private static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
    }

    private static func unescape(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        for (entity, value) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")] {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func clean(_ text: String) -> String {
        unescape(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmpty(_ text: String) -> String? { text.isEmpty ? nil : text }

    /// The groups of the first match, with an empty string for a group that did not take part. Index 0 is the whole match.
    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
