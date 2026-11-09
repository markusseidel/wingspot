package site.wingspot.app

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import java.io.File
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import site.wingspot.core.AircraftType
import site.wingspot.core.Airport
import site.wingspot.core.ReferenceDataInstaller
import site.wingspot.core.ReferenceDatabase

data class ReferenceState(
    val database: ReferenceDatabase? = null,
    val isDownloading: Boolean = false,
    val failed: Boolean = false,
    val airports: List<Airport> = emptyList(),
    val types: List<AircraftType> = emptyList(),
)

/**
 * Keeps the airport and aircraft data on the phone: opens what is installed, then checks for a newer snapshot and
 * installs it in the background. Search runs on the installed data, so it works offline.
 */
class ReferenceViewModel(private val installer: ReferenceDataInstaller) : ViewModel() {
    private val mutable = MutableStateFlow(ReferenceState(database = installer.installed()))
    val state: StateFlow<ReferenceState> = mutable.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        if (mutable.value.isDownloading) return
        mutable.value = mutable.value.copy(isDownloading = true, failed = false)
        viewModelScope.launch {
            try {
                val manifest = installer.manifest()
                val current = mutable.value.database
                if (manifest != null && manifest.dataVersion != current?.dataVersion) {
                    val installed = installer.install(manifest)
                    mutable.value = mutable.value.copy(database = installed)
                }
                mutable.value = mutable.value.copy(isDownloading = false)
            } catch (e: Exception) {
                // Keeps working with what is installed, if anything.
                mutable.value = mutable.value.copy(isDownloading = false, failed = mutable.value.database == null)
            }
        }
    }

    fun search(text: String) {
        val db = mutable.value.database
        if (db == null || text.isBlank()) {
            mutable.value = mutable.value.copy(airports = emptyList(), types = emptyList())
            return
        }
        viewModelScope.launch {
            val airports = db.searchAirports(text, 8)
            val types = db.searchTypes(text, 8)
            mutable.value = mutable.value.copy(airports = airports, types = types)
        }
    }

    companion object {
        fun factory(context: Context): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                ReferenceViewModel(
                    ReferenceDataInstaller(File(context.filesDir, "refdata"), BuildConfig.SUPABASE_URL + "/functions"),
                )
            }
        }
    }
}
