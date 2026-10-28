package eu.kanade.tachiyomi.network

import android.content.Context
import eu.kanade.tachiyomi.network.interceptor.CloudflareInterceptor
import eu.kanade.tachiyomi.network.interceptor.UncaughtExceptionInterceptor
import eu.kanade.tachiyomi.network.interceptor.UserAgentInterceptor
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import okhttp3.Cache
import okhttp3.OkHttpClient
import okhttp3.brotli.BrotliInterceptor
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * MyKit's implementation of the network API that Mihon/Tachiyomi extensions
 * use (`network.client`, `network.defaultUserAgentProvider()`).
 *
 * Public members mirror Mihon's NetworkHelper (Apache-2.0) so compiled
 * extensions link against it.
 */
class NetworkHelper(private val context: Context) {

    val cookieJar = AndroidCookieJar()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .cookieJar(cookieJar)
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .callTimeout(2, TimeUnit.MINUTES)
            .cache(Cache(File(context.cacheDir, "network_cache"), 5L * 1024 * 1024))
            .addInterceptor(UncaughtExceptionInterceptor())
            .addInterceptor(UserAgentInterceptor(::defaultUserAgentProvider))
            .addInterceptor(BrotliInterceptor)
            // Extensions require this; solves Cloudflare challenges in a hidden WebView.
            .addInterceptor(
                CloudflareInterceptor(context, cookieJar, scope, ::defaultUserAgentProvider),
            )
            .build()
    }

    /** @deprecated Since extension-lib 1.5 */
    @Deprecated("The regular client handles Cloudflare by default")
    @Suppress("UNUSED")
    val cloudflareClient: OkHttpClient get() = client

    fun defaultUserAgentProvider(): String = DEFAULT_USER_AGENT

    companion object {
        const val DEFAULT_USER_AGENT =
            "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"
    }
}
