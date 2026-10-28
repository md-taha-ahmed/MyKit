package tachiyomi.core.common.util.system

import android.util.Log
import logcat.LogPriority

/** Logging helper with Mihon's signature, backed by android.util.Log. */
inline fun Any.logcat(
    priority: LogPriority = LogPriority.DEBUG,
    throwable: Throwable? = null,
    message: () -> String = { "" },
) {
    val tag = javaClass.simpleName.ifEmpty { "MyKitManga" }
    val text = buildString {
        append(message())
        if (throwable != null) append('\n').append(Log.getStackTraceString(throwable))
    }
    Log.println(priority.androidPriority, tag, text)
}
