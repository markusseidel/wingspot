package site.wingspot.core

/** Which files shared or opened into the app are read as a flight track (#236). */
object KmlFile {
    const val MIME = "application/vnd.google-earth.kml+xml"

    /**
     * A KML file: its type says so, or its name ends in `.kml` (other apps often hand over a plain binary type). A KMZ (zipped), a GPX
     * and anything else is not.
     */
    fun looksLikeKml(mimeType: String?, name: String?): Boolean =
        mimeType.equals(MIME, ignoreCase = true) || name?.trim()?.endsWith(".kml", ignoreCase = true) == true
}
