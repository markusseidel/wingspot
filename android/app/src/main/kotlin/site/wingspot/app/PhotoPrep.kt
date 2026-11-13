package site.wingspot.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import site.wingspot.core.PhotoCleaner

/** A photo ready to save and upload: a JPEG of at most 2048 pixels on the long side, with no metadata. */
class PreparedPhoto(val jpeg: ByteArray, val width: Int, val height: Int)

object PhotoPrep {
    /**
     * Turns what the person picked into what Wingspot stores. The picture is decoded (turned the right way up) and
     * written again from its pixels, so the location and camera data of the original are not carried over; the
     * metadata segments that remain are cut out as well. The original is not kept. Null if it can't be read.
     */
    suspend fun prepare(context: Context, uri: Uri): PreparedPhoto? = withContext(Dispatchers.IO) {
        try {
            val bitmap = ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                val longSide = max(info.size.width, info.size.height)
                if (longSide > PhotoCleaner.MAX_PIXELS) {
                    val scale = PhotoCleaner.MAX_PIXELS.toFloat() / longSide
                    decoder.setTargetSize((info.size.width * scale).toInt().coerceAtLeast(1), (info.size.height * scale).toInt().coerceAtLeast(1))
                }
            }
            for (quality in listOf(80, 65, 50)) {
                val out = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
                val clean = PhotoCleaner.removeMetadata(out.toByteArray())
                if (clean.size <= PhotoCleaner.MAX_BYTES) return@withContext PreparedPhoto(clean, bitmap.width, bitmap.height)
            }
            null
        } catch (e: Exception) {
            null
        }
    }
}
