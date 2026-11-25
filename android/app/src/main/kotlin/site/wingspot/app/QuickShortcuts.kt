package site.wingspot.app

import android.content.Context
import android.content.Intent
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import java.time.Instant
import site.wingspot.core.QuickAction
import site.wingspot.core.SpotSession

/** The shortcuts of a long press on the app icon (#349). The three fixed ones are in `res/xml/shortcuts.xml`; this adds the running session. */
object QuickShortcuts {
    /** The check-in kind a shortcut opens. The session entry opens the sighting form, which joins the session. */
    fun kind(action: QuickAction): Kind = when (action) {
        QuickAction.SPOTTED, QuickAction.SESSION -> Kind.SPOTTED
        QuickAction.FLOWN -> Kind.FLOWN
        QuickAction.AIRPORT -> Kind.AIRPORT
    }

    /** The entry for the running spotting session, or none: it is removed when the session ends or has run out. */
    fun showSession(context: Context, session: SpotSession?) {
        val app = context.applicationContext
        val running = session?.takeIf { it.isActive(Instant.now()) }
        if (running == null) {
            ShortcutManagerCompat.removeDynamicShortcuts(app, listOf(QuickAction.SESSION.id))
            return
        }
        val intent = Intent(Intent.ACTION_MAIN).setClassName(app.packageName, MainActivity::class.java.name).putExtra("quick_action", QuickAction.SESSION.id)
        val label = app.getString(R.string.session_at, running.spotName)
        val shortcut = ShortcutInfoCompat.Builder(app, QuickAction.SESSION.id)
            .setShortLabel(label).setLongLabel(label)
            .setIcon(IconCompat.createWithResource(app, R.drawable.ic_glyph_binoculars))
            .setIntent(intent).build()
        ShortcutManagerCompat.pushDynamicShortcut(app, shortcut)
    }
}
