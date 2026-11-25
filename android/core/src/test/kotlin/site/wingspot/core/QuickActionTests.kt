package site.wingspot.core

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class QuickActionTests {
    @Test
    fun anActionIsReadFromItsId() {
        assertEquals(QuickAction.SPOTTED, QuickAction.parse("spotted"))
        assertEquals(QuickAction.FLOWN, QuickAction.parse("flown"))
        assertEquals(QuickAction.AIRPORT, QuickAction.parse("airport"))
        assertEquals(QuickAction.SESSION, QuickAction.parse("session"))
    }

    @Test
    fun anUnknownIdIsIgnored() {
        assertNull(QuickAction.parse("feed"))
        assertNull(QuickAction.parse(""))
        assertNull(QuickAction.parse(null))
    }

    /** The fixed shortcuts in the XML file are the ones the app knows, in the order of the Check in screen (Spotted, Flown, Airport). */
    @Test
    fun theStaticShortcutsAreTheKnownOnesInOrder() {
        val xml = listOf("app/src/main/res/xml/shortcuts.xml", "../app/src/main/res/xml/shortcuts.xml").map(::File).first { it.isFile }.readText()
        val ids = Regex("""android:shortcutId="([^"]+)"""").findAll(xml).map { it.groupValues[1] }.toList()
        assertEquals(listOf("spotted", "flown", "airport"), ids)
        val actions = Regex("""android:name="quick_action"\s+android:value="([^"]+)"""").findAll(xml).map { it.groupValues[1] }.toList()
        assertEquals(ids, actions)
        assertTrue(ids.all { QuickAction.parse(it) != null })
    }
}
