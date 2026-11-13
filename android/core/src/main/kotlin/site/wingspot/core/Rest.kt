package site.wingspot.core

import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * Calls the database API (`<project>/rest/v1`) and storage as the signed-in person. Row-level security on the server
 * decides what comes back. A refused token is refreshed once. [accessToken] gives a token (null if signed out) and is
 * called with `forceRefresh = true` after a 401.
 */
class Rest(
    private val baseUrl: String,
    private val apiKey: String,
    private val accessToken: suspend (forceRefresh: Boolean) -> String?,
    private val client: OkHttpClient = OkHttpClient(),
) {
    val json = Json { ignoreUnknownKeys = true; explicitNulls = false; encodeDefaults = true }
    private val root = baseUrl.trimEnd('/')

    /** Returns the response body. [path] starts with `/`, for example `/rest/v1/rpc/get_feed`. */
    suspend fun call(method: String, path: String, body: String? = null, prefer: String? = null): String {
        val first = send(method, path, body, prefer, accessToken(false) ?: throw ApiException.Unauthorized)
        if (first.code != 401) return finish(first)
        val retry = send(method, path, body, prefer, accessToken(true) ?: throw ApiException.Unauthorized)
        return finish(retry)
    }

    private class Answer(val code: Int, val text: String)

    private suspend fun send(method: String, path: String, body: String?, prefer: String?, token: String): Answer =
        withContext(Dispatchers.IO) {
            val builder = Request.Builder().url(root + path)
                .header("Authorization", "Bearer $token").header("apikey", apiKey).header("Accept", "application/json")
            prefer?.let { builder.header("Prefer", it) }
            val requestBody = body?.toRequestBody("application/json".toMediaType())
            builder.method(method, requestBody ?: if (method == "GET" || method == "DELETE") null else "".toRequestBody())
            try {
                client.newCall(builder.build()).execute().use { Answer(it.code, it.body.string()) }
            } catch (e: IOException) {
                throw ApiException.Retry
            }
        }

    private fun finish(answer: Answer): String = when {
        answer.code in 200..299 -> answer.text
        answer.code == 401 -> throw ApiException.Unauthorized
        answer.code >= 500 || answer.code == 429 || answer.code == 408 -> throw ApiException.Retry
        else -> throw ApiException.Failed(
            answer.code,
            runCatching { json.parseToJsonElement(answer.text).jsonObject["code"]?.jsonPrimitive?.content }.getOrNull(),
        )
    }
}

/** Downloads a picture from a signed link. Null if it can't be fetched. */
object Downloads {
    private val client = OkHttpClient()

    suspend fun bytes(url: String): ByteArray? = withContext(Dispatchers.IO) {
        try {
            client.newCall(Request.Builder().url(url).build()).execute().use { if (it.isSuccessful) it.body.bytes() else null }
        } catch (e: IOException) {
            null
        }
    }
}
