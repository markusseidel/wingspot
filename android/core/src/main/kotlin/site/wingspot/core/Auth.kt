package site.wingspot.core

import java.net.URI
import java.net.URLDecoder
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** A secret kept on the phone while the sign-in link is on its way. Its hash goes with the request (PKCE). */
class Pkce private constructor(val verifier: String, val challenge: String) {
    companion object {
        fun create(random: SecureRandom = SecureRandom()): Pkce {
            val bytes = ByteArray(48).also(random::nextBytes)
            val verifier = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
            return Pkce(verifier, challengeFor(verifier))
        }

        /** Rebuilds the pair from a verifier that was kept on the phone. */
        fun fromVerifier(verifier: String) = Pkce(verifier, challengeFor(verifier))

        fun challengeFor(verifier: String): String =
            Base64.getUrlEncoder().withoutPadding()
                .encodeToString(MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.US_ASCII)))
    }
}

@Serializable
data class SessionUser(val id: String, val email: String? = null)

@Serializable
data class Session(
    @kotlinx.serialization.SerialName("access_token") val accessToken: String,
    @kotlinx.serialization.SerialName("refresh_token") val refreshToken: String,
    @kotlinx.serialization.SerialName("expires_in") val expiresIn: Long = 3600,
    val user: SessionUser,
)

sealed class AuthException(message: String) : Exception(message) {
    /** The link was used already, has expired, or was requested on another device. */
    object InvalidLink : AuthException("invalidLink")
    object TooManyRequests : AuthException("tooManyRequests")
    object InvalidEmail : AuthException("invalidEmail")
    object Offline : AuthException("offline")
    object Unknown : AuthException("unknown")
}

/**
 * Email-link sign-in against Supabase's auth service, the same flow as the iPhone app: ask for a link with the
 * PKCE challenge, then trade the code in the link for a session. Nothing here logs an email, a link or a token.
 */
class SupabaseAuth(
    baseUrl: String,
    private val publishableKey: String,
    private val client: OkHttpClient = OkHttpClient(),
    private val redirectTo: String = REDIRECT_URL,
) {
    private val base = baseUrl.trimEnd('/')
    private val json = Json { ignoreUnknownKeys = true }
    private val jsonType = "application/json".toMediaType()

    suspend fun sendSignInLink(email: String, language: String?, pkce: Pkce) {
        val url = "$base/auth/v1/otp".toHttpUrl().newBuilder().addQueryParameter("redirect_to", redirectTo).build()
        val body = buildJsonObject {
            put("email", email)
            put("create_user", true)
            put("code_challenge", pkce.challenge)
            put("code_challenge_method", "s256")
            if (language != null) put("data", JsonObject(mapOf("language" to JsonPrimitive(language))))
        }
        call(Request.Builder().url(url).post(body.toString().toRequestBody(jsonType))) { }
    }

    /** Finishes sign-in from the link the phone was opened with, `wingspot://auth-callback?code=...`. */
    suspend fun completeSignIn(callback: String, pkce: Pkce): Session {
        val code = queryParameter(callback, "code") ?: throw AuthException.InvalidLink
        val url = "$base/auth/v1/token".toHttpUrl().newBuilder().addQueryParameter("grant_type", "pkce").build()
        val body = buildJsonObject {
            put("auth_code", code)
            put("code_verifier", pkce.verifier)
        }
        return call(Request.Builder().url(url).post(body.toString().toRequestBody(jsonType))) { text ->
            json.decodeFromString(Session.serializer(), text)
        }
    }

    private suspend fun <T> call(builder: Request.Builder, parse: (String) -> T): T = withContext(Dispatchers.IO) {
        val request = builder.header("apikey", publishableKey).build()
        try {
            client.newCall(request).execute().use { response ->
                val text = response.body.string()
                when {
                    response.isSuccessful -> parse(text)
                    response.code == 429 -> throw AuthException.TooManyRequests
                    response.code == 422 || response.code == 400 && "email" in text.lowercase() -> throw AuthException.InvalidEmail
                    response.code in 400..403 -> throw AuthException.InvalidLink
                    else -> throw AuthException.Unknown
                }
            }
        } catch (e: java.io.IOException) {
            throw AuthException.Offline
        }
    }

    companion object {
        const val REDIRECT_URL = "wingspot://auth-callback"

        /** The value of a query parameter in a link, or null. Never throws on a strange link. */
        fun queryParameter(link: String, name: String): String? = runCatching {
            URI(link).rawQuery.orEmpty().split('&')
                .map { it.split('=', limit = 2) }
                .firstOrNull { it[0] == name && it.size == 2 }
                ?.let { URLDecoder.decode(it[1], Charsets.UTF_8) }
                ?.takeIf { it.isNotEmpty() }
        }.getOrNull()
    }
}
