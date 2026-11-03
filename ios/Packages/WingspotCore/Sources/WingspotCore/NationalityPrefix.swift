/// ICAO nationality prefixes of aircraft registers.
///
/// Only one- and two-character prefixes are listed. Prefixes shared by several territories
/// (e.g. `VP`, `VQ`) are left out until the reference data pipeline provides them.
struct NationalityPrefix: Sendable {
    let country: String
    /// Whether the canonical form has a dash after the prefix (`D-AIMA`) or not (`N123AB`, `JA8089`).
    let usesDash: Bool

    func countryCode(for mark: String) -> String {
        // `B` is shared by China, Hong Kong, Macau and Taiwan.
        guard country == "CN" else { return country }
        switch mark.first {
        case "H", "K", "L": return "HK"
        case "M": return "MO"
        default: return mark.count == 5 && mark.allSatisfy(\.isNumber) ? "TW" : "CN"
        }
    }

    static let all: [String: NationalityPrefix] = {
        let withoutDash: Set<String> = ["N", "JA", "HL"]
        let countries: [String: String] = [
            "B": "CN", "C": "CA", "D": "DE", "F": "FR", "G": "GB", "I": "IT", "M": "IM", "N": "US",
            "A2": "BW", "A3": "TO", "A5": "BT", "A6": "AE", "A7": "QA", "AP": "PK",
            "CC": "CL", "CN": "MA", "CP": "BO", "CS": "PT", "CU": "CU", "CX": "UY", "C5": "GM", "C6": "BS", "C9": "MZ",
            "D2": "AO", "D4": "CV",
            "EC": "ES", "EI": "IE", "EK": "AM", "EP": "IR", "ER": "MD", "ES": "EE", "ET": "ET", "EW": "BY",
            "EX": "KG", "EY": "TJ", "EZ": "TM",
            "HA": "HU", "HB": "CH", "HC": "EC", "HH": "HT", "HI": "DO", "HK": "CO", "HL": "KR", "HP": "PA",
            "HR": "HN", "HS": "TH", "HZ": "SA",
            "JA": "JP", "JY": "JO",
            "LN": "NO", "LV": "AR", "LX": "LU", "LY": "LT", "LZ": "BG",
            "OB": "PE", "OD": "LB", "OE": "AT", "OH": "FI", "OK": "CZ", "OM": "SK", "OO": "BE", "OY": "DK",
            "PH": "NL", "PK": "ID", "PP": "BR", "PR": "BR", "PS": "BR", "PT": "BR", "PU": "BR", "PZ": "SR",
            "RA": "RU", "RP": "PH",
            "SE": "SE", "SP": "PL", "ST": "SD", "SU": "EG", "SX": "GR", "S2": "BD", "S5": "SI", "S7": "SC",
            "TC": "TR", "TF": "IS", "TG": "GT", "TI": "CR", "TS": "TN", "T7": "SM",
            "UK": "UZ", "UN": "KZ", "UP": "KZ", "UR": "UA",
            "VH": "AU", "VN": "VN", "VT": "IN",
            "XA": "MX", "XB": "MX", "XC": "MX", "XU": "KH", "XY": "MM",
            "YA": "AF", "YI": "IQ", "YK": "SY", "YL": "LV", "YR": "RO", "YS": "SV", "YU": "RS", "YV": "VE",
            "ZA": "AL", "ZK": "NZ", "ZP": "PY", "ZS": "ZA", "Z3": "MK",
            "3A": "MC", "3B": "MU", "4K": "AZ", "4L": "GE", "4O": "ME", "4R": "LK", "4X": "IL",
            "5A": "LY", "5B": "CY", "5H": "TZ", "5N": "NG", "5R": "MG", "5T": "MR", "5U": "NE", "5X": "UG", "5Y": "KE",
            "6O": "SO", "6V": "SN", "6Y": "JM", "7O": "YE", "7P": "LS", "7Q": "MW", "7T": "DZ",
            "8P": "BB", "8Q": "MV", "8R": "GY",
            "9A": "HR", "9G": "GH", "9H": "MT", "9J": "ZM", "9K": "KW", "9L": "SL", "9M": "MY", "9N": "NP",
            "9Q": "CD", "9V": "SG", "9Y": "TT",
        ]
        return countries.reduce(into: [:]) { result, item in
            result[item.key] = NationalityPrefix(country: item.value, usesDash: !withoutDash.contains(item.key))
        }
    }()
}
