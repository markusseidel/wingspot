import Testing
@testable import WingspotCore

@Test func aQuickActionIsReadFromItsType() {
    #expect(QuickAction(type: "site.wingspot.quick.spotted") == .spotted)
    #expect(QuickAction(type: "site.wingspot.quick.flown") == .flown)
    #expect(QuickAction(type: "site.wingspot.quick.airport") == .airport)
    #expect(QuickAction(type: "site.wingspot.quick.session") == .session)
}

@Test func anUnknownTypeIsIgnored() {
    #expect(QuickAction(type: "site.wingspot.quick.feed") == nil)
    #expect(QuickAction(type: "com.other.spotted") == nil)
    #expect(QuickAction(type: "") == nil)
}

@Test func everyActionRoundTripsThroughItsType() {
    for action in QuickAction.allCases { #expect(QuickAction(type: action.type) == action) }
}
