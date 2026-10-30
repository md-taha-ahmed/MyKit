package com.mdtaha.mykit.backup

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Native half of MyKit's backup (`lib/features/backup/data/
 * backup_native_data_source.dart`): what Flutter's SharedPreferences can't
 * see — installed extension APKs, their trust keys and each source's own
 * settings (`source_<id>` preferences) — plus restarting the app after a
 * restore so every layer reloads from disk.
 *
 * Preference values cross the channel tagged with their type
 * (`[tag, value]`) so ints, longs and floats come back as what they were.
 */
class BackupChannel(private val activity: Activity, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val context: Context = activity.applicationContext
    private val channel = MethodChannel(messenger, "com.mdtaha.mykit/backup").apply {
        setMethodCallHandler(this@BackupChannel)
    }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "restart") {
            result.success(null)
            restart()
            return
        }
        scope.launch {
            val reply = runCatching {
                when (call.method) {
                    "export" -> export()
                    "import" -> {
                        @Suppress("UNCHECKED_CAST")
                        import(call.arguments as Map<String, Any?>)
                        null
                    }
                    else -> NotImplemented
                }
            }
            withContext(Dispatchers.Main) {
                reply.fold(
                    onSuccess = { if (it === NotImplemented) result.notImplemented() else result.success(it) },
                    onFailure = { result.error(it.javaClass.simpleName, it.message, null) },
                )
            }
        }
    }

    private fun export(): Map<String, Any> {
        val prefs = mutableMapOf<String, Any>()
        prefsDir().listFiles { f -> f.extension == "xml" }?.forEach { file ->
            val name = file.nameWithoutExtension
            if (!backsUp(name)) return@forEach
            val entries = mutableMapOf<String, Any>()
            context.getSharedPreferences(name, Context.MODE_PRIVATE).all.forEach { (key, value) ->
                tag(value)?.let { entries[key] = it }
            }
            prefs[name] = entries
        }

        val files = mutableMapOf<String, ByteArray>()
        for (dir in FILE_DIRS) {
            File(context.filesDir, dir).listFiles { f -> f.isFile && f.extension == EXT }
                ?.forEach { files["$dir/${it.name}"] = it.readBytes() }
        }
        return mapOf("prefs" to prefs, "files" to files)
    }

    private fun import(data: Map<String, Any?>) {
        @Suppress("UNCHECKED_CAST")
        val prefs = data["prefs"] as? Map<String, Map<String, List<Any?>>> ?: emptyMap()
        for ((name, entries) in prefs) {
            if (!backsUp(name) || name.contains('/')) continue
            val editor = context.getSharedPreferences(name, Context.MODE_PRIVATE).edit().clear()
            for ((key, tagged) in entries) {
                val value = tagged.getOrNull(1) ?: continue
                when (tagged[0]) {
                    "s" -> editor.putString(key, value as String)
                    "b" -> editor.putBoolean(key, value as Boolean)
                    "i" -> editor.putInt(key, (value as Number).toInt())
                    "l" -> editor.putLong(key, (value as Number).toLong())
                    "f" -> editor.putFloat(key, (value as Number).toFloat())
                    "ss" -> editor.putStringSet(key, (value as List<*>).map { it.toString() }.toSet())
                }
            }
            editor.commit()
        }

        @Suppress("UNCHECKED_CAST")
        val files = data["files"] as? Map<String, ByteArray> ?: emptyMap()
        for (dir in FILE_DIRS) {
            val target = File(context.filesDir, dir).apply { mkdirs() }
            // Replace, not merge: the backup's set of extensions is the truth.
            target.listFiles()?.forEach { it.setWritable(true); it.delete() }
            files.filterKeys { it.substringBefore('/') == dir }.forEach { (path, bytes) ->
                val name = path.substringAfter('/')
                if (name.contains('/') || name.startsWith('.') || !name.endsWith(".$EXT")) return@forEach
                File(target, name).apply {
                    writeBytes(bytes)
                    setReadOnly() // Android 14+ refuses writable dex files.
                }
            }
        }
    }

    /** Relaunches MyKit in a fresh process (extensions, players and caches reload). */
    private fun restart() {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        val intent = Intent.makeRestartActivityTask(launch.component)
        Handler(Looper.getMainLooper()).postDelayed({
            activity.startActivity(intent)
            Runtime.getRuntime().exit(0)
        }, 300)
    }

    private fun prefsDir() = File(context.applicationInfo.dataDir, "shared_prefs")

    private fun backsUp(name: String) =
        name != FLUTTER_PREFS && SKIP_PREFIXES.none { name.startsWith(it) }

    private fun tag(value: Any?): List<Any>? = when (value) {
        is String -> listOf("s", value)
        is Boolean -> listOf("b", value)
        is Int -> listOf("i", value)
        is Long -> listOf("l", value)
        is Float -> listOf("f", value.toDouble())
        is Set<*> -> listOf("ss", value.map { it.toString() }.sorted())
        else -> null
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }

    private object NotImplemented

    companion object {
        /** Flutter's own preferences are backed up from Dart. */
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"

        /** Library/system state that belongs to this install only. */
        private val SKIP_PREFIXES = listOf("androidx.", "com.google.", "WebView", "_")

        /** `ExtensionHost` directories (manga and anime). */
        private val FILE_DIRS = listOf("manga_extensions", "anime_extensions")
        private const val EXT = "ext"
    }
}
