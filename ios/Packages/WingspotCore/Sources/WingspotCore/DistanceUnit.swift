import Foundation

/// How distances are shown. The database always stores kilometres.
public enum DistanceUnit: String, CaseIterable, Sendable {
    case kilometres = "km"
    case nauticalMiles = "nm"
    case miles = "mi"

    /// A distance in this unit, rounded to whole numbers.
    public func value(km: Int) -> Int {
        switch self {
        case .kilometres: km
        case .nauticalMiles: Int((Double(km) / 1.852).rounded())
        case .miles: Int((Double(km) / 1.609344).rounded())
        }
    }

    public var symbol: String {
        switch self {
        case .kilometres: "km"
        case .nauticalMiles: "NM"
        case .miles: "mi"
        }
    }

    /// For example `1,234 NM`, with the number written the way the phone's language does.
    public func format(km: Int) -> String {
        "\(value(km: km).formatted()) \(symbol)"
    }
}
