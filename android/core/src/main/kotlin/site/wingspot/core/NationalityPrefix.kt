package site.wingspot.core

/** ICAO nationality prefixes of aircraft registers, ported from the iPhone app's `NationalityPrefix.swift`. */
internal data class NationalityPrefix(val country: String, val usesDash: Boolean) {
    fun countryCode(mark: String): String {
        // `B` is shared by China, Hong Kong, Macau and Taiwan.
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
        "B" to "CN", "C" to "CA", "D" to "DE", "F" to "FR", "G" to "GB", "I" to "IT",
        "M" to "IM", "N" to "US", "A2" to "BW", "A3" to "TO", "A5" to "BT", "A6" to "AE",
        "A7" to "QA", "AP" to "PK", "CC" to "CL", "CN" to "MA", "CP" to "BO", "CS" to "PT",
        "CU" to "CU", "CX" to "UY", "C5" to "GM", "C6" to "BS", "C9" to "MZ", "D2" to "AO",
        "D4" to "CV", "EC" to "ES", "EI" to "IE", "EK" to "AM", "EP" to "IR", "ER" to "MD",
        "ES" to "EE", "ET" to "ET", "EW" to "BY", "EX" to "KG", "EY" to "TJ", "EZ" to "TM",
        "HA" to "HU", "HB" to "CH", "HC" to "EC", "HH" to "HT", "HI" to "DO", "HK" to "CO",
        "HL" to "KR", "HP" to "PA", "HR" to "HN", "HS" to "TH", "HZ" to "SA", "JA" to "JP",
        "JY" to "JO", "LN" to "NO", "LV" to "AR", "LX" to "LU", "LY" to "LT", "LZ" to "BG",
        "OB" to "PE", "OD" to "LB", "OE" to "AT", "OH" to "FI", "OK" to "CZ", "OM" to "SK",
        "OO" to "BE", "OY" to "DK", "PH" to "NL", "PK" to "ID", "PP" to "BR", "PR" to "BR",
        "PS" to "BR", "PT" to "BR", "PU" to "BR", "PZ" to "SR", "RA" to "RU", "RP" to "PH",
        "SE" to "SE", "SP" to "PL", "ST" to "SD", "SU" to "EG", "SX" to "GR", "S2" to "BD",
        "S5" to "SI", "S7" to "SC", "TC" to "TR", "TF" to "IS", "TG" to "GT", "TI" to "CR",
        "TS" to "TN", "T7" to "SM", "UK" to "UZ", "UN" to "KZ", "UP" to "KZ", "UR" to "UA",
        "VH" to "AU", "VN" to "VN", "VT" to "IN", "XA" to "MX", "XB" to "MX", "XC" to "MX",
        "XU" to "KH", "XY" to "MM", "YA" to "AF", "YI" to "IQ", "YK" to "SY", "YL" to "LV",
        "YR" to "RO", "YS" to "SV", "YU" to "RS", "YV" to "VE", "ZA" to "AL", "ZK" to "NZ",
        "ZP" to "PY", "ZS" to "ZA", "Z3" to "MK", "3A" to "MC", "3B" to "MU", "4K" to "AZ",
        "4L" to "GE", "4O" to "ME", "4R" to "LK", "4X" to "IL", "5A" to "LY", "5B" to "CY",
        "5H" to "TZ", "5N" to "NG", "5R" to "MG", "5T" to "MR", "5U" to "NE", "5X" to "UG",
        "5Y" to "KE", "6O" to "SO", "6V" to "SN", "6Y" to "JM", "7O" to "YE", "7P" to "LS",
        "7Q" to "MW", "7T" to "DZ", "8P" to "BB", "8Q" to "MV", "8R" to "GY", "9A" to "HR",
        "9G" to "GH", "9H" to "MT", "9J" to "ZM", "9K" to "KW", "9L" to "SL", "9M" to "MY",
        "9N" to "NP", "9Q" to "CD", "9V" to "SG", "9Y" to "TT",
        )

        val all: Map<String, NationalityPrefix> =
            countries.mapValues { (prefix, country) -> NationalityPrefix(country, prefix !in withoutDash) }
    }
}
