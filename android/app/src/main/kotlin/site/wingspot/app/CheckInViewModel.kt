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
import site.wingspot.core.AircraftType
import site.wingspot.core.Airport
import site.wingspot.core.CheckInStore
import site.wingspot.core.LocalCheckIn
import site.wingspot.core.Registration
import site.wingspot.core.SpottedDraft
import site.wingspot.core.SpottedResult

data class CheckInState(
    val isOpen: Boolean = false,
    val result: SpottedResult? = null,
    val recent: List<LocalCheckIn> = emptyList(),
    val saveFailed: Boolean = false,
)

/** Saves spotted check-ins on the phone first, then asks for an upload. Works fully offline. */
class CheckInViewModel(private val store: CheckInStore, private val requestUpload: () -> Unit) : ViewModel() {
    private val mutable = MutableStateFlow(CheckInState())
    val state: StateFlow<CheckInState> = mutable.asStateFlow()

    init {
        reload()
    }

    fun open() {
        mutable.value = mutable.value.copy(isOpen = true, result = null, saveFailed = false)
    }

    fun close() {
        mutable.value = mutable.value.copy(isOpen = false, result = null)
    }

    /** Starts the next check-in. The form keeps its airport, because spotters log several planes in one place. */
    fun another() {
        mutable.value = mutable.value.copy(result = null)
    }

    fun save(registration: Registration?, type: AircraftType?, airport: Airport?) {
        val draft = SpottedDraft(registration, type?.icaoCode, airport?.id)
        if (!draft.hasAircraft) return
        viewModelScope.launch {
            try {
                val result = store.saveSpotted(draft)
                mutable.value = mutable.value.copy(result = result, saveFailed = false)
                requestUpload()
                reload()
            } catch (e: Exception) {
                mutable.value = mutable.value.copy(saveFailed = true)
            }
        }
    }

    /** Called after an upload may have changed the states. */
    fun reload() {
        viewModelScope.launch { mutable.value = mutable.value.copy(recent = store.recent(10)) }
    }

    companion object {
        fun factory(app: WingspotApp): ViewModelProvider.Factory = viewModelFactory {
            initializer { CheckInViewModel(app.checkIns) { OutboxWorker.schedule(app) } }
        }
    }
}
