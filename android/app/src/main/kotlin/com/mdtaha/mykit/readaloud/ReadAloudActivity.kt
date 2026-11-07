package com.mdtaha.mykit.readaloud

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode

/**
 * "Read aloud" in Android's text-selection menu, in any app. Runs its own small
 * Flutter screen (readAloudMain) over whatever the user is reading.
 */
class ReadAloudActivity : FlutterActivity() {
    override fun getDartEntrypointFunctionName() = "readAloudMain"

    override fun getDartEntrypointArgs(): List<String> =
        listOf(intent?.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString().orEmpty())

    override fun getBackgroundMode() = BackgroundMode.transparent
}
