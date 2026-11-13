package site.wingspot.app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import site.wingspot.core.Session
import site.wingspot.core.SessionUser

/**
 * Keeps the session on the phone. The tokens and the PKCE verifier are encrypted with an AES key that lives in the
 * Android Keystore and never leaves it, so a copy of the app's files is of no use. If the key is lost (for example
 * after a restore to another phone) the stored values can't be read and the user signs in again.
 */
class SessionStore(context: Context) {
    private val prefs = context.getSharedPreferences("session", Context.MODE_PRIVATE)

    fun load(): Session? {
        val access = secret("access") ?: return null
        val refresh = secret("refresh") ?: return null
        val id = prefs.getString("user_id", null) ?: return null
        return Session(access, refresh, 3600, SessionUser(id, prefs.getString("email", null)))
    }

    fun save(session: Session) {
        val access = seal(session.accessToken)
        val refresh = seal(session.refreshToken)
        prefs.edit()
            .putString("access_enc", access).putString("refresh_enc", refresh)
            .remove("access").remove("refresh") // tokens an earlier version stored in the clear
            .putString("user_id", session.user.id).putString("email", session.user.email)
            .putLong("expires_at", System.currentTimeMillis() + session.expiresIn * 1000).apply()
    }

    /** True when the access token is gone or has less than a minute left. A session saved without a time counts as expired. */
    fun expiresSoon(): Boolean = prefs.getLong("expires_at", 0) - System.currentTimeMillis() < 60_000

    fun clear() = prefs.edit().clear().apply()

    /** The PKCE verifier waits here while the email is on its way, as the app may be stopped meanwhile. */
    fun saveVerifier(verifier: String) = prefs.edit().putString("verifier_enc", seal(verifier)).remove("verifier").apply()
    fun verifier(): String? = secret("verifier")

    /** Reads an encrypted value; one an earlier version stored in the clear is accepted and encrypted on the spot. */
    private fun secret(name: String): String? {
        prefs.getString("${name}_enc", null)?.let { return open(it) }
        val plain = prefs.getString(name, null) ?: return null
        prefs.edit().putString("${name}_enc", seal(plain)).remove(name).apply()
        return plain
    }

    private fun seal(text: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.ENCRYPT_MODE, key()) }
        return Base64.encodeToString(cipher.iv + cipher.doFinal(text.toByteArray()), Base64.NO_WRAP)
    }

    private fun open(sealed: String): String? = try {
        val bytes = Base64.decode(sealed, Base64.NO_WRAP)
        val cipher = Cipher.getInstance(TRANSFORMATION)
            .apply { init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes, 0, IV_BYTES)) }
        String(cipher.doFinal(bytes, IV_BYTES, bytes.size - IV_BYTES))
    } catch (_: Exception) {
        null
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    private companion object {
        const val ALIAS = "wingspot_session"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_BYTES = 12
    }
}
