import Testing
import WingspotCore

@Test func anOlderVersionNeedsAnUpdate() {
    #expect(AppVersion.needsUpdate(installed: "0.2.0", minimum: "0.3.0"))
    #expect(AppVersion.needsUpdate(installed: "0.9.0", minimum: "0.10.0"))
    #expect(AppVersion.needsUpdate(installed: "0.3", minimum: "0.3.1"))
}

@Test func theSameOrANewerVersionDoesNot() {
    #expect(!AppVersion.needsUpdate(installed: "0.3.0", minimum: "0.3.0"))
    #expect(!AppVersion.needsUpdate(installed: "0.3", minimum: "0.3.0"))
    #expect(!AppVersion.needsUpdate(installed: "1.0.0", minimum: "0.10.0"))
}

@Test func whatCannotBeReadNeverAsksForAnUpdate() {
    #expect(!AppVersion.needsUpdate(installed: "0.2.0", minimum: nil))
    #expect(!AppVersion.needsUpdate(installed: "0.2.0", minimum: ""))
    #expect(!AppVersion.needsUpdate(installed: "0.2.0", minimum: "1.x"))
    #expect(!AppVersion.needsUpdate(installed: nil, minimum: "9.0.0"))
    #expect(!AppVersion.needsUpdate(installed: "0.2.0", minimum: "1..0"))
}
