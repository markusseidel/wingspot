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
}

/** The Wingspot API (`contracts/openapi.yaml`) as the phone uses it. */
class ApiClient(functionsUrl: String, private val client: OkHttpClient = OkHttpClient()) {
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

    /** `CheckinItem` in the contract. The visibility is left out, so the server's default (private) applies. */
    private fun item(c: LocalCheckIn): JsonObject = buildJsonObject {
        put("id", c.id.toString())
        put("kind", c.kind)
        put("occurred_at", c.occurredAt.toString())
        c.registration?.let { put("registration", it) }
        c.typeIcao?.let { put("type_icao", it) }
        c.airportId?.let { put("airport_id", it) }
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
                    api.uploadCheckins(batch, token)
                } catch (e: ApiException.Unauthorized) {
                    token = accessToken(true) ?: return SyncOutcome.SignedOut // throws Retry when offline
                    api.uploadCheckins(batch, token)
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
}
