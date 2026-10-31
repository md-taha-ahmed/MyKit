import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/widgets/dialogs.dart';
import '../../domain/entities/manga_entities.dart';
import '../../domain/repositories/manga_repository.dart';
import '../../manga_routes.dart';
import '../providers/anime_providers.dart';
import '../providers/manga_providers.dart';
import '../widgets/anime_widgets.dart';
import '../widgets/extension_info_sheet.dart';
import '../widgets/manga_widgets.dart';

// The anime half of the Manga tool: Library · Browse · Extensions, like manga.

class AnimeLibraryTab extends ConsumerWidget {
  const AnimeLibraryTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = [...ref.watch(animeLibraryProvider)]
      ..sort((a, b) {
        final da = a.lastWatchedAt ?? a.addedAt;
        final db = b.lastWatchedAt ?? b.addedAt;
        return db.compareTo(da);
      });
    if (library.isEmpty) {
      return EmptyHint(
        icon: Icons.video_library_outlined,
        text: tr(
          'Your anime library is empty.\nFind something in Browse and tap "Add to library".',
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: mangaGridDelegate,
      itemCount: library.length,
      itemBuilder: (context, i) {
        final e = library[i];
        return AnimeGridCard(
          anime: e.anime,
          badge: e.watchedEpisodes.isEmpty
              ? null
              : '${e.watchedEpisodes.length} watched',
        );
      },
    );
  }
}

class AnimeBrowseTab extends ConsumerWidget {
  const AnimeBrowseTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(visibleAnimeSourcesProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => MangaErrorView(
            error: e,
            onRetry: () => ref.invalidate(installedAnimeExtensionsProvider),
          ),
          data: (sources) {
            if (sources.isEmpty) {
              return EmptyHint(
                icon: Icons.explore_outlined,
                text: tr(
                  'No anime sources yet.\nInstall an extension from the Extensions tab (check the language filter too).',
                ),
              );
            }
            String? lastLang;
            return ListView(
              children: [
                for (final s in sources) ...[
                  if (s.lang != lastLang)
                    SectionLabel(languageName(lastLang = s.lang)),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: mangaAccent.withValues(alpha: .15),
                      child: Text(
                        s.name.characters.first.toUpperCase(),
                        style: const TextStyle(color: mangaAccent),
                      ),
                    ),
                    title: Text(s.name),
                    subtitle: Text(
                      [s.extensionName, if (s.nsfw) '18+'].join(' · '),
                      style: const TextStyle(color: Colors.white54),
                    ),
                    trailing: s.supportsLatest
                        ? TextButton(
                            onPressed: () => context.push(
                              MangaRoutes.animeSource(s.id, latest: true),
                            ),
                            child: Text(tr('Latest')),
                          )
                        : null,
                    onTap: () => context.push(MangaRoutes.animeSource(s.id)),
                  ),
                ],
              ],
            );
          },
        );
  }
}

class AnimeExtensionsTab extends ConsumerStatefulWidget {
  const AnimeExtensionsTab({super.key});

  @override
  ConsumerState<AnimeExtensionsTab> createState() => _AnimeExtensionsTabState();
}

class _AnimeExtensionsTabState extends ConsumerState<AnimeExtensionsTab> {
  String _query = '';

  Future<void> _install(AvailableExtension ext) async {
    try {
      await ref.read(installedAnimeExtensionsProvider.notifier).install(ext);
      _snack('${ext.name} installed');
    } on MangaException catch (e) {
      _snack(tr('Install failed: {message}', {'message': e.message}));
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(mangaSettingsProvider);
    final installed =
        ref.watch(installedAnimeExtensionsProvider).value ?? const [];
    final installedByPkg = {for (final e in installed) e.pkgName: e};
    final busy = ref.watch(installingProvider);
    final q = _query.toLowerCase();

    bool visible(String name, String lang, bool nsfw) =>
        (q.isEmpty || name.toLowerCase().contains(q)) &&
        (settings.showNsfw || !nsfw) &&
        (settings.langs.isEmpty ||
            settings.langs.contains(lang) ||
            lang == 'all');

    return ref
        .watch(availableAnimeExtensionsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => MangaErrorView(
            error: e,
            onRetry: () => ref.invalidate(allAvailableExtensionsProvider),
          ),
          data: (available) {
            if (available.isEmpty && installed.isEmpty) {
              return const _AddAnimeRepoPrompt();
            }
            final updates = available
                .where(
                  (a) =>
                      installedByPkg[a.pkgName] != null &&
                      a.versionCode > installedByPkg[a.pkgName]!.versionCode,
                )
                .map((a) => a.pkgName)
                .toSet();
            final shown = available
                .where(
                  (a) =>
                      !installedByPkg.containsKey(a.pkgName) &&
                      visible(a.name, a.lang, a.isNsfw),
                )
                .toList();
            final byPkg = {for (final a in available) a.pkgName: a};

            return RefreshIndicator(
              onRefresh: () =>
                  ref.refresh(allAvailableExtensionsProvider.future),
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: tr('Search anime extensions'),
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _query = v.trim()),
                    ),
                  ),
                  if (installed.isNotEmpty)
                    SectionLabel(
                      tr('Installed · {length}', {'length': installed.length}),
                    ),
                  for (final e in installed)
                    ExtensionTile(
                      name: e.name,
                      subtitle:
                          'v${e.versionName} · ${languageName(_lang(e))}'
                          '${e.nsfw ? ' · 18+' : ''}',
                      iconUrl: byPkg[e.pkgName]?.iconUrl,
                      onTap: () => showExtensionInfoSheet(
                        context,
                        name: e.name,
                        iconUrl: byPkg[e.pkgName]?.iconUrl,
                        versionName: e.versionName,
                        lang: _lang(e),
                        nsfw: e.nsfw,
                        sites: groupSites([
                          for (final s in e.sources)
                            (name: s.name, lang: s.lang, url: s.baseUrl ?? ''),
                        ]),
                        onInstall: updates.contains(e.pkgName)
                            ? () => _install(byPkg[e.pkgName]!)
                            : null,
                        installLabel: tr('Update'),
                      ),
                      trailing: busy.contains(e.pkgName)
                          ? const SmallSpinner()
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (updates.contains(e.pkgName))
                                  FilledButton(
                                    onPressed: () =>
                                        _install(byPkg[e.pkgName]!),
                                    child: Text(tr('Update')),
                                  ),
                                IconButton(
                                  tooltip: tr('Uninstall'),
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    final ok = await showConfirmDialog(
                                      context,
                                      title: tr('Uninstall {name}?', {
                                        'name': e.name,
                                      }),
                                      message: tr(
                                        'Its sources disappear from Browse. Library entries stay.',
                                      ),
                                      confirmLabel: tr('Uninstall'),
                                    );
                                    if (ok) {
                                      await ref
                                          .read(
                                            installedAnimeExtensionsProvider
                                                .notifier,
                                          )
                                          .uninstall(e.pkgName);
                                    }
                                  },
                                ),
                              ],
                            ),
                    ),
                  SectionLabel(
                    tr('Available · {length}', {'length': shown.length}),
                  ),
                  for (final a in shown)
                    ExtensionTile(
                      name: a.name,
                      subtitle:
                          'v${a.versionName} · ${languageName(a.lang)}'
                          '${a.isNsfw ? ' · 18+' : ''}'
                          '${a.isTorrent ? ' · torrent (not supported)' : ''}'
                          '${!a.isTorrent && !a.isSupported ? ' · unsupported lib ${a.libVersion}' : ''}',
                      iconUrl: a.iconUrl,
                      onTap: () => showExtensionInfoSheet(
                        context,
                        name: a.name,
                        iconUrl: a.iconUrl,
                        versionName: a.versionName,
                        lang: a.lang,
                        nsfw: a.isNsfw,
                        sites: groupSites([
                          for (final s in a.sources)
                            (name: s.name, lang: s.lang, url: s.homeUrl),
                        ]),
                        note: a.isTorrent
                            ? tr(
                                'Torrent extensions need Aniyomi\'s torrent server, which MyKit doesn\'t include.',
                              )
                            : a.isSupported
                            ? null
                            : tr(
                                'Needs extension lib {version}, which MyKit doesn\'t support yet.',
                                {'version': a.libVersion},
                              ),
                        onInstall: a.isSupported && !busy.contains(a.pkgName)
                            ? () => _install(a)
                            : null,
                      ),
                      trailing: busy.contains(a.pkgName)
                          ? const SmallSpinner()
                          : TextButton(
                              onPressed: a.isSupported
                                  ? () => _install(a)
                                  : null,
                              child: Text(tr('Install')),
                            ),
                    ),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        );
  }

  static String _lang(InstalledExtension e) {
    final langs = e.sources.map((s) => s.lang).toSet();
    return langs.length == 1 ? langs.first : 'all';
  }
}

/// Shown until an anime repository is added (repos are shared with manga).
class _AddAnimeRepoPrompt extends ConsumerStatefulWidget {
  const _AddAnimeRepoPrompt();

  @override
  ConsumerState<_AddAnimeRepoPrompt> createState() =>
      _AddAnimeRepoPromptState();
}

class _AddAnimeRepoPromptState extends ConsumerState<_AddAnimeRepoPrompt> {
  final _url = TextEditingController(text: yuzonoAnimeRepoUrl);
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(extensionReposProvider.notifier).add(_url.text);
    } on MangaException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.dns_outlined, size: 48, color: Colors.white38),
        const SizedBox(height: 16),
        Text(
          tr('Add an anime repository'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          tr(
            'Anime extensions come from Aniyomi repositories. MyKit only installs extensions signed with the key the repository publishes.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _url,
          decoration: InputDecoration(
            labelText: tr('Repository URL'),
            errorText: _error,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loading ? null : _add,
          icon: _loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: Text(tr('Add repository')),
        ),
      ],
    );
  }
}
