package eu.kanade.tachiyomi

/**
 * Host app info read by extensions (e.g. in User-Agent headers).
 * Reports a Mihon-compatible version since MyKit implements its extension API.
 */
@Suppress("UNUSED")
object AppInfo {
    fun getVersionCode(): Int = 20
    fun getVersionName(): String = "0.20.4"
    fun getSupportedImageMimeTypes(): List<String> = listOf(
        "image/avif", "image/gif", "image/heif", "image/jpeg",
        "image/jxl", "image/png", "image/webp",
    )
}
