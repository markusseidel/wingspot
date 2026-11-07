import SwiftUI
import WingspotCore

extension DistanceUnit {
    static let storageKey = "distanceUnit"

    /// The unit the person chose in the settings. Kilometres until then.
    static var preferred: DistanceUnit {
        DistanceUnit(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .kilometres
    }

    var title: LocalizedStringKey {
        switch self {
        case .kilometres: "Kilometres"
        case .nauticalMiles: "Nautical miles"
        case .miles: "Miles"
        }
    }
}
