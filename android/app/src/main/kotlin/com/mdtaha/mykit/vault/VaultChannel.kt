package com.mdtaha.mykit.vault

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.provider.Settings
import android.view.WindowManager
import android.view.autofill.AutofillManager
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.fragment.app.FragmentActivity
import com.mdtaha.mykit.autofill.AutofillLinks
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Native side of the Passwords tool (`lib/features/passwords/data/
 * datasources/vault_native_data_source.dart`): fingerprint unlock (see
 * [VaultKeyStore]), FLAG_SECURE while the vault is open, sensitive clipboard
 * copies cleared after a delay, and the autofill service switch.
 */
class VaultChannel(private val activity: FragmentActivity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.mdtaha.mykit/vault").apply {
        setMethodCallHandler(this@VaultChannel)
    }
    private val main = Handler(Looper.getMainLooper())
    private var clearClipboard: Runnable? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "biometricAvailable" -> result.success(
                BiometricManager.from(activity).canAuthenticate(BIOMETRIC_STRONG) ==
                    BiometricManager.BIOMETRIC_SUCCESS,
            )
            "hasBiometricKey" -> result.success(VaultKeyStore.hasKey(activity))
            "enrollBiometric" -> VaultKeyStore.enroll(
                activity,
                call.argument<ByteArray>("secret")!!,
            ) { reply(result, it) }
            "unlockBiometric" -> try {
                VaultKeyStore.unlock(activity, "Unlock passwords", "Use master password") {
                    reply(result, it)
                }
            } catch (e: VaultKeyStore.Invalidated) {
                result.error("invalidated", e.message, null)
            }
            "removeBiometric" -> {
                VaultKeyStore.remove(activity)
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
            "autofillEnabled" -> result.success(
                activity.getSystemService(AutofillManager::class.java)
                    ?.hasEnabledAutofillServices() == true,
            )
            "openAutofillSettings" -> {
                val intent = Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE)
                    .setData(Uri.parse("package:${activity.packageName}"))
                result.success(
                    try {
                        activity.startActivity(intent)
                        true
                    } catch (_: Exception) {
                        false
                    },
                )
            }
            "clearAutofillLinks" -> {
                AutofillLinks.clear(activity)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun reply(result: MethodChannel.Result, outcome: VaultKeyStore.Outcome) {
        when (outcome) {
            is VaultKeyStore.Outcome.Success -> result.success(outcome.value)
            VaultKeyStore.Outcome.Cancelled -> result.error("cancelled", "Cancelled", null)
            is VaultKeyStore.Outcome.Failed -> result.error("biometric", outcome.message, null)
        }
    }

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
}
