package site.wingspot.core

import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** One answer from `POST /v1/checkins`. [status] is `stored` or `rejected`, and [code] says why when rejected. */
data class UploadResult(val id: String, val status: String, val code: String?)

sealed class ApiException(message: String) : Exception(message) {
    /** The access token was refused. */
    object Unauthorized : ApiException("unauthorized")
    /** No network, or the server answered with a 5xx: try again later. */
    object Retry : ApiException("retry")
    /** Any other answer, such as a 400: the request itself is wrong. */
    class Unexpected(val status: Int) : ApiException("unexpected $status")
    /** The server refused this request. [code] is the database's error code, for example `23505` for "already there". */
    class Failed(val status: Int, val code: String?) : ApiException("failed $status $code")
}

/** The Wingspot API (`contracts/openapi.yaml`) as the phone uses it. */
class ApiClient(
    functionsUrl: String,
    private val client: OkHttpClient = OkHttpClient(),
    /** The database API (`<project>/rest/v1`) and its public key, for the few calls that are not in `/v1`. Null in tests. */
    restUrl: String? = null,
    private val apiKey: String? = null,
) {
    private val rest = restUrl?.trimEnd('/')
    private val base = functionsUrl.trimEnd('/')
    private val json = Json { ignoreUnknownKeys = true }

    /** `POST /v1/checkins`. Safe to repeat: the server answers `stored` again for an id it already has. */
    suspend fun uploadCheckins(items: List<LocalCheckIn>, accessToken: String): List<UploadResult> = withContext(Dispatchers.IO) {
        require(items.size in 1..50)
        val body = buildJsonObject { put("checkins", JsonArray(items.map(::item))) }
        val request = Request.Builder().url("$base/v1/checkins")
            .header("Authorization", "Bearer $accessToken")
            .post(body.toString().toRequestBody("application/json".toMediaType())).build()
        try {
            client.newCall(request).execute().use { response ->
                val text = response.body.string()
                when {
                    response.code == 401 -> throw ApiException.Unauthorized
                    response.code >= 500 || response.code == 429 || response.code == 408 -> throw ApiException.Retry
                    response.code != 200 -> throw ApiException.Unexpected(response.code)
                    else -> json.parseToJsonElement(text).jsonObject["results"]!!.jsonArray.map {
                        val r = it.jsonObject
                        UploadResult(r["id"]!!.jsonPrimitive.content, r["status"]!!.jsonPrimitive.content, r["code"]?.jsonPrimitive?.content)
                    }
                }
            }
        } catch (e: IOException) {
            throw ApiException.Retry
        }
    }

    /** What the server said about one photo: [status] is `stored` or `rejected`, with the code when rejected. */
    data class PhotoResult(val stored: Boolean, val code: String?)

    /**
     * `PUT /v1/checkins/{id}/photos/{photoId}`. The check-in has to be on the server first: if it isn't (404), this
     * throws [ApiException.Retry] so the photo waits. Safe to repeat.
     */
    suspend fun uploadPhoto(checkInId: java.util.UUID, photoId: java.util.UUID, jpeg: ByteArray, accessToken: String): PhotoResult =
        withContext(Dispatchers.IO) {
            val request = Request.Builder().url("$base/v1/checkins/$checkInId/photos/$photoId")
                .header("Authorization", "Bearer $accessToken")
                .put(jpeg.toRequestBody("image/jpeg".toMediaType())).build()
            try {
                client.newCall(request).execute().use { response ->
                    val text = response.body.string()
                    val code = runCatching { json.parseToJsonElement(text).jsonObject["code"]?.jsonPrimitive?.content }.getOrNull()
                    when {
                        response.code == 200 -> PhotoResult(true, null)
                        response.code == 401 -> throw ApiException.Unauthorized
                        response.code == 404 && code == "unknown_checkin" -> throw ApiException.Retry
                        response.code >= 500 || response.code == 429 || response.code == 408 -> throw ApiException.Retry
                        response.code in listOf(409, 413, 415) -> PhotoResult(false, code ?: response.code.toString())
                        else -> throw ApiException.Unexpected(response.code)
                    }
                }
            } catch (e: IOException) {
                throw ApiException.Retry
            }
        }

    /**
     * `DELETE /v1/me`: deletes the account for good, with its check-ins, photos, comments and follows. Nothing can undo
     * it, and the access token stops working afterwards. Safe to repeat after a failure.
     */
    suspend fun deleteAccount(accessToken: String) = withContext(Dispatchers.IO) {
        val request = Request.Builder().url("$base/v1/me").header("Authorization", "Bearer $accessToken").delete().build()
        try {
            client.newCall(request).execute().use { response ->
                when {
                    response.isSuccessful -> Unit
                    response.code == 401 -> throw ApiException.Unauthorized
                    response.code >= 500 || response.code == 429 || response.code == 408 -> throw ApiException.Retry
                    else -> throw ApiException.Unexpected(response.code)
                }
            }
        } catch (e: IOException) {
            throw ApiException.Retry
        }
    }

    /** Deletes one of your own check-ins, with its photos, salutes and comments. Does nothing if it is already gone. */
    suspend fun deleteCheckin(id: java.util.UUID, accessToken: String) = withContext(Dispatchers.IO) {
        val request = Request.Builder().url("${rest ?: throw ApiException.Unexpected(0)}/rpc/delete_checkin")
            .header("Authorization", "Bearer $accessToken").header("apikey", apiKey.orEmpty())
            .post("""{"target":"$id"}""".toRequestBody("application/json".toMediaType())).build()
        try {
            client.newCall(request).execute().use { response ->
                when {
                    response.isSuccessful -> Unit
                    response.code == 401 -> throw ApiException.Unauthorized
                    response.code >= 500 || response.code == 429 || response.code == 408 -> throw ApiException.Retry
                    else -> throw ApiException.Unexpected(response.code)
                }
            }
        } catch (e: IOException) {
            throw ApiException.Retry
        }
    }

    /** `CheckinItem` in the contract. The visibility is left out, so the server's default (private) applies. */
    private fun item(c: LocalCheckIn): JsonObject = buildJsonObject {
        put("id", c.id.toString())
        put("kind", c.kind)
        put("occurred_at", c.occurredAt.toString())
        c.registration?.let { put("registration", it) }
        c.typeIcao?.let { put("type_icao", it) }
        c.airportId?.let { put("airport_id", it) }
        c.originId?.let { put("origin_id", it) }
        c.destinationId?.let { put("destination_id", it) }
        c.flightNumber?.let { put("flight_number", it) }
        c.cabin?.let { put("cabin", it) }
        c.seat?.let { put("seat", it) }
        c.visitContext?.let { put("context", it) }
        if (c.latitude != null && c.longitude != null) {
            put("latitude", c.latitude)
            put("longitude", c.longitude)
        }
    }
}

/** What one run of the outbox did. */
sealed class SyncOutcome {
    /** Nothing was waiting, or everything waiting was answered. */
    data class Done(val stored: Int, val rejected: Int) : SyncOutcome()
    /** The network or the server isn't ready: run again later with a delay. */
    object RetryLater : SyncOutcome()
    /** There is no signed-in session, so nothing can be sent yet. */
    object SignedOut : SyncOutcome()
}

/**
 * Uploads the check-ins that are still pending, oldest first, up to 50 at a time. A `rejected` item is final and is
 * not tried again. A network error or a 5xx leaves everything pending. An expired token is refreshed once.
 * [accessToken] gives a valid token (null if signed out) and throws [ApiException.Retry] when it can't reach the
 * network; it is called with `forceRefresh = true` after a 401.
 */
class Outbox(
    private val store: CheckInStore,
    private val api: ApiClient,
    private val accessToken: suspend (forceRefresh: Boolean) -> String?,
) {
    suspend fun sync(): SyncOutcome {
        val checkIns = syncCheckIns()
        if (checkIns !is SyncOutcome.Done) return checkIns
        return when (val photos = syncPhotos()) {
            is SyncOutcome.Done -> SyncOutcome.Done(checkIns.stored + photos.stored, checkIns.rejected + photos.rejected)
            else -> photos
        }
    }

    /** Sends the photos whose check-in the server has. A photo is sent once and not again. */
    private suspend fun syncPhotos(): SyncOutcome {
        var stored = 0
        var rejected = 0
        for (photo in store.photosReadyToSend()) {
            val token = try {
                accessToken(false)
            } catch (e: ApiException.Retry) {
                return SyncOutcome.RetryLater
            } ?: return SyncOutcome.SignedOut
            val result = try {
                try {
                    api.uploadPhoto(photo.checkInId, photo.id, photo.jpeg, token)
                } catch (e: ApiException.Unauthorized) {
                    api.uploadPhoto(photo.checkInId, photo.id, photo.jpeg, accessToken(true) ?: return SyncOutcome.SignedOut)
                }
            } catch (e: ApiException.Retry) {
                return SyncOutcome.RetryLater
            } catch (e: ApiException.Unauthorized) {
                return SyncOutcome.SignedOut
            } catch (e: ApiException.Unexpected) {
                return SyncOutcome.RetryLater
            }
            if (result.stored) {
                store.markPhoto(photo.id, SyncState.SYNCED)
                stored++
            } else {
                store.markPhoto(photo.id, SyncState.REJECTED, result.code)
                rejected++
            }
        }
        return SyncOutcome.Done(stored, rejected)
    }

    /**
     * Deletes a check-in everywhere. One that never reached the server only goes from the phone; any other needs the
     * server first. Returns false when the server could not be reached, in which case nothing is removed.
     */
    suspend fun delete(id: java.util.UUID): Boolean {
        if (store.mayBeOnServer(id)) {
            try {
                val token = accessToken(false) ?: return false
                try {
                    api.deleteCheckin(id, token)
                } catch (e: ApiException.Unauthorized) {
                    api.deleteCheckin(id, accessToken(true) ?: return false)
                }
            } catch (e: ApiException) {
                return false
            }
        }
        store.delete(id)
        return true
    }

    /**
     * A detail the server doesn't accept (an aircraft type it doesn't know, an odd flight number) must not cost the
     * whole flight: it is sent again without that detail, which stays on the phone.
     */
    private suspend fun uploadKeepingTheCore(batch: List<LocalCheckIn>, token: String): List<UploadResult> {
        val last = mutableMapOf<String, UploadResult>()
        val sending = batch.associateBy { it.id.toString() }.toMutableMap()
        var remaining = batch
        repeat(5) {
            val results = api.uploadCheckins(remaining.map { sending.getValue(it.id.toString()) }, token)
            val again = mutableListOf<LocalCheckIn>()
            for (c in remaining) {
                val r = results.firstOrNull { it.id.equals(c.id.toString(), ignoreCase = true) } ?: continue
                last[c.id.toString()] = r
                val current = sending.getValue(c.id.toString())
                val detail = if (r.status == "rejected") droppable(r.code, current) else null
                if (detail != null) {
                    sending[c.id.toString()] = current.without(detail)
                    again += c
                }
            }
            if (again.isEmpty()) return last.values.toList()
            remaining = again
        }
        return last.values.toList()
    }

    private suspend fun syncCheckIns(): SyncOutcome {
        store.reopenFixable()
        var stored = 0
        var rejected = 0
        while (true) {
            val batch = store.pending(50)
            if (batch.isEmpty()) return SyncOutcome.Done(stored, rejected)
            var token = try {
                accessToken(false)
            } catch (e: ApiException.Retry) {
                return SyncOutcome.RetryLater
            } ?: return SyncOutcome.SignedOut
            val results = try {
                try {
                    uploadKeepingTheCore(batch, token)
                } catch (e: ApiException.Unauthorized) {
                    token = accessToken(true) ?: return SyncOutcome.SignedOut // throws Retry when offline
                    uploadKeepingTheCore(batch, token)
                }
            } catch (e: ApiException.Retry) {
                return SyncOutcome.RetryLater
            } catch (e: ApiException.Unauthorized) {
                return SyncOutcome.SignedOut
            } catch (e: ApiException.Unexpected) {
                // The request itself is wrong, and sending it again would be the same. Leave the rows for a fixed build.
                return SyncOutcome.RetryLater
            }
            val byId = results.associateBy { it.id.lowercase() }
            val before = stored + rejected
            val storedIds = batch.filter { byId[it.id.toString()]?.status == "stored" }.map { it.id }
            store.markSynced(storedIds)
            stored += storedIds.size
            for (c in batch) {
                val r = byId[c.id.toString()] ?: continue
                if (r.status == "rejected") {
                    store.markRejected(c.id, r.code)
                    rejected++
                }
            }
            // An answer that settles nothing (an unknown status) would loop forever.
            if (stored + rejected == before) return SyncOutcome.RetryLater
        }
    }

    internal enum class Detail { TYPE, FLIGHT_NUMBER, CABIN, SEAT, REGISTRATION }

    internal companion object {
        /** The detail the server refused, if a flight can do without it and the check-in has it. */
        fun droppable(code: String?, c: LocalCheckIn): Detail? {
            if (c.kind != "flown") return null
            return when (code) {
                "unknown_type" -> Detail.TYPE.takeIf { c.typeIcao != null }
                "invalid_flight_number" -> Detail.FLIGHT_NUMBER.takeIf { c.flightNumber != null }
                "invalid_cabin" -> Detail.CABIN.takeIf { c.cabin != null }
                "invalid_seat" -> Detail.SEAT.takeIf { c.seat != null }
                "invalid_registration" -> Detail.REGISTRATION.takeIf { c.registration != null }
                else -> null
            }
        }

        fun LocalCheckIn.without(detail: Detail): LocalCheckIn = when (detail) {
            Detail.TYPE -> copy(typeIcao = null)
            Detail.FLIGHT_NUMBER -> copy(flightNumber = null)
            Detail.CABIN -> copy(cabin = null)
            Detail.SEAT -> copy(seat = null)
            Detail.REGISTRATION -> copy(registration = null)
        }
    }
}
