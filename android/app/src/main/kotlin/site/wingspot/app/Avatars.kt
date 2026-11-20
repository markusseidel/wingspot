package site.wingspot.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import site.wingspot.core.AvatarImage
import site.wingspot.core.Downloads

/** A profile image ready to upload, and the same picture to show at once. */
class PreparedAvatar(val jpeg: ByteArray, val preview: Bitmap)

/**
 * Profile images for every list that shows people. An image is asked for by the person's ID and kept in memory; a
 * person without one is remembered for this run, so a long feed asks once per person.
 */
object Avatars {
    private val cache = LruCache<String, Bitmap>(80)
    private val misses = HashSet<String>()

    /** Counts the changes made on this phone, so views showing your own image refresh at once. */
    var changes by mutableIntStateOf(0)
        private set

    /** The person's image, or null if they have none or it can't be loaded now. */
    suspend fun load(userId: String): Bitmap? {
        val key = userId.lowercase()
        synchronized(this) {
            cache.get(key)?.let { return it }
            if (key in misses) return null
        }
        val fetched = Downloads.fetch(AvatarImage.url(BuildConfig.SUPABASE_URL, key))
        val bitmap = fetched.bytes?.let { bytes -> withContext(Dispatchers.Default) { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) } }
        synchronized(this) {
            if (bitmap != null) cache.put(key, bitmap)
            // 400 and 404 mean the person has no image. Other answers may pass, so they are not remembered.
            else if (fetched.code == 400 || fetched.code == 404) misses.add(key)
        }
        return bitmap
    }

    /** Your own image changed, or was removed ([bitmap] is null). */
    fun changed(userId: String, bitmap: Bitmap?) {
        val key = userId.lowercase()
        synchronized(this) {
            if (bitmap != null) { cache.put(key, bitmap); misses.remove(key) } else { cache.remove(key); misses.add(key) }
        }
        changes++
    }

    /**
     * Cuts the picture to a centred square, scales it to the profile image size and encodes it as JPEG. Encoding
     * again also drops location and camera data. Null if the picture can't be read or stays too big.
     */
    suspend fun prepare(context: Context, uri: Uri): PreparedAvatar? = withContext(Dispatchers.IO) {
        try {
            val decoded = ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                val longSide = maxOf(info.size.width, info.size.height)
                if (longSide > 2048) {
                    val scale = 2048f / longSide
                    decoder.setTargetSize((info.size.width * scale).toInt().coerceAtLeast(1), (info.size.height * scale).toInt().coerceAtLeast(1))
                }
            }
            val square = AvatarImage.squareCrop(decoded.width, decoded.height)
            val cut = Bitmap.createBitmap(decoded, square.left, square.top, square.side, square.side)
            val image = Bitmap.createScaledBitmap(cut, AvatarImage.SIDE, AvatarImage.SIDE, true)
            for (quality in listOf(85, 70, 55)) {
                val out = ByteArrayOutputStream()
                image.compress(Bitmap.CompressFormat.JPEG, quality, out)
                if (out.size() <= AvatarImage.MAX_BYTES) return@withContext PreparedAvatar(out.toByteArray(), image)
            }
            null
        } catch (e: Exception) {
            null
        }
    }
}

/** A person's picture in a circle, or their first letter when they have none. */
@Composable
fun Avatar(userId: String?, name: String, size: Dp = 40.dp) {
    val changes = Avatars.changes
    val bitmap by produceState<Bitmap?>(null, userId, changes) {
        value = if (userId == null) null else Avatars.load(userId)
    }
    Box(
        Modifier.size(size).clip(CircleShape).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)),
        contentAlignment = Alignment.Center,
    ) {
        val image = bitmap
        if (image != null) {
            Image(image.asImageBitmap(), contentDescription = null, modifier = Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        } else {
            Text(name.take(1).uppercase(), fontSize = (size.value * 0.42f).sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
        }
    }
}
