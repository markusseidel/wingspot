package site.wingspot.app

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
import site.wingspot.core.AuthException
import site.wingspot.core.Pkce
import site.wingspot.core.Session
import site.wingspot.core.SupabaseAuth

data class AppState(
    val session: Session? = null,
    val sentTo: String? = null,
    val isWorking: Boolean = false,
    /** A string resource ID for the message to show. */
    val error: Int? = null,
)

class AppViewModel(
    private val store: SessionStore,
    private val auth: SupabaseAuth,
    private val onSignedIn: () -> Unit,
    private val deleteRemote: suspend () -> Unit,
) : ViewModel() {
    private val mutable = MutableStateFlow(AppState(session = store.load()))
    val state: StateFlow<AppState> = mutable.asStateFlow()

    fun sendLink(email: String) {
        if (mutable.value.isWorking) return
        mutable.value = mutable.value.copy(isWorking = true, error = null)
        viewModelScope.launch {
            try {
                val pkce = Pkce.create()
                store.saveVerifier(pkce.verifier)
                auth.sendSignInLink(email.trim(), Locale.getDefault().language, pkce)
                mutable.value = mutable.value.copy(sentTo = email.trim(), isWorking = false)
            } catch (e: AuthException) {
                mutable.value = mutable.value.copy(isWorking = false, error = message(e))
            }
        }
    }

    fun completeSignIn(link: String) {
        val verifier = store.verifier()
        if (verifier == null) {
            mutable.value = mutable.value.copy(error = R.string.error_invalid_link)
            return
        }
        viewModelScope.launch {
            try {
                val session = auth.completeSignIn(link, Pkce.fromVerifier(verifier))
                store.save(session)
                mutable.value = AppState(session = session)
                onSignedIn()
            } catch (e: AuthException) {
                mutable.value = mutable.value.copy(error = message(e))
            }
        }
    }

    /** Signs in with an email and a password. */
    fun signInWithPassword(email: String, password: String) = signInWith { auth.signInWithPassword(email.trim(), password) }

    /** Signs in with an identity token from Google. [nonce] is the raw nonce whose hash Google put into the token. */
    fun signInWithGoogle(idToken: String, nonce: String) = signInWith { auth.signInWithIdToken("google", idToken, nonce) }

    /** The person closed or refused the Google sheet, or Google isn't available on this phone. */
    fun googleFailed() {
        mutable.value = mutable.value.copy(isWorking = false, error = R.string.error_google)
    }

    private fun signInWith(get: suspend () -> site.wingspot.core.Session) {
        if (mutable.value.isWorking) return
        mutable.value = mutable.value.copy(isWorking = true, error = null)
        viewModelScope.launch {
            try {
                val session = get()
                store.save(session)
                mutable.value = AppState(session = session)
                onSignedIn()
            } catch (e: AuthException) {
                mutable.value = mutable.value.copy(isWorking = false, error = message(e))
            }
        }
    }

    fun useOtherEmail() {
        mutable.value = mutable.value.copy(sentTo = null, error = null)
    }

    /** Deletes the account on the server, for good, and then forgets the session. Throws when the server can't be reached. */
    suspend fun deleteAccount() {
        deleteRemote()
        store.clear()
        mutable.value = AppState()
    }

    fun signOut() {
        store.clear()
        mutable.value = AppState()
    }

    private fun message(e: AuthException) = when (e) {
        AuthException.InvalidEmail -> R.string.error_invalid_email
        AuthException.InvalidLogin -> R.string.error_invalid_login
        AuthException.InvalidLink -> R.string.error_invalid_link
        AuthException.TooManyRequests -> R.string.error_too_many
        AuthException.Offline -> R.string.error_offline
        AuthException.Unknown -> R.string.error_unknown
    }

    companion object {
        fun factory(app: WingspotApp): ViewModelProvider.Factory = viewModelFactory {
            initializer { AppViewModel(app.sessions, app.auth, { OutboxWorker.schedule(app) }, app::deleteAccount) }
        }
    }
}
