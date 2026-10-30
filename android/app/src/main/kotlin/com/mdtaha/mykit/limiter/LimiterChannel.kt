package com.mdtaha.mykit.limiter

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter side of the screen-time limiter (`lib/features/limiter/data/
 * limiter_native_data_source.dart`): settings in, usage out, and the
 * accessibility switch.
 */
class LimiterChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.mdtaha.mykit/limiter").apply {
        setMethodCallHandler(this@LimiterChannel)
    }
    private val store = LimiterStore.get(context)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setConfig" -> {
                store.saveConfig(call.argument<String>("json")!!)
                LimiterService.running?.refresh()
                result.success(null)
            }
            "status" -> {
                store.flush()
                result.success(
                    mapOf(
                        "enabled" to serviceEnabled(),
                        "usage" to store.usageJson(),
                        "extensions" to store.extensionsJson(),
                    ),
                )
            }
            "openSettings" -> {
                context.startActivity(
                    Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                result.success(null)
            }
            "setShortsActive" -> {
                LimiterService.shortsActive = call.argument<Boolean>("active") == true
                LimiterService.running?.refresh()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** The accessibility service is switched on in system settings. */
    private fun serviceEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val ours = ComponentName(context, LimiterService::class.java)
        return enabled.split(':').any {
            ComponentName.unflattenFromString(it) == ours
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
