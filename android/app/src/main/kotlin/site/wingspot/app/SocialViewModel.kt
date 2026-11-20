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
import site.wingspot.core.FeedSort
import site.wingspot.core.FeedPhoto
import site.wingspot.core.SocialApi

enum class Tab { FEED, CHECK_IN, EXPLORE, BADGES, PROFILE }

/** A page above the tabs. */
sealed class Route {
    data class CheckInPage(val id: String) : Route()
    data class PersonPage(val id: String) : Route()
    data class ComparePage(val id: String, val name: String) : Route()
    data class AirportPage(val id: Long) : Route()
    data class TypePage(val code: String) : Route()
    data class RegistrationPage(val registration: String) : Route()
    object ExploreMap : Route()
    object AirportsMap : Route()
    object Collections : Route()
    object Leaderboard : Route()
    object Settings : Route()
    object Inbox : Route()
    object EditProfile : Route()
}

data class FeedState(
    val items: List<FeedItem> = emptyList(),
    val photos: Map<String, List<FeedPhoto>> = emptyMap(),
    /** The friends tagged on the check-ins in [items]. */
    val tags: Map<String, List<site.wingspot.core.Person>> = emptyMap(),
    /** The badges the check-ins in [items] earned. */
    val badges: Map<String, List<SocialApi.FeedBadge>> = emptyMap(),
    val isLoading: Boolean = false,
    val reachedEnd: Boolean = false,
    val hasLoaded: Boolean = false,
    val failed: Boolean = false,
)

/** The Feed tab's data and the pages opened from it: your check-ins and those of people you follow, newest first, in pages. */
class SocialViewModel(
    private val api: SocialApi, private val me: () -> String?, initialSort: FeedSort = FeedSort.CREATED,
    private val saveSort: (FeedSort) -> Unit = {},
) : ViewModel() {
    private val mutable = MutableStateFlow(FeedState())
    val state: StateFlow<FeedState> = mutable.asStateFlow()

    /** How the Feed tab is sorted. New check-ins show first by default. */
    var sort: FeedSort by mutableStateOf(initialSort)
        private set

    fun chooseSort(value: FeedSort) {
        if (value == sort) return
        sort = value
        saveSort(value)
        refresh()
    }

    var tab: Tab by mutableStateOf(Tab.CHECK_IN)
    val stack = mutableStateListOf<Route>()
    /** Check-ins opened from a person's page or by id, so the page has something to show before it is loaded again. */
    val opened = mutableMapOf<String, FeedItem>()

    private var generation = 0

    fun open(item: FeedItem) {
        opened[item.id] = item
        stack.add(Route.CheckInPage(item.id))
    }

    /** Opens a page above the tabs that needs no check-in, such as Settings. */
    fun open(route: Route) {
        stack.add(route)
    }

    fun openPerson(id: String) {
        stack.add(Route.PersonPage(id))
    }

    // Activity inbox ---------------------------------------------------------------------------------------------

    /** What is unread in the inbox, up to 99. Drives the dot on the bell. */
    var unread by mutableStateOf(0)
        private set
    var inbox by mutableStateOf(emptyList<SocialApi.ActivityItem>())
        private set
    var inboxLoaded by mutableStateOf(false)
        private set
    var inboxFailed by mutableStateOf(false)
        private set
    var inboxMore by mutableStateOf(false)
        private set

    fun refreshUnread() {
        if (me() == null) return
        viewModelScope.launch { try { unread = api.unreadActivityCount() } catch (e: ApiException) { } }
    }

    /** Loads the first page. Nothing is marked read by looking: the person does that with "Mark all read". */
    fun loadInbox() {
        if (me() == null) return
        viewModelScope.launch {
            try {
                val page = api.activity(null, INBOX_PAGE)
                inbox = page
                inboxMore = page.size >= INBOX_PAGE
                inboxFailed = false
                inboxLoaded = true
                refreshUnread()
            } catch (e: ApiException) {
                inboxFailed = true
                inboxLoaded = true
            }
        }
    }

    val inboxHasUnread: Boolean get() = unread > 0 || inbox.any { !it.isRead }

    fun markAllRead() {
        val before = inbox to unread
        inbox = inbox.map { it.copy(isRead = true) }
        unread = 0
        viewModelScope.launch {
            try { api.markActivityRead() } catch (e: ApiException) { inbox = before.first; unread = before.second }
        }
    }

    fun loadMoreInbox() {
        val last = inbox.lastOrNull() ?: return
        if (!inboxMore) return
        inboxMore = false
        viewModelScope.launch {
            try {
                val page = api.activity(last.createdAt, INBOX_PAGE)
                val known = inbox.map { it.id }.toSet()
                inbox = inbox + page.filter { it.id !in known }
                inboxMore = page.size >= INBOX_PAGE
            } catch (e: ApiException) {
                inboxMore = true
            }
        }
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
                val page = api.feed(null, PAGE, sort)
                if (mine != generation) return@launch
                mutable.value = FeedState(items = page, photos = loadPhotos(page), tags = loadTags(page), badges = loadBadges(page), isLoading = false, reachedEnd = page.size < PAGE, hasLoaded = true, failed = false)
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
                val page = api.feed(FeedCursor(last.cursorTime ?: last.occurredAt, last.id), PAGE, sort)
                if (mine != generation) return@launch
                val known = mutable.value.items.map { it.id }.toSet()
                val fresh = page.filter { it.id !in known }
                mutable.value = mutable.value.copy(
                    items = mutable.value.items + fresh, photos = mutable.value.photos + loadPhotos(fresh), tags = mutable.value.tags + loadTags(fresh), badges = mutable.value.badges + loadBadges(fresh),
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

    private suspend fun loadTags(items: List<FeedItem>): Map<String, List<site.wingspot.core.Person>> =
        try {
            api.tags(items.map { it.id })
        } catch (e: ApiException) {
            emptyMap() // the cards show without their friends
        }

    suspend fun loadBadges(items: List<FeedItem>): Map<String, List<SocialApi.FeedBadge>> =
        try {
            api.badges(items.map { it.id })
        } catch (e: ApiException) {
            emptyMap() // the cards show without their badges
        }

    /** The tags of one check-in, loaded again, for example after they were changed. */
    suspend fun reloadTags(id: String): List<site.wingspot.core.Person> {
        val found = try { api.tags(listOf(id))[id].orEmpty() } catch (e: ApiException) { return mutable.value.tags[id].orEmpty() }
        mutable.value = mutable.value.copy(tags = mutable.value.tags + (id to found))
        return found
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
        mutable.value = mutable.value.copy(items = mutable.value.items.filterNot { it.id == id }, photos = mutable.value.photos - id, tags = mutable.value.tags - id, badges = mutable.value.badges - id)
    }

    fun clear() {
        generation++
        mutable.value = FeedState()
        stack.clear()
        opened.clear()
        unread = 0
        inbox = emptyList()
        inboxLoaded = false
        inboxFailed = false
        inboxMore = false
    }

    companion object {
        private const val PAGE = 30
        private const val INBOX_PAGE = 30

        fun factory(app: WingspotApp): ViewModelProvider.Factory = viewModelFactory {
            initializer { SocialViewModel(app.social, { app.sessions.load()?.user?.id }, app.prefs.feedSort, app.prefs::chooseFeedSort) }
        }
    }
}
