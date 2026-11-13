package site.wingspot.app

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
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
import site.wingspot.core.FeedCursor
import site.wingspot.core.FeedItem
import site.wingspot.core.FeedPhoto
import site.wingspot.core.SocialApi

enum class Tab { FEED, CHECK_IN, PEOPLE, ACCOUNT }

/** A page above the tabs. */
sealed class Route {
    data class CheckInPage(val id: String) : Route()
    data class PersonPage(val id: String) : Route()
}

data class FeedState(
    val items: List<FeedItem> = emptyList(),
    val photos: Map<String, List<FeedPhoto>> = emptyMap(),
    val isLoading: Boolean = false,
    val reachedEnd: Boolean = false,
    val hasLoaded: Boolean = false,
    val failed: Boolean = false,
)

/** The Feed tab's data and the pages opened from it: your check-ins and those of people you follow, newest first, in pages. */
class SocialViewModel(private val api: SocialApi, private val me: () -> String?) : ViewModel() {
    private val mutable = MutableStateFlow(FeedState())
    val state: StateFlow<FeedState> = mutable.asStateFlow()

    var tab: Tab by mutableStateOf(Tab.CHECK_IN)
    val stack = mutableStateListOf<Route>()
    /** Check-ins opened from a person's page or by id, so the page has something to show before it is loaded again. */
    val opened = mutableMapOf<String, FeedItem>()

    private var generation = 0

    fun open(item: FeedItem) {
        opened[item.id] = item
        stack.add(Route.CheckInPage(item.id))
    }

    fun openPerson(id: String) {
        stack.add(Route.PersonPage(id))
    }

    fun back() {
        if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex)
    }

    fun refresh() {
        if (me() == null) return
        val mine = ++generation
        mutable.value = mutable.value.copy(isLoading = true, failed = false)
        viewModelScope.launch {
            try {
                val page = api.feed(null, PAGE)
                if (mine != generation) return@launch
                mutable.value = FeedState(page, loadPhotos(page), false, page.size < PAGE, true, false)
            } catch (e: ApiException) {
                if (mine == generation) mutable.value = mutable.value.copy(isLoading = false, failed = true, hasLoaded = true)
            }
        }
    }

    fun loadMore() {
        val now = mutable.value
        val last = now.items.lastOrNull() ?: return
        if (now.isLoading || now.reachedEnd) return
        val mine = generation
        mutable.value = now.copy(isLoading = true)
        viewModelScope.launch {
            try {
                val page = api.feed(FeedCursor(last.occurredAt, last.id), PAGE)
                if (mine != generation) return@launch
                val known = mutable.value.items.map { it.id }.toSet()
                val fresh = page.filter { it.id !in known }
                mutable.value = mutable.value.copy(
                    items = mutable.value.items + fresh, photos = mutable.value.photos + loadPhotos(fresh),
                    isLoading = false, reachedEnd = page.size < PAGE,
                )
            } catch (e: ApiException) {
                if (mine == generation) mutable.value = mutable.value.copy(isLoading = false, failed = true)
            }
        }
    }

    private suspend fun loadPhotos(items: List<FeedItem>): Map<String, List<FeedPhoto>> =
        try {
            api.photos(items.map { it.id }).groupBy { it.checkInId }
        } catch (e: ApiException) {
            emptyMap() // the cards show without their photos
        }

    /** Salutes or un-salutes. The card changes at once and goes back if the request fails. */
    fun toggleSalute(id: String) {
        val user = me() ?: return
        val before = mutable.value.items.firstOrNull { it.id == id } ?: return
        val on = !before.saluted
        replace(before.copy(saluted = on, salutes = (before.salutes + if (on) 1 else -1).coerceAtLeast(0)))
        viewModelScope.launch {
            try {
                api.setSalute(on, id, user)
            } catch (e: ApiException) {
                replace(before)
            }
        }
    }

    /** Keeps a count in step after the check-in page changed it. */
    fun setCommentCount(id: String, count: Int) {
        mutable.value.items.firstOrNull { it.id == id }?.let { replace(it.copy(comments = count)) }
    }

    private fun replace(item: FeedItem) {
        mutable.value = mutable.value.copy(items = mutable.value.items.map { if (it.id == item.id) item else it })
    }

    fun remove(id: String) {
        mutable.value = mutable.value.copy(items = mutable.value.items.filterNot { it.id == id }, photos = mutable.value.photos - id)
    }

    fun clear() {
        generation++
        mutable.value = FeedState()
        stack.clear()
        opened.clear()
    }

    companion object {
        private const val PAGE = 30

        fun factory(app: WingspotApp): ViewModelProvider.Factory = viewModelFactory {
            initializer { SocialViewModel(app.social) { app.sessions.load()?.user?.id } }
        }
    }
}
