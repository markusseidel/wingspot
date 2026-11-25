package site.wingspot.core

/**
 * What a long press on the app icon can open (#349). [id] is what the shortcut's intent carries (extra `quick_action`) and the shortcut id
 * in `res/xml/shortcuts.xml`.
 */
enum class QuickAction(val id: String) {
    SPOTTED("spotted"), FLOWN("flown"), AIRPORT("airport"),

    /** The entry that is only there while a spotting session runs. It opens the sighting form, which joins the session. */
    SESSION("session");

    companion object {
        /** Null for anything that is not one of ours. */
        fun parse(id: String?): QuickAction? = entries.firstOrNull { it.id == id }
    }
}
