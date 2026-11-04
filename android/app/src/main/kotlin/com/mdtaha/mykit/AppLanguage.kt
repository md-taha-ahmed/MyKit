package com.mdtaha.mykit

import android.content.Context
import java.util.Locale

/**
 * The language chosen in MyKit's Settings (`lib/core/i18n/i18n.dart` saves
 * it as `app.language`), for the screens Android shows outside Flutter: the
 * Screen time block screen and warning, and the autofill pop-ups.
 */
object AppLanguage {
    fun isArabic(context: Context): Boolean {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        return when (prefs.getString("flutter.app.language", null)) {
            "arabic" -> true
            "english" -> false
            else -> Locale.getDefault().language == "ar"
        }
    }

    /** [en] or [ar], in the app's language. */
    fun t(context: Context, en: String, ar: String) = if (isArabic(context)) ar else en
}
