/// ICAO nationality prefixes of aircraft registers.
///
/// Prefixes are one to four characters long (`D`, `HB`, `9XR`, `RDPL`). The prefixes `VP`, `VQ` and `VR` are shared
/// by British territories and resolved by the first letter of the mark.
struct NationalityPrefix: Sendable {
    let country: String
    /// Whether the canonical form has a dash after the prefix (`D-AIMA`) or not (`N123AB`, `JA8089`).
    let usesDash: Bool

    func countryCode(for mark: String) -> String {
        // `B` is shared by China, Hong Kong, Macau and Taiwan.
        if country == "VP" {
            switch mark.first {
            case "A": return "AI"
            case "B": return "BM"
            case "C": return "KY"
            case "F": return "FK"
            case "G": return "GI"
            case "H": return "SH"
            case "L": return "VG"
            case "M": return "MS"
            case "T": return "TC"
            default: return "GB"
            }
        }
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
            "3A": "MC", "3B": "MU", "3C": "GQ", "3D": "SZ", "3X": "GN", "4K": "AZ",
            "4L": "GE", "4O": "ME", "4R": "LK", "4W": "TL", "4X": "IL", "5A": "LY",
            "5B": "CY", "5H": "TZ", "5N": "NG", "5R": "MG", "5T": "MR", "5U": "NE",
            "5V": "TG", "5W": "WS", "5X": "UG", "5Y": "KE", "6O": "SO", "6V": "SN",
            "6W": "SN", "6Y": "JM", "7O": "YE", "7P": "LS", "7Q": "MW", "7T": "DZ",
            "8P": "BB", "8Q": "MV", "8R": "GY", "9A": "HR", "9G": "GH", "9H": "MT",
            "9J": "ZM", "9K": "KW", "9L": "SL", "9M": "MY", "9N": "NP", "9Q": "CD",
            "9U": "BI", "9V": "SG", "9XR": "RW", "9Y": "TT", "A2": "BW", "A3": "TO",
            "A4O": "OM", "A5": "BT", "A6": "AE", "A7": "QA", "A8": "LR", "A9C": "BH",
            "AP": "PK", "B": "CN", "C": "CA", "C2": "NR", "C3": "AD", "C5": "GM",
            "C6": "BS", "C9": "MZ", "CC": "CL", "CN": "MA", "CP": "BO", "CS": "PT",
            "CU": "CU", "CX": "UY", "D": "DE", "D2": "AO", "D4": "CV", "D6": "KM",
            "E3": "ER", "E5": "CK", "E7": "BA", "EC": "ES", "EI": "IE", "EJ": "IE",
            "EK": "AM", "EP": "IR", "ER": "MD", "ES": "EE", "ET": "ET", "EW": "BY",
            "EX": "KG", "EY": "TJ", "EZ": "TM", "F": "FR", "G": "GB", "H4": "SB",
            "HA": "HU", "HB": "CH", "HC": "EC", "HH": "HT", "HI": "DO", "HK": "CO",
            "HL": "KR", "HP": "PA", "HR": "HN", "HS": "TH", "HV": "VA", "HZ": "SA",
            "I": "IT", "J2": "DJ", "J3": "GD", "J5": "GW", "J6": "LC", "J7": "DM",
            "J8": "VC", "JA": "JP", "JY": "JO", "LN": "NO", "LQ": "AR", "LV": "AR",
            "LW": "AR", "LX": "LU", "LY": "LT", "LZ": "BG", "M": "IM", "N": "US",
            "OB": "PE", "OD": "LB", "OE": "AT", "OH": "FI", "OK": "CZ", "OM": "SK",
            "OO": "BE", "OY": "DK", "P": "KP", "P2": "PG", "P4": "AW", "PH": "NL",
            "PJ": "CW", "PK": "ID", "PP": "BR", "PR": "BR", "PS": "BR", "PT": "BR",
            "PU": "BR", "PZ": "SR", "RA": "RU", "RDPL": "LA", "RF": "RU", "RP": "PH",
            "S2": "BD", "S5": "SI", "S7": "SC", "S9": "ST", "SE": "SE", "SP": "PL",
            "ST": "SD", "SU": "EG", "SX": "GR", "T2": "TV", "T3": "KI", "T7": "SM",
            "T8A": "PW", "TC": "TR", "TF": "IS", "TG": "GT", "TI": "CR", "TJ": "CM",
            "TL": "CF", "TN": "CG", "TR": "GA", "TS": "TN", "TT": "TD", "TU": "CI",
            "TY": "BJ", "TZ": "ML", "UK": "UZ", "UN": "KZ", "UP": "KZ", "UR": "UA",
            "V2": "AG", "V3": "BZ", "V4": "KN", "V5": "NA", "V6": "FM", "V7": "MH",
            "V8": "BN", "VH": "AU", "VN": "VN", "VP": "VP", "VQ": "VP", "VR": "VP",
            "VT": "IN", "XA": "MX", "XB": "MX", "XC": "MX", "XT": "BF", "XU": "KH",
            "XW": "LA", "XY": "MM", "XZ": "MM", "YA": "AF", "YI": "IQ", "YJ": "VU",
            "YK": "SY", "YL": "LV", "YN": "NI", "YR": "RO", "YS": "SV", "YU": "RS",
            "YV": "VE", "Z": "ZW", "Z3": "MK", "Z8": "SS", "ZA": "AL", "ZK": "NZ",
            "ZP": "PY", "ZS": "ZA", "ZT": "ZA", "ZU": "ZA",
        ]
        return countries.reduce(into: [:]) { result, item in
            result[item.key] = NationalityPrefix(country: item.value, usesDash: !withoutDash.contains(item.key))
        }
    }()
}
