import Testing
@testable import WingspotCore

struct RegistrationVector: Decodable, Sendable, CustomTestStringConvertible {
    let input: String
    let expected: String?
    let country: String?

    var testDescription: String { "\"\(input)\" → \(expected ?? "invalid")" }
}

struct RegistrationVectors: Decodable { let cases: [RegistrationVector] }

@Suite struct RegistrationTests {
    static let vectors = TestVectors.load("registrations", as: RegistrationVectors.self).cases

    @Test(arguments: vectors)
    func normalizes(_ vector: RegistrationVector) {
        let registration = Registration(vector.input)
        #expect(registration?.value == vector.expected)
        if let country = vector.country {
            #expect(registration?.countryCode == country)
        }
    }

    @Test func exposesPrefix() {
        #expect(Registration("hbjna")?.prefix == "HB")
        #expect(Registration("DAIMA")?.prefix == "D")
    }
}
