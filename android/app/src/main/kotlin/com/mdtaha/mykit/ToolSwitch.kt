package com.mdtaha.mykit

import android.content.Context

/**
 * Sections turned off in MyKit's Settings (`lib/core/tools/tool_switch.dart`
 * saves them as comma-separated ids in `tools.disabled`), for the parts that
 * run outside Flutter: Screen time and password autofill.
 */
object ToolSwitch {
    const val SCREEN_TIME = "screen-time"
    const val PASSWORDS = "passwords"

    fun isOff(context: Context, id: String): Boolean =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.tools.disabled", null)
            ?.split(',')
            ?.contains(id) == true
}
