package site.wingspot.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class InviteTests {
    @Test
    fun aCodeInALinkIsFound() {
        assertEquals("ABCD2345", InviteLink.code("wingspot://invite/abcd2345"))
        assertNull(InviteLink.code("wingspot://auth-callback?code=xyz"))
        assertNull(InviteLink.code("wingspot://invite/short"))
        assertNull(InviteLink.code("https://example.com/invite/ABCD2345"))
    }

    @Test
    fun aTypedCodeIsMadeTidyOrRefused() {
        assertEquals("ABCD2345", InviteLink.clean("  abcd2345 \n"))
        assertNull(InviteLink.clean("ABCD234"))
        assertNull(InviteLink.clean("ABCD2O45"))
    }

    @Test
    fun theLinkOfACodeRoundTrips() {
        assertEquals("wingspot://invite/ABCD2345", InviteLink.url("ABCD2345"))
        assertEquals("ABCD2345", InviteLink.code(InviteLink.url("ABCD2345")))
    }
}
