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

## RSS feeds

- Add a feed by pasting a feed URL **or a website address**: the app reads the page's `<link rel="alternate">` or tries common paths (`/feed`, `/rss.xml`, …).
- Feeds live in categories (create, rename, delete; move feeds between them) — see *Feeds & categories* (folder icon).
- Supports RSS 2.0, RSS 1.0/RDF and Atom (`lib/features/rss/data/parsers/feed_parser.dart`).
- Articles are cached for offline reading (100 per feed); read state is tracked per article.

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

## Manga (beta) — Mihon-compatible extensions

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

