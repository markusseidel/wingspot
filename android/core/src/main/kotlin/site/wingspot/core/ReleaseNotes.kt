package site.wingspot.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer

/** The "What's new" text of one build of the app. German is optional; English is always there. */
@Serializable
data class ReleaseNote(
    val id: String,
    val version: String,
    val build: Long,
    /** `beta` or `release`. */
    val kind: String = "beta",
    @SerialName("title_en") val titleEn: String,
    @SerialName("body_en") val bodyEn: String,
    @SerialName("title_de") val titleDe: String? = null,
    @SerialName("body_de") val bodyDe: String? = null,
    @SerialName("released_at") val releasedAt: String? = null,
) {
    val isBeta: Boolean get() = kind == "beta"

    /** The title and the lines of the text in [language] (`de` or anything else), English when there is no translation. */
    fun text(language: String): Pair<String, List<String>> =
        if (language == "de" && !titleDe.isNullOrBlank() && !bodyDe.isNullOrBlank()) titleDe to linesOf(bodyDe) else titleEn to linesOf(bodyEn)

    /** The day of the release, `2026-11-23`, or null when the server sent no date. */
    val day: String? get() = releasedAt?.take(10)?.takeIf { it.length == 10 }

    companion object {
        /** The text as lines, without the leading "- " of a bullet. Empty lines are dropped. */
        fun linesOf(body: String): List<String> =
            body.lines().map { it.trim().removePrefix("- ").trim() }.filter { it.isNotEmpty() }
    }
}

/** The notes as the screen shows them: builds newer than the installed one (what the next update brings), then the rest. */
data class ReleaseNoteGroups(val newer: List<ReleaseNote>, val installedAndOlder: List<ReleaseNote>)

fun groupReleaseNotes(all: List<ReleaseNote>, installedBuild: Long): ReleaseNoteGroups {
    val sorted = all.sortedByDescending { it.build }
    return ReleaseNoteGroups(sorted.filter { it.build > installedBuild }, sorted.filter { it.build <= installedBuild })
}

/** `get_release_notes` for Android. Works signed out too. */
class ReleaseNotesApi(private val rest: Rest) {
    suspend fun fetch(): List<ReleaseNote> = rest.json.decodeFromString(
        ListSerializer(ReleaseNote.serializer()),
        rest.callPublic("POST", "/rest/v1/rpc/get_release_notes", """{"p_platform":"android"}"""),
    )

    /** The list as the phone keeps it, so the screen opens offline: the same JSON the server sends. */
    fun encode(items: List<ReleaseNote>): String = rest.json.encodeToString(ListSerializer(ReleaseNote.serializer()), items)

    fun decode(text: String): List<ReleaseNote> = runCatching { rest.json.decodeFromString(ListSerializer(ReleaseNote.serializer()), text) }.getOrDefault(emptyList())
}
