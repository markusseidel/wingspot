package site.wingspot.core

import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNull

class PhotoFileCacheTests {
    private fun cache(max: Long = 1_000) = PhotoFileCache(Files.createTempDirectory("photos").toFile(), max)

    @Test
    fun aSavedPhotoComesBackByItsId() {
        val cache = cache()
        assertNull(cache.get("a"))
        cache.put("a", byteArrayOf(1, 2, 3))
        assertContentEquals(byteArrayOf(1, 2, 3), cache.get("a"))
        assertEquals(3, cache.size())
    }

    @Test
    fun theFilesUsedLongestAgoGoWhenTheFolderIsTooBig() {
        val cache = cache(max = 250)
        val dir = Files.createTempDirectory("photos2").toFile()
        val small = PhotoFileCache(dir, 250)
        small.put("old", ByteArray(100))
        small.put("mid", ByteArray(100))
        java.io.File(dir, "old").setLastModified(1_000)
        java.io.File(dir, "mid").setLastModified(2_000)
        small.put("new", ByteArray(100))
        assertNull(small.get("old"))
        assertContentEquals(ByteArray(100), small.get("mid"))
        assertContentEquals(ByteArray(100), small.get("new"))
        cache.clear()
    }

    @Test
    fun readingAPhotoMakesItTheNewest() {
        val dir = Files.createTempDirectory("photos3").toFile()
        val cache = PhotoFileCache(dir, 250)
        cache.put("a", ByteArray(100)); cache.put("b", ByteArray(100))
        java.io.File(dir, "a").setLastModified(1_000); java.io.File(dir, "b").setLastModified(2_000)
        cache.get("a")
        cache.put("c", ByteArray(100))
        assertNull(cache.get("b"))
        assertContentEquals(ByteArray(100), cache.get("a"))
    }

    @Test
    fun clearRemovesEverything() {
        val cache = cache()
        cache.put("a", byteArrayOf(1)); cache.put("b", byteArrayOf(2))
        cache.clear()
        assertNull(cache.get("a"))
        assertEquals(0, cache.size())
    }
}
