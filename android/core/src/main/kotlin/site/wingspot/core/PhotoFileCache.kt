package site.wingspot.core

import java.io.File

/**
 * Photos of check-ins on disk, kept by photo id (#341). The link to a photo is signed and new every time the feed is loaded, so the link
 * is no good as a key. When the folder gets over [maxBytes], the files used longest ago are removed.
 */
class PhotoFileCache(private val dir: File, private val maxBytes: Long = 150_000_000) {
    init { dir.mkdirs() }

    private fun file(id: String) = File(dir, id.filter { it.isLetterOrDigit() || it == '-' })

    /** The saved photo, or null. Reading it counts as use. */
    fun get(id: String): ByteArray? = file(id).takeIf { it.isFile }?.let { f ->
        runCatching { f.readBytes().also { f.setLastModified(System.currentTimeMillis()) } }.getOrNull()
    }

    fun put(id: String, bytes: ByteArray) {
        runCatching {
            dir.mkdirs()
            val target = file(id)
            val temp = File(dir, target.name + ".part")
            temp.writeBytes(bytes)
            temp.renameTo(target)
        }
        prune()
    }

    /** Removes everything, on sign-out: the photos belong to the account. */
    fun clear() {
        dir.listFiles()?.forEach { it.delete() }
    }

    fun size(): Long = dir.listFiles()?.sumOf { it.length() } ?: 0L

    private fun prune() {
        val files = dir.listFiles()?.filter { it.isFile && !it.name.endsWith(".part") }?.sortedBy { it.lastModified() }?.toMutableList() ?: return
        var total = files.sumOf { it.length() }
        while (total > maxBytes && files.isNotEmpty()) {
            val oldest = files.removeAt(0)
            total -= oldest.length()
            oldest.delete()
        }
    }
}
