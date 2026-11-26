package site.wingspot.core

import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** The community rules version everyone must have agreed to. Version 2 added "I am 16 or older" (docs/MINIMUM-AGE-PLAN.md). */
const val CURRENT_TERMS_VERSION = 2

/** The rules version kept with the account on the server. */
interface TermsRemote {
    /** The version the account agreed to; 0 when none. */
    suspend fun version(): Int
    /** Records the agreement; from version 2 this includes "I am 16 or older". */
    suspend fun accept(version: Int)
}

/** What the phone remembers per account: the version agreed to, and whether that still has to reach the server. */
interface TermsMemory {
    fun version(user: String): Int
    fun setVersion(user: String, version: Int)
    fun isPending(user: String): Boolean
    fun setPending(user: String, pending: Boolean)
}

/**
 * Brings phone and server together: an agreement from another phone is taken over, one made on this phone that didn't reach
 * the server is sent again. Failures are left for the next time; the phone's copy alone decides, so the app starts offline.
 */
class TermsSync(private val memory: TermsMemory, private val remote: TermsRemote) {
    fun hasAccepted(user: String): Boolean = memory.version(user) >= CURRENT_TERMS_VERSION

    fun accept(user: String) {
        memory.setVersion(user, CURRENT_TERMS_VERSION)
        memory.setPending(user, true)
    }

    /** Returns true when the phone's copy changed. */
    suspend fun sync(user: String): Boolean {
        if (memory.isPending(user)) {
            try { remote.accept(memory.version(user)) } catch (e: ApiException) { return false }
            memory.setPending(user, false)
            return false
        }
        if (hasAccepted(user)) return false
        val stored = try { remote.version() } catch (e: ApiException) { return false }
        if (stored <= memory.version(user)) return false
        memory.setVersion(user, stored)
        return true
    }
}

/** `get_my_terms` and `accept_terms` on the server. */
class TermsApi(private val rest: Rest) : TermsRemote {
    override suspend fun version(): Int =
        rest.json.parseToJsonElement(rest.call("POST", "/rest/v1/rpc/get_my_terms", "{}")).jsonArray.firstOrNull()
            ?.jsonObject?.get("terms_version")?.jsonPrimitive?.int ?: 0

    override suspend fun accept(version: Int) {
        rest.call("POST", "/rest/v1/rpc/accept_terms", """{"p_version":$version}""")
    }
}

/**
 * The app version against the server's minimum (`min_version` in `/v1/config`, docs/MINIMUM-AGE-PLAN.md 4a). Compared part by
 * part as numbers ("0.10.0" is newer than "0.9.0"); a missing part counts as 0. Anything that can't be read never asks for an
 * update, so a typo on the server can't lock everybody out. The iPhone app has the same rule.
 */
object AppVersion {
    fun needsUpdate(installed: String?, minimum: String?): Boolean {
        val have = parts(installed) ?: return false
        val need = parts(minimum) ?: return false
        for (index in 0 until maxOf(have.size, need.size)) {
            val a = have.getOrElse(index) { 0 }
            val b = need.getOrElse(index) { 0 }
            if (a != b) return a < b
        }
        return false
    }

    private fun parts(version: String?): List<Int>? {
        val text = version?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        return text.split(".").map { part -> part.toIntOrNull()?.takeIf { it >= 0 } ?: return null }
    }
}
