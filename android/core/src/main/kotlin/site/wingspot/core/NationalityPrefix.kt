package site.wingspot.core

/** ICAO nationality prefixes of aircraft registers, ported from the iPhone app's `NationalityPrefix.swift`. */
internal data class NationalityPrefix(val country: String, val usesDash: Boolean) {
    fun countryCode(mark: String): String {
        // `B` is shared by China, Hong Kong, Macau and Taiwan.
        if (country == "VP") {
            return when (mark.firstOrNull()) {
                'A' -> "AI"; 'B' -> "BM"; 'C' -> "KY"; 'F' -> "FK"; 'G' -> "GI"; 'H' -> "SH"
                'L' -> "VG"; 'M' -> "MS"; 'T' -> "TC"; else -> "GB"
            }
        }
        if (country != "CN") return country
        return when (mark.firstOrNull()) {
            'H', 'K', 'L' -> "HK"
            'M' -> "MO"
            else -> if (mark.length == 5 && mark.all { it.isDigit() }) "TW" else "CN"
        }
    }

    companion object {
        private val withoutDash = setOf("N", "JA", "HL")

        private val countries: Map<String, String> = mapOf(
        "3A" to "MC", "3B" to "MU", "3C" to "GQ", "3D" to "SZ", "3X" to "GN", "4K" to "AZ",
        "4L" to "GE", "4O" to "ME", "4R" to "LK", "4W" to "TL", "4X" to "IL", "5A" to "LY",
        "5B" to "CY", "5H" to "TZ", "5N" to "NG", "5R" to "MG", "5T" to "MR", "5U" to "NE",
        "5V" to "TG", "5W" to "WS", "5X" to "UG", "5Y" to "KE", "6O" to "SO", "6V" to "SN",
        "6W" to "SN", "6Y" to "JM", "7O" to "YE", "7P" to "LS", "7Q" to "MW", "7T" to "DZ",
        "8P" to "BB", "8Q" to "MV", "8R" to "GY", "9A" to "HR", "9G" to "GH", "9H" to "MT",
        "9J" to "ZM", "9K" to "KW", "9L" to "SL", "9M" to "MY", "9N" to "NP", "9Q" to "CD",
        "9U" to "BI", "9V" to "SG", "9XR" to "RW", "9Y" to "TT", "A2" to "BW", "A3" to "TO",
        "A4O" to "OM", "A5" to "BT", "A6" to "AE", "A7" to "QA", "A8" to "LR", "A9C" to "BH",
        "AP" to "PK", "B" to "CN", "C" to "CA", "C2" to "NR", "C3" to "AD", "C5" to "GM",
        "C6" to "BS", "C9" to "MZ", "CC" to "CL", "CN" to "MA", "CP" to "BO", "CS" to "PT",
        "CU" to "CU", "CX" to "UY", "D" to "DE", "D2" to "AO", "D4" to "CV", "D6" to "KM",
        "E3" to "ER", "E5" to "CK", "E7" to "BA", "EC" to "ES", "EI" to "IE", "EJ" to "IE",
        "EK" to "AM", "EP" to "IR", "ER" to "MD", "ES" to "EE", "ET" to "ET", "EW" to "BY",
        "EX" to "KG", "EY" to "TJ", "EZ" to "TM", "F" to "FR", "G" to "GB", "H4" to "SB",
        "HA" to "HU", "HB" to "CH", "HC" to "EC", "HH" to "HT", "HI" to "DO", "HK" to "CO",
        "HL" to "KR", "HP" to "PA", "HR" to "HN", "HS" to "TH", "HV" to "VA", "HZ" to "SA",
        "I" to "IT", "J2" to "DJ", "J3" to "GD", "J5" to "GW", "J6" to "LC", "J7" to "DM",
        "J8" to "VC", "JA" to "JP", "JY" to "JO", "LN" to "NO", "LQ" to "AR", "LV" to "AR",
        "LW" to "AR", "LX" to "LU", "LY" to "LT", "LZ" to "BG", "M" to "IM", "N" to "US",
        "OB" to "PE", "OD" to "LB", "OE" to "AT", "OH" to "FI", "OK" to "CZ", "OM" to "SK",
        "OO" to "BE", "OY" to "DK", "P" to "KP", "P2" to "PG", "P4" to "AW", "PH" to "NL",
        "PJ" to "CW", "PK" to "ID", "PP" to "BR", "PR" to "BR", "PS" to "BR", "PT" to "BR",
        "PU" to "BR", "PZ" to "SR", "RA" to "RU", "RDPL" to "LA", "RF" to "RU", "RP" to "PH",
        "S2" to "BD", "S5" to "SI", "S7" to "SC", "S9" to "ST", "SE" to "SE", "SP" to "PL",
        "ST" to "SD", "SU" to "EG", "SX" to "GR", "T2" to "TV", "T3" to "KI", "T7" to "SM",
        "T8A" to "PW", "TC" to "TR", "TF" to "IS", "TG" to "GT", "TI" to "CR", "TJ" to "CM",
        "TL" to "CF", "TN" to "CG", "TR" to "GA", "TS" to "TN", "TT" to "TD", "TU" to "CI",
        "TY" to "BJ", "TZ" to "ML", "UK" to "UZ", "UN" to "KZ", "UP" to "KZ", "UR" to "UA",
        "V2" to "AG", "V3" to "BZ", "V4" to "KN", "V5" to "NA", "V6" to "FM", "V7" to "MH",
        "V8" to "BN", "VH" to "AU", "VN" to "VN", "VP" to "VP", "VQ" to "VP", "VR" to "VP",
        "VT" to "IN", "XA" to "MX", "XB" to "MX", "XC" to "MX", "XT" to "BF", "XU" to "KH",
        "XW" to "LA", "XY" to "MM", "XZ" to "MM", "YA" to "AF", "YI" to "IQ", "YJ" to "VU",
        "YK" to "SY", "YL" to "LV", "YN" to "NI", "YR" to "RO", "YS" to "SV", "YU" to "RS",
        "YV" to "VE", "Z" to "ZW", "Z3" to "MK", "Z8" to "SS", "ZA" to "AL", "ZK" to "NZ",
        "ZP" to "PY", "ZS" to "ZA", "ZT" to "ZA", "ZU" to "ZA",
        )

        val all: Map<String, NationalityPrefix> =
            countries.mapValues { (prefix, country) -> NationalityPrefix(country, prefix !in withoutDash) }
    }
}
