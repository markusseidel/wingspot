import Testing
@testable import WingspotCore

@Test func kilometresStayAsTheyAre() {
    #expect(DistanceUnit.kilometres.value(km: 1000) == 1000)
}

@Test func convertsToNauticalMilesAndMiles() {
    #expect(DistanceUnit.nauticalMiles.value(km: 1000) == 540)
    #expect(DistanceUnit.miles.value(km: 1000) == 621)
    #expect(DistanceUnit.nauticalMiles.value(km: 0) == 0)
}

@Test func formatsWithTheUnitSymbol() {
    #expect(DistanceUnit.kilometres.format(km: 12).hasSuffix(" km"))
    #expect(DistanceUnit.nauticalMiles.format(km: 12).hasSuffix(" NM"))
    #expect(DistanceUnit.miles.format(km: 12).hasSuffix(" mi"))
}

@Test func theStoredNamesAreStable() {
    #expect(DistanceUnit(rawValue: "nm") == .nauticalMiles)
    #expect(DistanceUnit(rawValue: "mi") == .miles)
    #expect(DistanceUnit(rawValue: "km") == .kilometres)
}
