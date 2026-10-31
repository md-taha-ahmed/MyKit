# MyKit

[![CI](https://github.com/md-taha-ahmed/MyKit/actions/workflows/ci.yml/badge.svg)](https://github.com/md-taha-ahmed/MyKit/actions/workflows/ci.yml)

A personal, local-only toolbox app for Android. The dashboard lists tools; each tool is a self-contained feature.

## Architecture

Feature-first clean architecture with Riverpod for state management and go_router for navigation.

```
lib/
├── main.dart                     # bootstraps SharedPreferences + ProviderScope
├── app/                          # app shell: MaterialApp, router, theme, tools_registry
├── core/
│   ├── storage/                  # shared infrastructure providers
│   └── tools/                    # ToolDefinition + toolsProvider
└── features/
    ├── dashboard/                # grid of tools built from the registry
    ├── manga/                    # BETA: Mihon-compatible extensions + reader
    ├── books/                    # PDF library: shelves, reader, bookmarks
    ├── music/                    # folder-based local music player (background playback)
    ├── rss/                      # RSS/Atom reader with categories (same layering)
    └── countdown/
        ├── countdown_tool.dart   # ToolDefinition for the dashboard
        ├── countdown_routes.dart # routes owned by this tool
        ├── domain/               # pure Dart: entities, repository contract, calculator
        ├── data/                 # JSON model, local data source, repo impl, home-widget bridge
        └── presentation/         # Riverpod providers, screens, widgets
```

Dependencies flow inward: `presentation → domain ← data`. Providers in
`presentation/providers` wire the data implementations to the domain contracts.

## Adding a new tool

1. Create `lib/features/<tool>/` with `domain/`, `data/`, `presentation/`.
2. Add `<tool>_routes.dart` (top-level path like `/<tool>`) and `<tool>_tool.dart` exporting a `ToolDefinition`.
3. Add it to `lib/app/tools_registry.dart`. It now shows on the dashboard and its routes are registered.

## Countdown home-screen widget (Android)

Native code lives in `android/app/src/main/kotlin/com/mdtaha/mykit/widgets/`:

- `CountdownWidgetProvider` renders each widget instance from the JSON the app saves via `home_widget`.
- `CountdownRenderer` / `CountdownMath` draw the ring natively, so widgets refresh (every 30 min) without the app running.
  `CountdownMath.kt` mirrors `countdown_calculator.dart` — keep them in sync.
- `CountdownWidgetConfigureActivity` lets you choose which countdown a widget shows.

Add a widget by long-pressing the home screen → Widgets → MyKit → Countdown, or from the app via the edit screen's ⋮ → *Add to home screen*.
Tapping a widget opens that countdown in the app.

## Run

```
flutter pub get
flutter run
flutter test
```

## Language and setup

- **Arabic or English**: Settings (⚙ on the dashboard) → Language (System / English / العربية). Arabic lays the
  whole app out right to left and uses Arabic dates and system dialogs. All text goes through `tr()`
  (`lib/core/i18n/i18n.dart`); the English text is the key and `lib/core/i18n/ar.dart` holds the Arabic.
  `test/core/i18n_test.dart` fails if a `tr('…')` text has no Arabic, so add new text there too.
- **Setup checklist** (`lib/features/setup/`): opens on a fresh install and from Settings. It checks
  notifications, running in the background, the Gemini key, Drive backup, the password vault, autofill and
  Screen time, and fixes each with one tap. The Gemini key screen explains how to get a free key and tests it
  before saving.
- **Sharing the app**: `tool/build_shared_apk.sh` builds an APK with Google sign-in but without your Gemini key,
  so each person uses their own (from the checklist). A normal build with `config/ai.local.json` would give
  everyone your key.

## RSS feeds

- Add a feed by pasting a feed URL **or a website address**: the app reads the page's `<link rel="alternate">` or tries common paths (`/feed`, `/rss.xml`, …).
- Feeds live in categories (create, rename, delete; move feeds between them) — see *Feeds & categories* (folder icon).
- Supports RSS 2.0, RSS 1.0/RDF and Atom (`lib/features/rss/data/parsers/feed_parser.dart`).
- Articles are cached for offline reading (100 per feed); read state is tracked per article.

### AI summaries and article chat (Gemini)

Every article has **Summarize** (gist + key facts, in the article's language) and **Ask** (a chat about the
article). When a feed only ships a teaser, the app fetches the page and extracts the article text first.

- Client: `lib/core/ai/gemini_client.dart` (Gemini `generateContent` REST, `gemini-3.5-flash-lite` with
  `gemini-3.5-flash` as fallback when busy — the regular models with the most free-tier quota).
- Key: put it in the git-ignored `config/ai.local.json` (`{"GEMINI_API_KEY": "…"}`) and build with
  `--dart-define-from-file=config/ai.local.json`, or paste it in the app (article ⋮ → Gemini API key…;
  stored on the device only). CI builds contain no key.

## Backup — Google Drive

Dashboard → cloud icon. Everything MyKit stores on the phone is packed into one gzipped JSON file and uploaded to
the **app data folder** of your Google Drive (hidden; scope `drive.appdata`, so MyKit sees no other Drive files):

- all Flutter preferences: settings, libraries, progress, feeds, countdowns, workouts, add-ons, API keys;
- the Android side (`packages/mykit_backup`, a local plugin so it also runs on WorkManager's background engine):
  installed Mihon/Aniyomi extension APKs, their trust keys and each source's own settings.

Not included: imported book PDFs and caches/downloads. This install's Google sign-in token is never backed up.

- **Automatic** (WorkManager): leaving the app schedules a backup 2 minutes later; coming back cancels it, so
  opening and closing the app often still uploads once. It only uploads if something changed, runs even if Android
  has killed MyKit, waits for a network connection and retries failures. Can be switched off.
- **Kept in Drive**: the 5 latest backups, the newest of each of the last 7 days and of each of the last 4 weeks.
- **Restore** (e.g. after reinstalling): Backup → Sign in with Google → pick a backup → Restore. MyKit replaces its
  data and restarts.

Setup: uses the same OAuth client as the YouTube import (below). In that Google Cloud project also **enable the
Google Drive API** and add the scope `https://www.googleapis.com/auth/drive.appdata` under *Data access*. Build with
`--dart-define-from-file=config/google_oauth.local.json` so a fresh install can sign in without re-entering the
client. Move the consent screen to *In production* — in *Testing* Google expires the sign-in after 7 days, which
stops automatic backups until you sign in again.

## YouTube subscriptions import

RSS Feeds → **+** → **Import YouTube subscriptions** signs in with Google **in the browser** (OAuth with PKCE and a
loopback redirect, `lib/core/google/google_oauth.dart`), so it works **without Google Play services** (microG,
de-Googled ROMs). It reads your subscriptions with the YouTube Data API (read-only, ~1 quota unit per 50 channels),
lets you tick channels, and adds each channel's free RSS feed (`youtube.com/feeds/videos.xml?channel_id=…`).

One-time Google Cloud setup (free):

1. Open <https://console.cloud.google.com/> and create a project (e.g. "MyKit").
2. **APIs & Services → Library →** search **YouTube Data API v3 → Enable**.
3. **Google Auth Platform** (OAuth consent screen):
   - *Branding*: app name `MyKit`, your email as support and developer contact.
   - *Audience*: **External**, keep it in **Testing**, and add your Google account under **Test users**.
   - *Data access*: add the scope `https://www.googleapis.com/auth/youtube.readonly`.
4. **Clients → Create client → Application type: Desktop app** → Create. Copy the **Client ID** and **Client secret**.
5. In MyKit: RSS Feeds → **+** → **Import YouTube subscriptions** → paste both → **Save** → **Continue with Google**.
   In the browser pick your account; on *"Google hasn't verified this app"* tap **Continue** (it's your own app),
   allow read-only YouTube access, then **Return to MyKit**.

Notes: while the consent screen is in *Testing*, Google expires the sign-in after 7 days — just tap *Continue with
Google* again (or move the app to *In production*; it stays unverified, which is fine for personal use). The ID and
secret are stored only on the device (or pass `--dart-define=GOOGLE_OAUTH_CLIENT_ID=… --dart-define=GOOGLE_OAUTH_CLIENT_SECRET=…`
at build time). For installed apps Google does not treat the "client secret" as confidential.

## Music

- Songs come from Android's MediaStore (`android/.../media/MediaLibraryChannel.kt`), grouped by folder.
- Folders are listed A–Z; songs sort by name A–Z / Z–A (natural order: "Track 2" before "Track 10") or recently added,
  using either the song title or the file name (sort icon). The choice is remembered.
- Background playback, the media notification, lock-screen and headset controls come from
  `just_audio` + `just_audio_background` (initialised in `main.dart`; `MainActivity` extends `AudioServiceActivity`).

## Books (PDF reader)

- Shelves (categories): create / rename / delete, import PDFs straight into a shelf, move books between shelves.
- PDFs are copied into app storage (`<documents>/books/`); page 1 is rendered as the cover.
- Reader remembers the last page, has bookmarks with notes, contents (PDF outline), full-text search and go-to-page.
- Layouts: vertical continuous scroll or horizontal page-by-page (pinch / double-tap zoom).
- Page colours: light, dark (softened inversion) and sepia — `presentation/widgets/reader_colors.dart`.

## Anime & Manga (beta) — Mihon & Aniyomi extensions

MyKit hosts real Mihon/Tachiyomi extension APKs (extension lib 1.4 / 1.6).

- **Repositories**: add a repo URL (e.g. keiyoushi's `index.min.json`). Resolution follows Mihon 0.20+:
  legacy `index.min.json` → `repo.json` → `index_v2` (gzipped protobuf) → extension list
  (`lib/features/manga/data/parsers/extension_index_parser.dart`).
- **Install**: the APK is downloaded and **only loaded if it is signed with the repo's
  `signingKeyFingerprint`** and declares a supported lib version (`android/.../manga/ExtensionHost.kt`).
  Files live read-only in app storage (`files/manga_extensions/`).
- **Runtime**: the extension API (`eu.kanade.tachiyomi.*`) is ported from Mihon (see `THIRD_PARTY_NOTICES.md`),
  with OkHttp 5, jsoup, RxJava 1, Injekt, kotlinx-serialization and QuickJS at the versions keiyoushi builds against.
  Kotlin must stay in step with the extensions (currently 2.4.10). R8 keep rules: `android/app/proguard-rules.pro`.
- **Flutter ↔ native**: `MangaChannel.kt` ⇄ `manga_native_data_source.dart` (popular/latest/search, details,
  chapters, pages, images via the source's own client and headers).
- **App**: Library · Browse · Extensions tabs, manga details + chapters, reader (right-to-left, left-to-right,
  vertical/webtoon), progress and read chapters.
- Not yet: source filters, source preference screens, downloads, library update checks, tracking.

**Anime** (switch **Manga | Anime** at the top of the tool) hosts real Aniyomi anime extension APKs
(ext lib 14 / 16 / 17), with the same Library · Browse · Extensions tabs.

- **Repositories** are shared with manga; an anime repo (e.g. yuzono's `index.min.json`) shows its extensions
  in Anime mode. The index parser handles Aniyomi's protobuf store (field 8 = torrent flag, 9 = sources).
- **Host**: `ExtensionHost<S>` serves both kinds (`ExtensionHost.MANGA` / `ANIME`: feature, metadata keys,
  lib versions, storage); same signature check and class loading. The anime source API
  (`eu.kanade.tachiyomi.animesource.*`) and Aniyomi's extra helpers are ported from Aniyomi (see
  `THIRD_PARTY_NOTICES.md`); NanoHTTPD and the kotlinx-serialization plugin are added for it.
- **Playback** (`AnimeChannel.kt`) follows Aniyomi's EpisodeLoader: sources overriding the hoster API give
  hosters → videos (lazy hosters load on demand), older ones give videos directly; `getVideoUrl` /
  `resolveVideo` and the source's own sorting are applied. Videos play in the Movies & Series player with the
  source's headers; subtitles that need those headers are downloaded by the app and passed to mpv as text.
- **App**: browse/latest/search per source, details with episodes or seasons, watched marks (long-press),
  Continue/Start, resume position, library.
- Not yet: torrent extensions (need Aniyomi's TorrServer), source filters and preference screens, downloads.

## Movies & Series (beta) — Stremio add-ons

Browse, pick a source and play, using the [Stremio add-on protocol](https://github.com/Stremio/stremio-addon-sdk/tree/master/docs/api).

- **Add-ons** (`lib/features/movies/data/datasources/stremio_addon_client.dart`): any add-on can be installed by its
  `manifest.json` URL or `stremio://` link. Defaults: **Cinemeta** (catalogs, search, details),
  **Torrentio** (streams) and **OpenSubtitles v3** (subtitles). Configured add-ons (e.g. Torrentio with a debrid
  service) are installed from the install link their configure page gives; a debrid stream is a direct URL and
  plays without the torrent engine.
- **Torrent streaming** (`android/.../torrent/`): libtorrent (libtorrent4j) downloads only the chosen file,
  sequentially; `TorrentHttpServer` serves it on `http://127.0.0.1` with `Range` support, waiting for whatever
  the player reads next, so seeking works. A window of 24–96 MB ahead of the read position gets top piece
  priority (moved on seek); only the piece the player is blocked on gets a deadline — libtorrent's deadline mode
  requests one block per peer at a time and throttles downloads if used for the whole buffer. Playback starts
  after a ~3 MB prebuffer plus the file's last piece (MP4/MKV indexes). The engine starts when the tool opens and
  adds a fresh public tracker list (ngosang/trackerslist). One stream at a time; files are deleted when the
  player closes. arm64/armv7 only.
- **Slow torrents**: mobile carriers often throttle BitTorrent (total speed stays flat however many peers send);
  Wi-Fi, a P2P-friendly VPN or a debrid service avoid that.
- **Player**: libmpv via media_kit (MKV, HEVC, AC3/DTS…): online subtitles (preferred language remembered,
  delay ±), embedded subtitle and audio tracks, resume position, "open in another player" (VLC, MX…).
- **App**: Movies | Series tabs with Continue watching and catalog rows, search (titles or an IMDb link/id),
  details with seasons/episodes, sources with quality filter, seeders and size.
- Not yet: downloads for offline, next-episode autoplay, library/watchlist, catalog filters (genre).
- Torrents share what you download with other peers, and your IP is visible to them. Only stream what you have
  the right to watch.

## Fitness — home workouts and progress

Built for losing weight with home training (dumbbells + calisthenics).

- **Plan**: a ready 4-day upper/lower plan (Sat/Sun/Tue/Wed by default, beginner-friendly: incline push-ups,
  floor press, goblet squats, RDLs, lunges, core and a short finisher) — every workout, exercise, target and day
  is editable. Double progression: when every set reaches the top of the rep range the workout screen says to
  add weight (`lib/features/fitness/domain/`).
- **Workout**: one exercise at a time with photos, sets × reps × kg pre-filled from last time, hold timer for
  timed moves, rest countdown (vibration/sound, plus a notification if the phone is locked), summary with new
  personal bests. The workout in progress survives leaving the screen or the app.
- **Exercises**: 876 exercises from [free-exercise-db](https://github.com/yuhonas/free-exercise-db) (public
  domain) — downloaded once; photos download on first view and stay cached; start/end photos alternate like a
  GIF. Filters: home equipment, muscle. Add your own photo to any exercise, or create your own exercises.
  A body diagram (front/back, drawn in code) highlights primary and secondary muscles.
- **Progress**: weight chart with goal line, BMI, measurements (waist, chest, arm, hips, thigh), workouts per
  week, week streak, personal bests and full history.
- **Reminders** on training days (flutter_local_notifications; inexact alarms, no special permission).

## App icon

- Android 8+ uses the adaptive vector icon: `android/app/src/main/res/drawable/ic_launcher_{background,foreground,monochrome}.xml`
  (monochrome enables Android 13 themed icons).
- Older Android versions use the PNGs in `mipmap-*/`, generated by `tool/app_icon/generate.py` (needs Pillow).
  It also writes `assets/icon/app_icon_512.png` for store listings.
- When changing the design, update the script and the vector XMLs together.

## CI/CD (GitHub Actions)

- **CI** (`.github/workflows/ci.yml`) — on every PR and push to `main`: format check, `flutter analyze --fatal-infos`,
  tests with coverage, then a release APK build uploaded as a workflow artifact.
- **Release** (`.github/workflows/release.yml`) — push a tag to publish a GitHub Release with APKs
  (universal + per-ABI) and SHA-256 checksums:

  ```
  git tag v1.0.0 && git push origin v1.0.0
  ```
- **Signing** — set these repository secrets to sign releases with your own key (otherwise the debug key is used):
  `ANDROID_KEYSTORE_BASE64` (`base64 -i release.jks`), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
  `ANDROID_KEY_PASSWORD`. Locally, create `android/key.properties` (git-ignored) with `storeFile`, `storePassword`,
  `keyAlias`, `keyPassword`. Note: switching keys means existing installs must be uninstalled once.
- **Dependabot** keeps pub packages and actions up to date; Gradle bumps need care because the manga host must match
  the library versions extensions are built against.

