package site.wingspot.core

import java.security.SecureRandom
import java.util.UUID

/** A time-ordered UUID (RFC 9562), made on the phone so that retrying an upload can't create a duplicate. */
object Uuid7 {
    private val random = SecureRandom()

    fun generate(timeMillis: Long = System.currentTimeMillis()): UUID {
        val bytes = ByteArray(16).also(random::nextBytes)
        for (i in 0 until 6) bytes[i] = (timeMillis shr ((5 - i) * 8)).toByte()
        bytes[6] = ((bytes[6].toInt() and 0x0F) or 0x70).toByte()
        bytes[8] = ((bytes[8].toInt() and 0x3F) or 0x80).toByte()
        var high = 0L
        var low = 0L
        for (i in 0 until 8) high = (high shl 8) or (bytes[i].toLong() and 0xFF)
        for (i in 8 until 16) low = (low shl 8) or (bytes[i].toLong() and 0xFF)
        return UUID(high, low)
    }
}
