import Foundation
import Testing
import BCBP

struct BCBPVector: Decodable, Sendable, CustomTestStringConvertible {
    struct Expected: Decodable, Sendable {
        struct Leg: Decodable, Sendable {
            let from, to, carrier, flightNumber, compartmentCode, flightDate: String
            let dayOfYear: Int
            let seat: String?
        }
        let version: String?
        let legs: [Leg]
    }

    let name: String
    let barcode: String
    let referenceDate: String
    let expected: Expected?
    let expectedError: String?

    var testDescription: String { name }
}

struct BCBPVectors: Decodable { let cases: [BCBPVector] }

@Suite struct BCBPTests {
    static let vectors = TestVectors.load("bcbp", as: BCBPVectors.self).cases

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func day(_ iso: String) -> Date {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }

    @Test(arguments: vectors)
    func matchesVector(_ vector: BCBPVector) throws {
        if let expectedError = vector.expectedError {
            #expect(throws: BCBPError.self) { try BoardingPass(barcode: vector.barcode) }
            do {
                _ = try BoardingPass(barcode: vector.barcode)
            } catch {
                #expect(error.code == expectedError)
            }
            return
        }

        let expected = try #require(vector.expected)
        let pass = try BoardingPass(barcode: vector.barcode)
        #expect(pass.version == expected.version)
        try #require(pass.legs.count == expected.legs.count)

        for (leg, want) in zip(pass.legs, expected.legs) {
            #expect(leg.from == want.from)
            #expect(leg.to == want.to)
            #expect(leg.carrier == want.carrier)
            #expect(leg.flightNumber == want.flightNumber)
            #expect(leg.dayOfYear == want.dayOfYear)
            #expect(leg.compartmentCode == want.compartmentCode)
            #expect(leg.seat == want.seat)
            #expect(leg.flightDate(near: Self.day(vector.referenceDate), calendar: Self.calendar) == Self.day(want.flightDate))
        }
    }

    @Test func doesNotExposePassengerData() throws {
        let pass = try BoardingPass(barcode: Self.vectors[0].barcode)
        let dump = String(describing: pass)
        #expect(!dump.contains("DOE"))
        #expect(!dump.contains("ABC123"))
    }
}
