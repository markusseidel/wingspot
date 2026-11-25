package site.wingspot.core

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals

class KmlBatchTests {
    private val aug12 = LocalDate.of(2026, 8, 12)

    @Test
    fun aFlightTheLogbookHasIsMarked() {
        val result = KmlBatch.duplicates(
            listOf(KmlBatch.Entry("LH 400", aug12), KmlBatch.Entry("LH401", aug12)),
            listOf(KmlBatch.Existing("LH400", aug12)),
        )
        assertEquals(listOf(true, false), result)
    }

    @Test
    fun theSameFlightTwiceInTheBatchIsMarkedTheSecondTime() {
        val result = KmlBatch.duplicates(
            listOf(KmlBatch.Entry("LH400", aug12), KmlBatch.Entry("lh400", aug12), KmlBatch.Entry("LH400", aug12.plusDays(1))), emptyList(),
        )
        assertEquals(listOf(false, true, false), result)
    }

    @Test
    fun theSameLinkIsTheSameFlight() {
        val result = KmlBatch.duplicates(
            listOf(KmlBatch.Entry(null, null, "https://fr24/abc"), KmlBatch.Entry("LH400", aug12, "https://fr24/abc")), emptyList(),
        )
        assertEquals(listOf(false, true), result)
    }

    @Test
    fun anEntryWithoutANumberOrADayIsNeverMarkedByNumber() {
        val result = KmlBatch.duplicates(
            listOf(KmlBatch.Entry(null, aug12), KmlBatch.Entry("LH400", null)), listOf(KmlBatch.Existing("LH400", aug12)),
        )
        assertEquals(listOf(false, false), result)
    }
}
