package site.wingspot.core

import java.time.LocalDate

/** Importing several KML files at once (#236): which of them are flights the person already has, or that the same batch has twice. */
object KmlBatch {
    /** A flight as the batch sees it. [link] is the link to the flight in the file: the same link twice is the same flight. */
    data class Entry(val flightNumber: String?, val day: LocalDate?, val link: String? = null)

    /** A flight check-in the person already has. */
    data class Existing(val flightNumber: String?, val day: LocalDate)

    /** The flight number the way it is stored: upper case, no spaces. Empty when there is none. */
    fun normalized(number: String?): String = number.orEmpty().filterNot { it.isWhitespace() }.uppercase()

    /**
     * For each entry, whether it is a flight that is already there: a check-in with the same flight number on the same day, or an earlier
     * entry of the batch with the same link, or the same number on the same day. An entry without a flight number or a day is never a
     * duplicate of anything but its own link.
     */
    fun duplicates(entries: List<Entry>, existing: List<Existing>): List<Boolean> {
        val have = existing.mapNotNull { e -> normalized(e.flightNumber).takeIf { it.isNotEmpty() }?.let { it to e.day } }.toSet()
        val seen = mutableSetOf<Pair<String, LocalDate>>()
        val links = mutableSetOf<String>()
        return entries.map { entry ->
            var duplicate = false
            entry.link?.takeIf { it.isNotEmpty() }?.let { if (!links.add(it)) duplicate = true }
            val number = normalized(entry.flightNumber)
            val day = entry.day
            if (number.isNotEmpty() && day != null) {
                val key = number to day
                if (key in have || !seen.add(key)) duplicate = true
            }
            duplicate
        }
    }
}
