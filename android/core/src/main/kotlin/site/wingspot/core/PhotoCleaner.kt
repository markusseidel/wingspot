package site.wingspot.core

/**
 * Makes sure a JPEG carries no metadata, because the server refuses a photo with EXIF or XMP (which can hold a location).
 * Kept: the JFIF header (E0), the colour profile (E2) and Adobe's colour flag (EE). Everything else before the
 * picture data is cut out. Not a JPEG: returned unchanged.
 */
object PhotoCleaner {
    /** The server refuses anything above 3 MB. */
    const val MAX_BYTES = 2_900_000

    /** The long side of a stored photo, in pixels. */
    const val MAX_PIXELS = 2048

    fun removeMetadata(jpeg: ByteArray): ByteArray {
        if (jpeg.size <= 4 || jpeg[0] != 0xFF.toByte() || jpeg[1] != 0xD8.toByte()) return jpeg
        val out = java.io.ByteArrayOutputStream(jpeg.size)
        out.write(0xFF); out.write(0xD8)
        var i = 2
        while (i + 4 <= jpeg.size && jpeg[i] == 0xFF.toByte()) {
            val marker = jpeg[i + 1].toInt() and 0xFF
            if (marker == 0xFF) { i += 1; continue }
            if (marker == 0xDA) break // the picture data starts here
            val length = (jpeg[i + 2].toInt() and 0xFF shl 8) or (jpeg[i + 3].toInt() and 0xFF)
            if (length < 2 || i + 2 + length > jpeg.size) return jpeg
            if (marker in KEPT) out.write(jpeg, i, 2 + length)
            i += 2 + length
        }
        out.write(jpeg, i, jpeg.size - i)
        return out.toByteArray()
    }

    private val KEPT = setOf(0xE0, 0xE2, 0xEE, 0xDB, 0xC0, 0xC1, 0xC2, 0xC4, 0xDD)
}
