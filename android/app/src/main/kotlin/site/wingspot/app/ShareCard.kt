package site.wingspot.app

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import androidx.core.content.FileProvider
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import site.wingspot.core.ApiException
import site.wingspot.core.InviteLink

/**
 * What a share card says. Generic on purpose: a flight, a badge and a level are all a small line, a big line and a number.
 * [kicker] is the label on top (FLOWN, BADGE), [message] the text sent along with the picture.
 */
data class ShareCardModel(val kicker: String, val headline: String, val figure: String?, val caption: String?, val message: String)

object ShareCards {
    private const val WIDTH = 1080
    private const val HEIGHT = 1350
    private const val ORANGE = 0xFFFF6B1A.toInt()

    /** Draws the card, 1080 x 1350, dark with the brand colour. */
    fun render(model: ShareCardModel, name: String, code: String?): Bitmap {
        val bitmap = Bitmap.createBitmap(WIDTH, HEIGHT, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawRect(0f, 0f, WIDTH.toFloat(), HEIGHT.toFloat(), Paint().apply {
            shader = LinearGradient(0f, 0f, 0f, HEIGHT.toFloat(), 0xFF0A1633.toInt(), 0xFF14244D.toInt(), Shader.TileMode.CLAMP)
        })
        val pad = 84f
        // Top: the name of the app and the label.
        text(canvas, "Wingspot", pad, 140f, 54f, 0xFFFFFFFF.toInt(), bold = true)
        val kicker = model.kicker.uppercase()
        val kickerPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 38f; typeface = Typeface.DEFAULT_BOLD; color = 0xFFFFFFFF.toInt() }
        val kickerWidth = kickerPaint.measureText(kicker)
        val left = WIDTH - pad - kickerWidth - 56f
        canvas.drawRoundRect(left, 96f, WIDTH - pad, 160f, 32f, 32f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = ORANGE })
        canvas.drawText(kicker, left + 28f, 140f, kickerPaint)
        // Middle: the big line, the figure and the details.
        var y = 440f
        y += paragraph(canvas, model.headline, pad, y, WIDTH - 2 * pad, 150f, 0xFFFFFFFF.toInt(), maxLines = 3)
        model.figure?.let { y += 28f; y += paragraph(canvas, it, pad, y, WIDTH - 2 * pad, 90f, ORANGE, maxLines = 2) }
        model.caption?.let { y += 28f; paragraph(canvas, it, pad, y, WIDTH - 2 * pad, 44f, 0xBFFFFFFF.toInt(), maxLines = 3, bold = false) }
        // Bottom: who is sharing, and the invite code.
        canvas.drawLine(pad, HEIGHT - 190f, WIDTH - pad, HEIGHT - 190f, Paint().apply { color = 0x33FFFFFF; strokeWidth = 3f })
        text(canvas, name, pad, HEIGHT - 110f, 48f, 0xFFFFFFFF.toInt(), bold = true)
        code?.let {
            val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 46f; typeface = Typeface.MONOSPACE; color = 0xBFFFFFFF.toInt() }
            canvas.drawText(it, WIDTH - pad - paint.measureText(it), HEIGHT - 110f, paint)
        }
        return bitmap
    }

    private fun text(canvas: Canvas, text: String, x: Float, y: Float, size: Float, color: Int, bold: Boolean) {
        canvas.drawText(text, x, y, TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = size; this.color = color; if (bold) typeface = Typeface.DEFAULT_BOLD })
    }

    /** Draws wrapped text that shrinks until it fits in [maxLines]. Returns its height. */
    private fun paragraph(canvas: Canvas, text: String, x: Float, y: Float, width: Float, size: Float, color: Int, maxLines: Int, bold: Boolean = true): Float {
        var textSize = size
        var layout: StaticLayout
        while (true) {
            val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { this.textSize = textSize; this.color = color; if (bold) typeface = Typeface.DEFAULT_BOLD }
            layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, width.toInt()).setAlignment(Layout.Alignment.ALIGN_NORMAL).build()
            if (layout.lineCount <= maxLines || textSize <= 28f) break
            textSize -= 6f
        }
        canvas.save()
        canvas.translate(x, y)
        layout.draw(canvas)
        canvas.restore()
        return layout.height.toFloat()
    }

    /** Draws the card, saves it in the cache and opens the share sheet with the picture and the text. */
    suspend fun share(app: WingspotApp, context: Context, me: String, model: ShareCardModel) {
        val name = try { app.social.person(me)?.who.orEmpty() } catch (e: ApiException) { "" }
        val code = try { app.social.myInviteCode() } catch (e: ApiException) { null }
        val uri = withContext(Dispatchers.Default) {
            val file = File(context.cacheDir, "share/wingspot-card.png").also { it.parentFile?.mkdirs() }
            file.outputStream().use { render(model, name, code).compress(Bitmap.CompressFormat.PNG, 100, it) }
            FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        }
        val text = if (code != null) model.message + " " + context.getString(R.string.invite_share_text, code, InviteLink.url(code)) else model.message
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_TEXT, text)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(send, null))
    }
}
