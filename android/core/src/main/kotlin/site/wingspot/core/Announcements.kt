package site.wingspot.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer

/** A short message from the project owner, shown at the top of the Feed. German is optional; English is always there. */
@Serializable
data class Announcement(
    val id: String,
    @SerialName("title_en") val titleEn: String,
    @SerialName("body_en") val bodyEn: String,
    @SerialName("title_de") val titleDe: String? = null,
    @SerialName("body_de") val bodyDe: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("expires_at") val expiresAt: String? = null,
) {
    /** The title and text in [language] (`de` or anything else), English when there is no translation. */
    fun text(language: String): Pair<String, String> =
        if (language == "de" && !titleDe.isNullOrBlank() && !bodyDe.isNullOrBlank()) titleDe to bodyDe else titleEn to bodyEn
}

/** What to show: the announcements the person hasn't dismissed, newest first. Dismissals are remembered by id. */
fun visibleAnnouncements(all: List<Announcement>, dismissed: Set<String>): List<Announcement> = all.filter { it.id !in dismissed }

/** `get_announcements`. Works signed out too. */
class AnnouncementsApi(private val rest: Rest) {
    suspend fun fetch(): List<Announcement> = rest.json.decodeFromString(
        ListSerializer(Announcement.serializer()),
        rest.callPublic("POST", "/rest/v1/rpc/get_announcements", "{}"),
    )

    /** The list as the phone keeps it, so the card shows offline: the same JSON the server sends. */
    fun encode(items: List<Announcement>): String = rest.json.encodeToString(ListSerializer(Announcement.serializer()), items)

    fun decode(text: String): List<Announcement> = runCatching { rest.json.decodeFromString(ListSerializer(Announcement.serializer()), text) }.getOrDefault(emptyList())
}
