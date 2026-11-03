import Foundation

extension BoardingPass {
    /// Parses the text content of a BCBP barcode (PDF417, Aztec or QR).
    public init(barcode: String) throws(BCBPError) {
        var scanner = FieldScanner(barcode)

        guard try scanner.take(1) == "M" else { throw .invalidFormatCode }
        guard let legCount = Int(try scanner.take(1)), (1...4).contains(legCount) else { throw .invalidLegCount }
        try scanner.skip(20)  // passenger name
        try scanner.skip(1)   // electronic ticket indicator

        var legs: [Leg] = []
        var version: String?
        for index in 0..<legCount {
            try scanner.skip(7)  // PNR
            let from = try scanner.airportCode("from")
            let to = try scanner.airportCode("to")
            let carrier = try scanner.take(3).trimmed
            let flightNumber = try scanner.take(5).trimmed.droppingLeadingZeros
            guard let dayOfYear = Int(try scanner.take(3)), (1...366).contains(dayOfYear) else {
                throw .invalidField("dateOfFlight")
            }
            let compartmentCode = try scanner.take(1).trimmed
            let seat = try scanner.take(4).trimmed.droppingLeadingZeros
            try scanner.skip(5)  // check-in sequence number
            try scanner.skip(1)  // passenger status
            guard let conditionalSize = Int(try scanner.take(2), radix: 16) else { throw .invalidField("fieldSize") }
            let conditional = try scanner.take(conditionalSize)

            if index == 0, conditional.first == ">", conditional.count >= 2 {
                version = String(conditional.dropFirst().prefix(1))
            }
            guard !carrier.isEmpty, !flightNumber.isEmpty else { throw .invalidField("flight") }
            legs.append(Leg(from: from, to: to, carrier: carrier, flightNumber: flightNumber, dayOfYear: dayOfYear,
                            compartmentCode: compartmentCode, seat: seat.isEmpty ? nil : seat))
        }
        // Anything after the legs (security data, airline use) is ignored.
        self.init(version: version, legs: legs)
    }
}

private struct FieldScanner {
    private var rest: Substring

    init(_ text: String) { rest = Substring(text) }

    mutating func take(_ length: Int) throws(BCBPError) -> Substring {
        guard rest.count >= length else { throw .truncated }
        defer { rest = rest.dropFirst(length) }
        return rest.prefix(length)
    }

    mutating func skip(_ length: Int) throws(BCBPError) {
        _ = try take(length)
    }

    mutating func airportCode(_ field: String) throws(BCBPError) -> String {
        let code = try take(3)
        guard code.allSatisfy({ $0.isASCII && $0.isLetter }) else { throw .invalidField(field) }
        return String(code)
    }
}

private extension Substring {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}

private extension String {
    /// `0400` → `400`, `0032A` → `32A`, `034K` → `34K`, `0000` → `0`.
    var droppingLeadingZeros: String {
        guard first == "0" else { return self }
        let stripped = drop(while: { $0 == "0" })
        return stripped.first?.isNumber == true ? String(stripped) : "0" + stripped
    }
}
