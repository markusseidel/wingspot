package site.wingspot.app

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import java.util.Locale
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import site.wingspot.core.Announcement
import site.wingspot.core.AnnouncementsApi
import site.wingspot.core.ApiException
import site.wingspot.core.visibleAnnouncements

/**
 * The announcements at the top of the Feed. What the server sent last time is kept on the phone, so the card shows offline;
 * a dismissal is remembered by id.
 */
class AnnouncementsViewModel(private val api: AnnouncementsApi, private val prefs: Prefs) : ViewModel() {
    private var all: List<Announcement> = prefs.announcementsCache?.let(api::decode).orEmpty()
    private val mutable = MutableStateFlow(visibleAnnouncements(all, prefs.dismissedAnnouncements))
    val visible: StateFlow<List<Announcement>> = mutable.asStateFlow()

    /** Asks the server. A failed request leaves what is shown as it is. */
    fun refresh() {
        viewModelScope.launch {
            try {
                all = api.fetch()
                prefs.announcementsCache = api.encode(all)
                // Forget dismissals of announcements that are gone, so the list of ids doesn't grow for ever.
                val ids = all.map { it.id }.toSet()
                prefs.dismissedAnnouncements = prefs.dismissedAnnouncements.filter { it in ids }.toSet()
                mutable.value = visibleAnnouncements(all, prefs.dismissedAnnouncements)
            } catch (e: ApiException) {
                // Offline or an old server: keep the last list.
            }
        }
    }

    fun dismiss(id: String) {
        prefs.dismissedAnnouncements = prefs.dismissedAnnouncements + id
        mutable.value = visibleAnnouncements(all, prefs.dismissedAnnouncements)
    }

    companion object {
        fun factory(app: WingspotApp): ViewModelProvider.Factory = viewModelFactory {
            initializer { AnnouncementsViewModel(app.announcements, app.prefs) }
        }
    }
}

/** The cards for the announcements that weren't dismissed, in the person's language (German, else English). */
@Composable
fun AnnouncementCards(model: AnnouncementsViewModel) {
    val items by model.visible.collectAsState()
    if (items.isEmpty()) return
    val language = Locale.getDefault().language
    Column(Modifier.fillMaxWidth().testTag("announcements"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        for (item in items) {
            val (title, body) = item.text(language)
            Card(Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.12f))) {
                Row(Modifier.padding(start = 16.dp, top = 8.dp, bottom = 12.dp, end = 4.dp), verticalAlignment = Alignment.Top) {
                    Column(Modifier.weight(1f).padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(title, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurface)
                        Text(body, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface)
                    }
                    val dismiss = stringResource(R.string.dismiss)
                    IconButton(onClick = { model.dismiss(item.id) }, modifier = Modifier.size(40.dp).testTag("announcement-dismiss").semantics { contentDescription = dismiss }) {
                        Text("✕", color = MaterialTheme.colorScheme.onSurface)
                    }
                }
            }
        }
    }
}
