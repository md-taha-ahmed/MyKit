package com.mdtaha.mykit.vault

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The fingerprint-protected copy of the Passwords vault key, shared by the
 * app ([VaultChannel]) and autofill ([com.mdtaha.mykit.autofill.AutofillAuthActivity]).
 *
 * An Android Keystore AES key that can only be used right after a strong
 * biometric check (and is wiped if fingerprints change) encrypts the vault
 * key; the encrypted copy lives in its own preferences file, which backups
 * skip.
 */
object VaultKeyStore {
    /** Also in BackupPlugin's skip list: device-bound, never backed up. */
    const val PREFS = "vault_biometric"
    private const val KEY_IV = "iv"
    private const val KEY_DATA = "data"
    private const val ALIAS = "mykit_vault_biometric"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"

    class Invalidated : Exception("Fingerprints changed. Unlock with your master password.")

    sealed interface Outcome {
        class Success(val value: Any) : Outcome
        object Cancelled : Outcome
        class Failed(val message: String) : Outcome
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun hasKey(context: Context) = prefs(context).contains(KEY_DATA)

    /** Asks for a fingerprint, then stores [secret] behind it. */
    fun enroll(activity: FragmentActivity, secret: ByteArray, done: (Outcome) -> Unit) {
        try {
            remove(activity)
            val cipher = Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.ENCRYPT_MODE, createKey())
            }
            prompt(activity, cipher, "Turn on fingerprint unlock", "Cancel", done) { authed ->
                val encrypted = authed.doFinal(secret)
                prefs(activity).edit()
                    .putString(KEY_IV, Base64.encodeToString(authed.iv, Base64.NO_WRAP))
                    .putString(KEY_DATA, Base64.encodeToString(encrypted, Base64.NO_WRAP))
                    .apply()
                true
            }
        } catch (e: Exception) {
            done(Outcome.Failed(e.message ?: "Could not set up fingerprint unlock"))
        }
    }

    /**
     * Asks for a fingerprint and returns the vault key (a ByteArray in
     * [Outcome.Success]). Throws [Invalidated] (before prompting) when
     * fingerprints changed; the key is then removed.
     */
    fun unlock(
        activity: FragmentActivity,
        title: String,
        negative: String = "Cancel",
        done: (Outcome) -> Unit,
    ) {
        val prefs = prefs(activity)
        val iv = prefs.getString(KEY_IV, null)
        val data = prefs.getString(KEY_DATA, null)
        if (iv == null || data == null) {
            done(Outcome.Failed("Fingerprint unlock is not set up"))
            return
        }
        val cipher = try {
            Cipher.getInstance(TRANSFORMATION).apply {
                init(
                    Cipher.DECRYPT_MODE,
                    loadKey() ?: throw KeyPermanentlyInvalidatedException(),
                    GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)),
                )
            }
        } catch (e: KeyPermanentlyInvalidatedException) {
            remove(activity)
            throw Invalidated()
        }
        prompt(activity, cipher, title, negative, done) { authed ->
            authed.doFinal(Base64.decode(data, Base64.NO_WRAP))
        }
    }

    fun remove(context: Context) {
        try {
            keyStore().deleteEntry(ALIAS)
        } catch (_: Exception) {
        }
        prefs(context).edit().clear().apply()
    }

    private fun prompt(
        activity: FragmentActivity,
        cipher: Cipher,
        title: String,
        negative: String,
        done: (Outcome) -> Unit,
        onAuthed: (Cipher) -> Any,
    ) {
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                val authed = r.cryptoObject?.cipher
                if (authed == null) {
                    done(Outcome.Failed("No cipher"))
                    return
                }
                done(
                    try {
                        Outcome.Success(onAuthed(authed))
                    } catch (e: Exception) {
                        Outcome.Failed(e.message ?: "Fingerprint unlock failed")
                    },
                )
            }

            override fun onAuthenticationError(code: Int, message: CharSequence) {
                val cancelled = code == BiometricPrompt.ERROR_USER_CANCELED ||
                    code == BiometricPrompt.ERROR_NEGATIVE_BUTTON ||
                    code == BiometricPrompt.ERROR_CANCELED
                done(if (cancelled) Outcome.Cancelled else Outcome.Failed(message.toString()))
            }
        }
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle("MyKit")
            .setNegativeButtonText(negative)
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .build()
        BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
            .authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }

    private fun keyStore() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun loadKey(): SecretKey? = keyStore().getKey(ALIAS, null) as? SecretKey

    private fun createKey(): SecretKey {
        val spec = KeyGenParameterSpec.Builder(
            ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
                }
            }
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            .apply { init(spec) }
            .generateKey()
    }
}
