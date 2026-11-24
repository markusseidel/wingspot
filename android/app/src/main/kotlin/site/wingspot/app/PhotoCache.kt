package site.wingspot.app

import android.content.Context
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import site.wingspot.core.Downloads
import site.wingspot.core.FeedPhoto
import site.wingspot.core.PhotoFileCache

/**
 * The photos of check-ins, kept by photo id (#341): decoded in memory, and as files on disk. The link to a photo is signed and new every
 * time the feed is loaded, so it can't be the key. Cleared on sign-out.
 */
object PhotoCache {
    private val memory = object : LruCache<String, ImageBitmap>((Runtime.getRuntime().maxMemory() / 8).toInt().coerceAtLeast(8_000_000)) {
        override fun sizeOf(key: String, value: ImageBitmap) = value.width * value.height * 4
    }
    private var files: PhotoFileCache? = null

    private fun files(context: Context): PhotoFileCache =
        files ?: PhotoFileCache(File(context.applicationContext.cacheDir, "photos")).also { files = it }

    /** The picture if it is in memory, so a screen can show it from the first frame. */
    fun cached(photo: FeedPhoto): ImageBitmap? = memory.get(photo.id)

    /** The photo: from memory, else the disk, else downloaded (and kept). Null when it can't be had. */
    suspend fun load(context: Context, photo: FeedPhoto): ImageBitmap? {
        memory.get(photo.id)?.let { return it }
        val disk = files(context)
        val bytes = withContext(Dispatchers.IO) { disk.get(photo.id) } ?: Downloads.bytes(photo.url)?.also { withContext(Dispatchers.IO) { disk.put(photo.id, it) } }
        val image = bytes?.let { withContext(Dispatchers.Default) { BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap() } } ?: return null
        memory.put(photo.id, image)
        return image
    }

    fun clear(context: Context) {
        memory.evictAll()
        files(context).clear()
    }
}
