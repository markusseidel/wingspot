package site.wingspot.app

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import site.wingspot.core.ApiException
import site.wingspot.core.Celebration
import site.wingspot.core.Celebrations
import site.wingspot.core.SocialApi
import site.wingspot.core.UserProgress

data class BadgesState(
    val progress: UserProgress? = null,
    val celebrations: List<Celebration> = emptyList(),
    /** True when the last refresh failed. The last known progress stays. */
    val refreshFailed: Boolean = false,
)

/** XP, level and badges, and what still has to be celebrated. */
class BadgesViewModel(private val api: SocialApi, private val prefs: Prefs) : ViewModel() {
    private val mutable = MutableStateFlow(BadgesState())
    val state: StateFlow<BadgesState> = mutable.asStateFlow()
    private var user: String? = null

    /** Call when the signed-in person changes. Shows the last known progress at once. */
    fun begin(userId: String?) {
        if (userId == user) return
        user = userId
        mutable.value = BadgesState(progress = userId?.let { prefs.cachedProgress(it) }?.let { runCatching { api.parseProgress(it) }.getOrNull() })
        if (userId != null) refresh()
    }

    fun refresh() {
        val me = user ?: return
        viewModelScope.launch {
            try {
                val text = api.progressJson()
                if (me != user) return@launch
                val progress = api.parseProgress(text)
                val result = Celebrations.compute(progress, prefs.acks(me), prefs.firstSeen(me))
                prefs.setAcks(me, result.newAcks)
                prefs.cacheProgress(me, text)
                mutable.value = BadgesState(progress, result.celebrations, false)
            } catch (e: ApiException) {
                mutable.value = mutable.value.copy(refreshFailed = true)
            } catch (e: Exception) {
                mutable.value = mutable.value.copy(refreshFailed = true)
            }
        }
    }

    /** The person has seen the celebrations. */
    fun acknowledge() {
        val me = user ?: return
        prefs.setAcks(me, mutable.value.celebrations.associate { it.badge.id to it.badge.level })
        mutable.value = mutable.value.copy(celebrations = emptyList())
    }

    companion object {
        fun factory(app: WingspotApp): ViewModelProvider.Factory = viewModelFactory { initializer { BadgesViewModel(app.social, app.prefs) } }
    }
}
