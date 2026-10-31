package com.mdtaha.mykit.setup

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.autofill.AutofillManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Setup checklist (`lib/features/setup/`): is MyKit allowed to run in the
 * background, is it the autofill service, and shortcuts to those settings.
 */
class SetupChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.mdtaha.mykit/setup").apply {
        setMethodCallHandler(this@SetupChannel)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(
                mapOf(
                    "batteryUnrestricted" to batteryUnrestricted(),
                    "autofill" to autofillIsMyKit(),
                ),
            )
            "requestBattery" -> {
                open(batteryIntent())
                result.success(null)
            }
            "requestAutofill" -> {
                open(
                    Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE)
                        .setData(Uri.parse("package:${context.packageName}")),
                    fallback = Intent(Settings.ACTION_SETTINGS),
                )
                result.success(null)
            }
            "openAppSettings" -> {
                open(appDetails())
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun batteryUnrestricted(): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun autofillIsMyKit(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = context.getSystemService(AutofillManager::class.java) ?: return false
        return try {
            manager.hasEnabledAutofillServices()
        } catch (_: Exception) {
            false
        }
    }

    /** The system "allow this app to run in the background?" dialog. */
    @SuppressLint("BatteryLife")
    private fun batteryIntent() =
        Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            .setData(Uri.parse("package:${context.packageName}"))

    private fun appDetails() =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
            .setData(Uri.parse("package:${context.packageName}"))

    private fun open(intent: Intent, fallback: Intent = appDetails()) {
        try {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Exception) {
            context.startActivity(fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
