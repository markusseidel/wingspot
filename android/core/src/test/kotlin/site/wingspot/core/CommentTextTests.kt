package site.wingspot.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class CommentTextTests {
    @Test
    fun theNameBeingTypedIsFound() {
        assertEquals("ma", CommentText.activePrefix("hello @Ma"))
        assertEquals("", CommentText.activePrefix("@"))
        assertNull(CommentText.activePrefix("hello"))
        assertNull(CommentText.activePrefix("hello @max "))
        assertNull(CommentText.activePrefix("mail@max"))
    }

    @Test
    fun aChosenFriendReplacesWhatWasTyped() {
        assertEquals("hi @max_k ", CommentText.completing("hi @ma", "max_k"))
        assertEquals("@anna ", CommentText.completing("@", "anna"))
        assertEquals("hi", CommentText.completing("hi", "anna"))
    }

    @Test
    fun aReplyStartsWithTheName() {
        assertEquals("@anna ", CommentText.replying("anna", ""))
        assertEquals("@anna thanks", CommentText.replying("anna", "thanks"))
        assertEquals("@Anna thanks", CommentText.replying("anna", "@Anna thanks"))
    }

    @Test
    fun mentionsAreFoundAtWordBoundaries() {
        val body = "Hi @Max and @maxine, not mail@max.de, @max!"
        val found = CommentText.mentionRanges(body, listOf("max", "maxine"))
        assertEquals(listOf("max", "maxine", "max"), found.map { it.second })
        assertEquals(listOf("@Max", "@maxine", "@max"), found.map { body.substring(it.first.first, it.first.last + 1) })
    }
}
