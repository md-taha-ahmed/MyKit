package com.mdtaha.mykit.calendar

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.CalendarContract
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Read-only access to the device calendar for Dart
 * (`lib/core/calendar/device_calendar_service.dart`).
 */
class CalendarChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.mdtaha.mykit/calendar"
        const val PERMISSION_REQUEST_CODE = 4821
    }

    private val channel = MethodChannel(messenger, CHANNEL).apply {
        setMethodCallHandler(this@CalendarChannel)
    }
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermission" -> result.success(hasPermission())
            "requestPermission" -> requestPermission(result)
            "openSettings" -> {
                activity.startActivity(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", activity.packageName, null),
                    ),
                )
                result.success(null)
            }
            "getEvents" -> {
                if (!hasPermission()) {
                    result.error("PERMISSION_DENIED", "Calendar permission not granted", null)
                    return
                }
                val start = call.argument<Number>("start")!!.toLong()
                val end = call.argument<Number>("end")!!.toLong()
                try {
                    result.success(queryEvents(start, end))
                } catch (e: Exception) {
                    result.error("QUERY_FAILED", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun hasPermission() =
        activity.checkSelfPermission(Manifest.permission.READ_CALENDAR) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestPermission(result: MethodChannel.Result) {
        if (hasPermission()) {
            result.success(true)
            return
        }
        pendingPermissionResult?.success(false)
        pendingPermissionResult = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.READ_CALENDAR),
            PERMISSION_REQUEST_CODE,
        )
    }

    /** Called from [com.mdtaha.mykit.MainActivity.onRequestPermissionsResult]. */
    fun onPermissionResult(granted: Boolean) {
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    /** Event instances (recurring events expanded) between [start] and [end] millis. */
    private fun queryEvents(start: Long, end: Long): List<Map<String, Any?>> {
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, start)
            ContentUris.appendId(it, end)
        }.build()

        val projection = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
            CalendarContract.Instances.DISPLAY_COLOR,
        )

        val events = mutableListOf<Map<String, Any?>>()
        activity.contentResolver.query(
            uri,
            projection,
            null,
            null,
            "${CalendarContract.Instances.BEGIN} ASC",
        )?.use { c ->
            while (c.moveToNext()) {
                events += mapOf(
                    "id" to c.getLong(0).toString(),
                    "title" to (c.getString(1) ?: ""),
                    "begin" to c.getLong(2),
                    "allDay" to (c.getInt(3) == 1),
                    "calendar" to (c.getString(4) ?: ""),
                    "color" to c.getInt(5),
                )
            }
        }
        return events
    }

    fun dispose() = channel.setMethodCallHandler(null)
}
