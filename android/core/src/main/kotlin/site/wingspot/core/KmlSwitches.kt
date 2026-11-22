package site.wingspot.core

/**
 * The KML import switches in the server's `feature_flags`. Unlike other flags, a missing one counts as **on**, so a
 * server that does not list them leaves the import as it is. See docs/KML-IMPORT-PLAN.md.
 */
data class KmlSwitches(val importOn: Boolean, val keepRoutes: Boolean) {
    companion object {
        fun from(flags: Map<String, Boolean>) = KmlSwitches(flags["kml_import"] ?: true, flags["kml_tracks_keep"] ?: true)
    }
}
