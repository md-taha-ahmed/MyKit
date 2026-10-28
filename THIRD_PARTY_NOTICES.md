# Third-party notices

## Mihon (Apache License 2.0)

Parts of the Android manga extension host are ported from Mihon
(https://github.com/mihonapp/mihon), Copyright the Mihon Open Source Project,
licensed under the Apache License, Version 2.0
(https://www.apache.org/licenses/LICENSE-2.0):

- `android/app/src/main/kotlin/eu/kanade/tachiyomi/**` (extension source API,
  network helpers, Cloudflare/WebView interceptors, WebView/device utils)
- `android/app/src/main/kotlin/tachiyomi/core/common/util/lang/RxCoroutineBridge.kt`
- `android/app/src/main/kotlin/mihon/core/common/extensions/JsonObject.kt`

Changes: dependency injection, logging, preferences and string resources were
replaced with MyKit equivalents; `NetworkHelper` and `AppInfo` were rewritten.
`ExtensionHost.kt` follows the design of Mihon's `ExtensionLoader`.

## Libraries used by Movies & Series

- libtorrent4j (https://github.com/aldenml/libtorrent4j), MIT License, which bundles
  libtorrent (https://libtorrent.org), BSD 3-Clause License.
- media_kit (https://github.com/media-kit/media-kit), MIT License, which bundles
  libmpv and FFmpeg builds licensed under the LGPL.
