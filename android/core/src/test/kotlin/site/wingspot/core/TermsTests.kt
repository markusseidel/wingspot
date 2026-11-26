package site.wingspot.core

import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class TermsTests {
    private class Memory : TermsMemory {
        val versions = mutableMapOf<String, Int>()
        val pending = mutableSetOf<String>()
        override fun version(user: String) = versions[user] ?: 0
        override fun setVersion(user: String, version: Int) { versions[user] = version }
        override fun isPending(user: String) = user in pending
        override fun setPending(user: String, pending: Boolean) { if (pending) this.pending += user else this.pending -= user }
    }

    private class Remote : TermsRemote {
        var stored = 0
        var offline = false
        override suspend fun version(): Int { if (offline) throw ApiException.Retry; return stored }
        override suspend fun accept(version: Int) { if (offline) throw ApiException.Retry; stored = maxOf(stored, version) }
    }

    @Test fun termsAreAcceptedPerAccount() {
        val terms = TermsSync(Memory(), Remote())
        assertFalse(terms.hasAccepted("a"))
        terms.accept("a")
        assertTrue(terms.hasAccepted("a"))
        assertFalse(terms.hasAccepted("b"))
    }

    @Test fun versionOneAsksAgainAndAnotherPhonesAgreementCounts() = runBlocking {
        val memory = Memory().apply { versions["a"] = 1 }
        val remote = Remote()
        val terms = TermsSync(memory, remote)
        assertFalse(terms.hasAccepted("a"))
        assertFalse(terms.sync("a"))
        assertFalse(terms.hasAccepted("a"))
        remote.stored = 2
        assertTrue(terms.sync("a"))
        assertTrue(terms.hasAccepted("a"))
    }

    @Test fun anOfflineAgreementIsSentLater() = runBlocking {
        val remote = Remote().apply { offline = true }
        val terms = TermsSync(Memory(), remote)
        terms.accept("a")
        terms.sync("a")
        assertEquals(0, remote.stored)
        assertTrue(terms.hasAccepted("a"))
        remote.offline = false
        terms.sync("a")
        assertEquals(2, remote.stored)
    }

    @Test fun anOlderVersionNeedsAnUpdate() {
        assertTrue(AppVersion.needsUpdate("0.2.0", "0.3.0"))
        assertTrue(AppVersion.needsUpdate("0.9.0", "0.10.0"))
        assertTrue(AppVersion.needsUpdate("0.3", "0.3.1"))
    }

    @Test fun theSameOrANewerVersionDoesNot() {
        assertFalse(AppVersion.needsUpdate("0.3.0", "0.3.0"))
        assertFalse(AppVersion.needsUpdate("0.3", "0.3.0"))
        assertFalse(AppVersion.needsUpdate("1.0.0", "0.10.0"))
    }

    @Test fun whatCannotBeReadNeverAsksForAnUpdate() {
        assertFalse(AppVersion.needsUpdate("0.2.0", null))
        assertFalse(AppVersion.needsUpdate("0.2.0", ""))
        assertFalse(AppVersion.needsUpdate("0.2.0", "1.x"))
        assertFalse(AppVersion.needsUpdate(null, "9.0.0"))
        assertFalse(AppVersion.needsUpdate("0.2.0", "1..0"))
    }
}
