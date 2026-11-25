import Foundation
import Testing
@testable import WingspotCore

@Test func aKmlFileIsRecognisedByItsExtension() {
    #expect(KmlFile.isKml(URL(fileURLWithPath: "/tmp/LH400.kml")))
    #expect(KmlFile.isKml(URL(fileURLWithPath: "/tmp/LH400.KML")))
}

@Test func otherFilesAndLinksAreNot() {
    #expect(!KmlFile.isKml(URL(fileURLWithPath: "/tmp/track.kmz")))
    #expect(!KmlFile.isKml(URL(fileURLWithPath: "/tmp/track.gpx")))
    #expect(!KmlFile.isKml(URL(fileURLWithPath: "/tmp/kml")))
    #expect(!KmlFile.isKml(URL(string: "https://example.test/flight.kml")!))
    #expect(!KmlFile.isKml(URL(string: "wingspot://auth-callback")!))
}
