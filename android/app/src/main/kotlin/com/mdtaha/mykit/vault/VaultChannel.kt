package com.mdtaha.mykit.vault

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import android.view.WindowManager
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Native side of the Passwords tool (`lib/features/passwords/data/
 * vault_native_data_source.dart`):
 *
 * - Fingerprint unlock: the vault key is encrypted with an Android Keystore
 *   AES key that can only be used right after a strong biometric check
 *   (BiometricPrompt + CryptoObject) and is wiped if fingerprints change.
 *   The encrypted copy lives in its own preferences file, which backups skip.
 * - FLAG_SECURE while the vault is open (no screenshots / recents preview).
 * - Clipboard copies marked sensitive and cleared after a delay.
 */
class VaultChannel(private val activity: FragmentActivity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.mdtaha.mykit/vault").apply {
        setMethodCallHandler(this@VaultChannel)
    }
    private val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val main = Handler(Looper.getMainLooper())
    private var clearClipboard: Runnable? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "biometricAvailable" -> result.success(
                BiometricManager.from(activity).canAuthenticate(BIOMETRIC_STRONG) ==
                    BiometricManager.BIOMETRIC_SUCCESS,
            )
            "hasBiometricKey" -> result.success(prefs.contains(KEY_DATA))
            "enrollBiometric" -> enroll(call.argument<ByteArray>("secret")!!, result)
            "unlockBiometric" -> unlock(result)
            "removeBiometric" -> {
                removeKey()
                result.success(null)
            }
            "setSecure" -> {
                if (call.argument<Boolean>("on") == true) {
                    activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                } else {
                    activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                result.success(null)
            }
            "copySensitive" -> {
                copy(call.argument<String>("text")!!, call.argument<Int>("clearAfterMs") ?: 30000)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // --- Biometric key ---------------------------------------------------

    private fun enroll(secret: ByteArray, result: MethodChannel.Result) {
        try {
            removeKey()
            val cipher = Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.ENCRYPT_MODE, createKey())
            }
            prompt(cipher, "Turn on fingerprint unlock", result) { authed ->
                val encrypted = authed.doFinal(secret)
                prefs.edit()
                    .putString(KEY_IV, Base64.encodeToString(authed.iv, Base64.NO_WRAP))
                    .putString(KEY_DATA, Base64.encodeToString(encrypted, Base64.NO_WRAP))
                    .apply()
                true
            }
        } catch (e: Exception) {
            result.error("biometric", e.message ?: "Could not set up fingerprint unlock", null)
        }
    }

    private fun unlock(result: MethodChannel.Result) {
        val iv = prefs.getString(KEY_IV, null)
        val data = prefs.getString(KEY_DATA, null)
        if (iv == null || data == null) {
            result.error("missing", "Fingerprint unlock is not set up", null)
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
            // Fingerprints changed: the key is gone for good; use the password.
            removeKey()
            result.error("invalidated", "Fingerprints changed. Unlock with your master password.", null)
            return
        } catch (e: Exception) {
            result.error("biometric", e.message ?: "Fingerprint unlock failed", null)
            return
        }
        prompt(cipher, "Unlock passwords", result) { authed ->
            authed.doFinal(Base64.decode(data, Base64.NO_WRAP))
        }
    }

    private fun prompt(
        cipher: Cipher,
        title: String,
        result: MethodChannel.Result,
        onAuthed: (Cipher) -> Any,
    ) {
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                val authed = r.cryptoObject?.cipher
                if (authed == null) {
                    result.error("biometric", "No cipher", null)
                    return
                }
                try {
                    result.success(onAuthed(authed))
                } catch (e: Exception) {
                    result.error("biometric", e.message ?: "Fingerprint unlock failed", null)
                }
            }

            override fun onAuthenticationError(code: Int, message: CharSequence) {
                val cancelled = code == BiometricPrompt.ERROR_USER_CANCELED ||
                    code == BiometricPrompt.ERROR_NEGATIVE_BUTTON ||
                    code == BiometricPrompt.ERROR_CANCELED
                result.error(if (cancelled) "cancelled" else "biometric", message.toString(), null)
            }
        }
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle("MyKit")
            .setNegativeButtonText("Use master password")
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

    private fun removeKey() {
        try {
            keyStore().deleteEntry(ALIAS)
        } catch (_: Exception) {
        }
        prefs.edit().clear().apply()
    }

    // --- Clipboard -------------------------------------------------------

    private fun copy(text: String, clearAfterMs: Int) {
        val clipboard = activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newPlainText("MyKit", text).apply {
            // Keeps the keyboard / clipboard preview from showing it (Android 13+).
            description.extras = PersistableBundle().apply {
                putBoolean(
                    if (Build.VERSION.SDK_INT >= 33) ClipDescription.EXTRA_IS_SENSITIVE
                    else "android.content.extra.IS_SENSITIVE",
                    true,
                )
            }
        }
        clipboard.setPrimaryClip(clip)
        clearClipboard?.let(main::removeCallbacks)
        clearClipboard = Runnable {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                clipboard.clearPrimaryClip()
            } else {
                clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
            }
        }.also { main.postDelayed(it, clearAfterMs.toLong()) }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    companion object {
        /** Also listed in BackupPlugin's skip list: device-bound, never backed up. */
        const val PREFS = "vault_biometric"
        private const val KEY_IV = "iv"
        private const val KEY_DATA = "data"
        private const val ALIAS = "mykit_vault_biometric"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
