package site.wingspot.core

import java.time.Duration
import java.time.Instant
import java.util.UUID
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/**
 * A spotting session: an airport visit at a spotting location, during which new sightings are linked to the visit.
 * It lasts until the person ends it, or [LIFETIME].
 */
data class SpotSession(
    val visitId: UUID, val spotId: Long, val spotName: String, val airportId: Long, val code: String, val startedAt: Instant,
    /** For a backdated visit: its day (and time), which the sightings of the session start with. Null: they happen now. */
    val visitMoment: Instant? = null, val visitTimeKnown: Boolean = true,
) {
    fun isActive(now: Instant): Boolean = Duration.between(startedAt, now) < LIFETIME

    fun encode(): String = buildJsonObject {
        put("visit", visitId.toString()); put("spot", spotId); put("name", spotName)
        put("airport", airportId); put("code", code); put("started", startedAt.toEpochMilli())
        visitMoment?.let { put("moment", it.toEpochMilli()); put("moment_known", visitTimeKnown) }
    }.toString()

    companion object {
        val LIFETIME: Duration = Duration.ofHours(12)

        /** The session saved by [encode], or null for nothing, damage or anything unexpected. */
        fun decode(text: String?): SpotSession? {
            if (text.isNullOrBlank()) return null
            return runCatching {
                val o: JsonObject = Json.parseToJsonElement(text).jsonObject
                SpotSession(
                    UUID.fromString(o.getValue("visit").jsonPrimitive.content), o.getValue("spot").jsonPrimitive.content.toLong(),
                    o.getValue("name").jsonPrimitive.content, o.getValue("airport").jsonPrimitive.content.toLong(),
                    o.getValue("code").jsonPrimitive.content, Instant.ofEpochMilli(o.getValue("started").jsonPrimitive.content.toLong()),
                    o["moment"]?.jsonPrimitive?.content?.toLongOrNull()?.let(Instant::ofEpochMilli),
                    o["moment_known"]?.jsonPrimitive?.content != "false",
                )
            }.getOrNull()
        }
    }
}
