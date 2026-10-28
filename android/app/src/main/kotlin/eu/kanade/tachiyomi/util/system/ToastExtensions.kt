package eu.kanade.tachiyomi.util.system

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.widget.Toast

/** Shows a toast from any thread. */
fun Context.toast(text: String, duration: Int = Toast.LENGTH_SHORT) {
    Handler(Looper.getMainLooper()).post { Toast.makeText(this, text, duration).show() }
}
