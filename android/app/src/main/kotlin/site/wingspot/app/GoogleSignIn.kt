package site.wingspot.app

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

/** Sign in with Google through the system's account sheet. The button only shows when the build knows the Google client id. */
object GoogleSignIn {
    val isAvailable: Boolean get() = BuildConfig.GOOGLE_WEB_CLIENT_ID.isNotBlank()

    /** A Google identity token and the raw nonce that goes with it, or null if the person closed the sheet or Google isn't available. */
    suspend fun idToken(activityContext: Context): Pair<String, String>? {
        // Google puts the hash of the nonce into the token. Supabase gets the raw one and checks the hash.
        val raw = Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(32).also(SecureRandom()::nextBytes))
        val hashed = MessageDigest.getInstance("SHA-256").digest(raw.toByteArray()).joinToString("") { "%02x".format(it) }
        val option = GetGoogleIdOption.Builder()
            .setFilterByAuthorizedAccounts(false)
            .setServerClientId(BuildConfig.GOOGLE_WEB_CLIENT_ID)
            .setNonce(hashed)
            .build()
        return try {
            val result = CredentialManager.create(activityContext).getCredential(activityContext, GetCredentialRequest.Builder().addCredentialOption(option).build())
            val credential = result.credential
            if (credential is CustomCredential && credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
                GoogleIdTokenCredential.createFrom(credential.data).idToken to raw
            } else {
                null
            }
        } catch (e: GetCredentialException) {
            null
        } catch (e: Exception) {
            null
        }
    }
}
