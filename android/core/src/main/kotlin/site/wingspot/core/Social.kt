package site.wingspot.core

import java.net.URLEncoder
import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** One check-in as the feed and the check-in page get it from the server. */
@Serializable
data class FeedItem(
    val id: String,
    @SerialName("user_id") val userId: String,
    val username: String,
    @SerialName("display_name") val displayName: String? = null,
    val kind: String,
    /** The time exactly as the server sent it. Paging sends it back unchanged, because rounding it would skip or repeat rows. */
    @SerialName("occurred_at") val occurredAt: String,
    val registration: String? = null,
    @SerialName("type_icao") val typeIcao: String? = null,
    @SerialName("type_name") val typeName: String? = null,
    @SerialName("airport_id") val airportId: Long? = null,
    @SerialName("airport_code") val airportCode: String? = null,
    @SerialName("origin_id") val originId: Long? = null,
    @SerialName("destination_id") val destinationId: Long? = null,
    @SerialName("origin_code") val originCode: String? = null,
    @SerialName("destination_code") val destinationCode: String? = null,
    @SerialName("flight_number") val flightNumber: String? = null,
    @SerialName("distance_km") val distanceKm: Int? = null,
    /** Cabin and seat are only sent for your own check-ins. */
    val cabin: String? = null,
    val seat: String? = null,
    val salutes: Int = 0,
    val comments: Int = 0,
    val saluted: Boolean = false,
) {
    /** The name to show: the display name if there is one. */
    val who: String get() = displayName?.takeIf { it.isNotBlank() } ?: username

    /** What to show as the title. */
    val title: String
        get() = when (kind) {
            "flown" -> "${originCode ?: "?"} → ${destinationCode ?: "?"}"
            "airport" -> airportCode ?: "?"
            else -> registration ?: typeIcao ?: "?"
        }
}

/** Where the next page starts: the time and id of the last check-in so far. */
data class FeedCursor(val time: String, val id: String)

@Serializable
data class Person(
    val id: String,
    val username: String,
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("is_private") val isPrivate: Boolean = false,
) {
    val who: String get() = displayName?.takeIf { it.isNotBlank() } ?: username
}

@Serializable
data class CommentAuthor(val username: String, @SerialName("display_name") val displayName: String? = null)

@Serializable
data class CheckInComment(
    val id: String,
    @SerialName("user_id") val userId: String,
    val body: String,
    @SerialName("created_at") val createdAt: String,
    val profiles: CommentAuthor? = null,
) {
    val who: String get() = profiles?.displayName?.takeIf { it.isNotBlank() } ?: profiles?.username ?: "?"
}

/** A photo on someone's check-in, with a link that works for a while. */
data class FeedPhoto(val id: String, val checkInId: String, val url: String, val width: Int?, val height: Int?)

@Serializable
private data class PhotoRow(
    val id: String,
    @SerialName("checkin_id") val checkInId: String,
    @SerialName("storage_path") val storagePath: String,
    val width: Int? = null,
    val height: Int? = null,
)

/** Who may see your check-ins. The names are what the server stores. */
enum class SharingChoice(val wire: String) { ONLY_ME("private"), FRIENDS("friends"), EVERYONE("public") }

enum class ReportKind(val wire: String) { USER("user"), CHECKIN("checkin"), COMMENT("comment"), PHOTO("photo") }

/** The social features of the server, as the signed-in person: feed, salutes, comments, follows, blocks and reports. */
class SocialApi(private val rest: Rest, private val storageUrl: String) {
    private val json get() = rest.json

    private fun enc(text: String) = URLEncoder.encode(text, "UTF-8")

    private fun feedParams(cursor: FeedCursor?, pageSize: Int, target: String? = null): String = buildJsonObject {
        target?.let { put("target", it) }
        put("before_time", cursor?.time?.let(::JsonPrimitive) ?: kotlinx.serialization.json.JsonNull)
        put("before_id", cursor?.id?.let(::JsonPrimitive) ?: kotlinx.serialization.json.JsonNull)
        put("page_size", pageSize)
    }.toString()

    private fun items(text: String): List<FeedItem> = json.decodeFromString(ListSerializer(FeedItem.serializer()), text)

    suspend fun feed(after: FeedCursor?, pageSize: Int = 30): List<FeedItem> =
        items(rest.call("POST", "/rest/v1/rpc/get_feed", feedParams(after, pageSize)))

    suspend fun personCheckIns(person: String, after: FeedCursor?, pageSize: Int = 30): List<FeedItem> =
        items(rest.call("POST", "/rest/v1/rpc/get_person_checkins", feedParams(after, pageSize, person)))

    /** One check-in by id, or null when it doesn't exist or can't be seen. */
    suspend fun checkIn(id: String): FeedItem? =
        items(rest.call("POST", "/rest/v1/rpc/get_checkin", """{"target":"$id"}""")).firstOrNull()

    // Salutes and comments ---------------------------------------------------------------------------------------------

    suspend fun setSalute(on: Boolean, checkIn: String, me: String) {
        if (on) {
            try {
                rest.call("POST", "/rest/v1/salutes", """{"user_id":"$me","checkin_id":"$checkIn"}""", prefer = "return=minimal")
            } catch (e: ApiException.Failed) {
                if (e.code != "23505") throw e // already saluted
            }
        } else {
            rest.call("DELETE", "/rest/v1/salutes?user_id=eq.$me&checkin_id=eq.$checkIn")
        }
    }

    suspend fun comments(checkIn: String): List<CheckInComment> = json.decodeFromString(
        ListSerializer(CheckInComment.serializer()),
        rest.call("GET", "/rest/v1/comments?select=id,user_id,body,created_at,profiles(username,display_name)&checkin_id=eq.$checkIn&order=created_at.asc"),
    )

    /** Throws [ApiException.Failed] with code `23514` when the word filter or the length limit refuses the text. */
    suspend fun addComment(body: String, checkIn: String, me: String): CheckInComment {
        val payload = buildJsonObject { put("checkin_id", checkIn); put("user_id", me); put("body", body) }.toString()
        val text = rest.call(
            "POST", "/rest/v1/comments?select=id,user_id,body,created_at,profiles(username,display_name)", payload,
            prefer = "return=representation",
        )
        return json.decodeFromString(ListSerializer(CheckInComment.serializer()), text).first()
    }

    suspend fun deleteComment(id: String) {
        rest.call("DELETE", "/rest/v1/comments?id=eq.$id")
    }

    suspend fun report(kind: ReportKind, target: String, reason: String): String {
        val payload = buildJsonObject { put("report_kind", kind.wire); put("report_target", target.lowercase()); put("report_reason", reason) }.toString()
        return json.parseToJsonElement(rest.call("POST", "/rest/v1/rpc/report", payload)).jsonPrimitive.content
    }

    suspend fun deleteCheckIn(id: String) {
        rest.call("POST", "/rest/v1/rpc/delete_checkin", """{"target":"$id"}""")
    }

    // Photos --------------------------------------------------------------------------------------------------------

    /** The photos of these check-ins that the caller may see, in order, with signed links valid for an hour. */
    suspend fun photos(checkIns: List<String>): List<FeedPhoto> {
        if (checkIns.isEmpty()) return emptyList()
        val rows = json.decodeFromString(
            ListSerializer(PhotoRow.serializer()),
            rest.call("GET", "/rest/v1/checkin_photos?select=id,checkin_id,storage_path,width,height,position&checkin_id=in.(${checkIns.joinToString(",")})&order=position.asc"),
        )
        if (rows.isEmpty()) return emptyList()
        val payload = buildJsonObject { put("expiresIn", 3600); put("paths", JsonArray(rows.map { JsonPrimitive(it.storagePath) })) }.toString()
        val signed = json.parseToJsonElement(rest.call("POST", "/storage/v1/object/sign/photos", payload)).jsonArray
            .associate { it.jsonObject["path"]!!.jsonPrimitive.content to it.jsonObject["signedURL"]?.jsonPrimitive?.content }
        return rows.mapNotNull { row ->
            val link = signed[row.storagePath] ?: return@mapNotNull null
            FeedPhoto(row.id, row.checkInId, storageUrl.trimEnd('/') + link, row.width, row.height)
        }
    }

    // People --------------------------------------------------------------------------------------------------------

    suspend fun searchPeople(text: String, me: String, limit: Int = 20): List<Person> = json.decodeFromString(
        ListSerializer(Person.serializer()),
        rest.call("GET", "/rest/v1/profiles?select=id,username,display_name,is_private&username=ilike.*${enc(text.trim())}*&id=neq.$me&order=username.asc&limit=$limit"),
    )

    suspend fun person(id: String): Person? = json.decodeFromString(
        ListSerializer(Person.serializer()),
        rest.call("GET", "/rest/v1/profiles?select=id,username,display_name,is_private&id=eq.$id"),
    ).firstOrNull()

    /** The people [me] follows, and the people who follow [me]. */
    suspend fun relations(me: String): Pair<Set<String>, Set<String>> {
        fun ids(text: String, key: String) = json.parseToJsonElement(text).jsonArray.map { it.jsonObject[key]!!.jsonPrimitive.content }.toSet()
        val following = ids(rest.call("GET", "/rest/v1/follows?select=follower,followee&follower=eq.$me"), "followee")
        val followers = ids(rest.call("GET", "/rest/v1/follows?select=follower,followee&followee=eq.$me"), "follower")
        return following to followers
    }

    suspend fun follow(id: String, me: String) {
        try {
            rest.call("POST", "/rest/v1/follows", """{"follower":"$me","followee":"$id"}""", prefer = "return=minimal")
        } catch (e: ApiException.Failed) {
            if (e.code != "23505") throw e
        }
    }

    suspend fun unfollow(id: String, me: String) {
        rest.call("DELETE", "/rest/v1/follows?follower=eq.$me&followee=eq.$id")
    }

    suspend fun block(id: String, me: String) {
        try {
            rest.call("POST", "/rest/v1/blocks", """{"blocker":"$me","blocked":"$id"}""", prefer = "return=minimal")
        } catch (e: ApiException.Failed) {
            if (e.code != "23505") throw e
        }
    }

    suspend fun unblock(id: String, me: String) {
        rest.call("DELETE", "/rest/v1/blocks?blocker=eq.$me&blocked=eq.$id")
    }

    suspend fun blocked(): List<Person> = json.decodeFromString(ListSerializer(Person.serializer()), rest.call("POST", "/rest/v1/rpc/get_blocks", "{}"))

    // My profile -----------------------------------------------------------------------------------------------------

    suspend fun sharing(me: String): SharingChoice {
        val rows = json.parseToJsonElement(rest.call("POST", "/rest/v1/rpc/get_profile", """{"target":"$me"}""")).jsonArray
        val value = rows.firstOrNull()?.jsonObject?.get("default_visibility")?.jsonPrimitive?.content
        return SharingChoice.entries.firstOrNull { it.wire == value } ?: SharingChoice.ONLY_ME
    }

    /** Returns how many existing check-ins were changed when [applyToExisting] is set. */
    suspend fun setSharing(choice: SharingChoice, applyToExisting: Boolean): Int {
        val payload = """{"new_default":"${choice.wire}","apply_to_existing":$applyToExisting}"""
        return rest.call("POST", "/rest/v1/rpc/set_sharing", payload).trim().toIntOrNull() ?: 0
    }

    /** XP, level and badges. Also catches up on badges for check-ins uploaded before they existed. Returns the answer as sent, to keep for offline use. */
    suspend fun progressJson(): String = rest.call("POST", "/rest/v1/rpc/get_my_progress", "{}")

    fun parseProgress(text: String): UserProgress = json.decodeFromString(UserProgress.serializer(), text)

    /** Everything stored about you, as the server's JSON. */
    suspend fun exportMyData(): String = rest.call("POST", "/rest/v1/rpc/export_my_data", "{}")

    /** The private-profile switch and the delay for public check-ins, in minutes. */
    data class Privacy(val isPrivate: Boolean, val postDelayMinutes: Int)

    suspend fun privacy(me: String): Privacy {
        val flag = json.parseToJsonElement(rest.call("GET", "/rest/v1/profiles?select=is_private&id=eq.$me")).jsonArray.firstOrNull()
            ?.jsonObject?.get("is_private")?.jsonPrimitive?.content == "true"
        val delay = json.parseToJsonElement(rest.call("POST", "/rest/v1/rpc/get_profile", """{"target":"$me"}""")).jsonArray.firstOrNull()
            ?.jsonObject?.get("post_delay_minutes")?.jsonPrimitive?.content?.toIntOrNull() ?: 0
        return Privacy(flag, delay)
    }

    suspend fun setPrivacy(me: String, privacy: Privacy) {
        val payload = """{"is_private":${privacy.isPrivate},"post_delay_minutes":${privacy.postDelayMinutes}}"""
        rest.call("PATCH", "/rest/v1/profiles?id=eq.$me", payload, prefer = "return=minimal")
    }

    /** Your own profile: username, name and home airport id. */
    data class MyProfile(val username: String, val displayName: String?, val homeAirport: Long?)

    suspend fun myProfile(me: String): MyProfile? {
        val row = json.parseToJsonElement(rest.call("GET", "/rest/v1/profiles?select=username,display_name&id=eq.$me")).jsonArray.firstOrNull()?.jsonObject ?: return null
        val home = json.parseToJsonElement(rest.call("POST", "/rest/v1/rpc/get_profile", """{"target":"$me"}""")).jsonArray.firstOrNull()
            ?.jsonObject?.get("home_airport")?.jsonPrimitive?.content?.toLongOrNull()
        return MyProfile(row["username"]!!.jsonPrimitive.content, row["display_name"]?.jsonPrimitive?.content?.takeIf { it != "null" }, home)
    }

    suspend fun setHomeAirport(me: String, airportId: Long?) {
        rest.call("PATCH", "/rest/v1/profiles?id=eq.$me", """{"home_airport":${airportId ?: "null"}}""", prefer = "return=minimal")
    }

    suspend fun saveProfile(me: String, username: String, displayName: String?) {
        val payload = buildJsonObject {
            put("username", username)
            if (displayName.isNullOrBlank()) put("display_name", kotlinx.serialization.json.JsonNull) else put("display_name", displayName.trim())
        }.toString()
        rest.call("PATCH", "/rest/v1/profiles?id=eq.$me", payload, prefer = "return=minimal")
    }
}

/** The username rule, the same as the check on `profiles.username`. */
object Username {
    private val valid = Regex("[a-z0-9_]{3,30}")
    private val placeholder = Regex("user_[0-9a-f]{25}")

    fun normalized(text: String) = text.trim().lowercase()
    fun isValid(username: String) = valid.matches(username)

    /** Sign-up gives every account a made-up name like `user_3f9a…`. It means the person hasn't chosen one yet. */
    fun isPlaceholder(username: String) = placeholder.matches(username)
}
