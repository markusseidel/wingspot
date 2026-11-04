import Foundation
import Testing
import WingspotCore

@Test func uuidV7HasTheRightVersionAndVariant() {
    let text = UUID.v7().uuidString
    let characters = Array(text)
    #expect(characters[14] == "7")
    #expect(["8", "9", "A", "B"].contains(characters[19]))
}

@Test func uuidV7StartsWithTheTimestamp() {
    let id = UUID.v7(at: Date(timeIntervalSince1970: 1_645_557_742))
    #expect(id.uuidString.replacingOccurrences(of: "-", with: "").hasPrefix("017F22E279B0"))
}

@Test func laterUUIDsSortAfterEarlierOnes() {
    let earlier = UUID.v7(at: Date(timeIntervalSince1970: 1_000))
    let later = UUID.v7(at: Date(timeIntervalSince1970: 2_000))
    #expect(earlier.uuidString < later.uuidString)
}
