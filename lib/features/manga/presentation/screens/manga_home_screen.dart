import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/dialogs.dart';
import '../../domain/entities/manga_entities.dart';
import '../../domain/repositories/manga_repository.dart';
import '../../manga_routes.dart';
import '../providers/anime_providers.dart';
import '../providers/manga_providers.dart';
import 'anime_tabs.dart';
import '../widgets/extension_info_sheet.dart';
import '../widgets/manga_widgets.dart';

/// Mihon-style home: Library · Browse · Extensions.
class MangaHomeScreen extends ConsumerStatefulWidget {
  const MangaHomeScreen({super.key});

  @override
  ConsumerState<MangaHomeScreen> createState() => _MangaHomeScreenState();
}

class _MangaHomeScreenState extends ConsumerState<MangaHomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // First visit: go straight to Extensions so the user can add a repo.
    if (ref.read(extensionReposProvider).isEmpty) _tab = 2;
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(mediaModeProvider);
    final anime = mode == MediaMode.anime;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        // Scales down rather than wrapping when the tab adds action icons.
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SegmentedButton<MediaMode>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              selectedBackgroundColor: mangaAccent.withValues(alpha: .3),
            ),
            segments: const [
              ButtonSegment(value: MediaMode.manga, label: Text('Manga')),
              ButtonSegment(value: MediaMode.anime, label: Text('Anime')),
            ],
            selected: {mode},
            onSelectionChanged: (v) =>
                ref.read(mediaModeProvider.notifier).set(v.first),
          ),
        ),
        actions: [
          if (_tab != 0)
            IconButton(
              tooltip: 'Filters',
              icon: const Icon(Icons.translate),
              onPressed: () => _showFilters(context),
            ),
          if (_tab == 2)
            IconButton(
              tooltip: 'Repositories',
              icon: const Icon(Icons.dns_outlined),
              onPressed: () => _showRepos(context),
            ),
        ],
      ),
      body: switch ((_tab, anime)) {
        (0, false) => const _LibraryTab(),
        (1, false) => const _BrowseTab(),
        (_, false) => const _ExtensionsTab(),
        (0, true) => const AnimeLibraryTab(),
        (1, true) => const AnimeBrowseTab(),
        (_, true) => const AnimeExtensionsTab(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Browse',
          ),
          NavigationDestination(
            icon: Icon(Icons.extension_outlined),
            selectedIcon: Icon(Icons.extension),
            label: 'Extensions',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Library
// ---------------------------------------------------------------------------

class _LibraryTab extends ConsumerWidget {
  const _LibraryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = [...ref.watch(mangaLibraryProvider)]
      ..sort((a, b) {
        final da = a.lastReadAt ?? a.addedAt, db = b.lastReadAt ?? b.addedAt;
        return db.compareTo(da);
      });
    if (library.isEmpty) {
      return const EmptyHint(
        icon: Icons.collections_bookmark_outlined,
        text:
            'Your library is empty.\nFind something in Browse and tap '
            '"Add to library".',
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: mangaGridDelegate,
      itemCount: library.length,
      itemBuilder: (context, i) {
        final e = library[i];
        final unreadBadge = e.readChapters.isEmpty
            ? null
            : '${e.readChapters.length} read';
        return MangaGridCard(manga: e.manga, badge: unreadBadge);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Browse (installed sources)
// ---------------------------------------------------------------------------

class _BrowseTab extends ConsumerWidget {
  const _BrowseTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(visibleSourcesProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => MangaErrorView(
            error: e,
            onRetry: () => ref.invalidate(installedExtensionsProvider),
          ),
          data: (sources) {
            if (sources.isEmpty) {
              return const EmptyHint(
                icon: Icons.explore_outlined,
                text:
                    'No sources yet.\nInstall an extension from the Extensions '
                    'tab (check the language filter too).',
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
                              MangaRoutes.source(s.id, latest: true),
                            ),
                            child: const Text('Latest'),
                          )
                        : null,
                    onTap: () => context.push(MangaRoutes.source(s.id)),
                  ),
                ],
              ],
            );
          },
        );
  }
}

// ---------------------------------------------------------------------------
// Extensions
// ---------------------------------------------------------------------------

class _ExtensionsTab extends ConsumerStatefulWidget {
  const _ExtensionsTab();

  @override
  ConsumerState<_ExtensionsTab> createState() => _ExtensionsTabState();
}

class _ExtensionsTabState extends ConsumerState<_ExtensionsTab> {
  String _query = '';

  Future<void> _install(AvailableExtension ext) async {
    try {
      await ref.read(installedExtensionsProvider.notifier).install(ext);
      _snack('${ext.name} installed');
    } on MangaException catch (e) {
      _snack('Install failed: ${e.message}');
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
    final repos = ref.watch(extensionReposProvider);
    if (repos.isEmpty) return const _AddRepoPrompt();

    final settings = ref.watch(mangaSettingsProvider);
    final installed = ref.watch(installedExtensionsProvider).value ?? const [];
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
        .watch(availableExtensionsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => MangaErrorView(
            error: e,
            onRetry: () => ref.invalidate(allAvailableExtensionsProvider),
          ),
          data: (available) {
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
                      decoration: const InputDecoration(
                        hintText: 'Search extensions',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _query = v.trim()),
                    ),
                  ),
                  if (installed.isNotEmpty)
                    SectionLabel('Installed · ${installed.length}'),
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
                        installLabel: 'Update',
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
                                    child: const Text('Update'),
                                  ),
                                IconButton(
                                  tooltip: 'Uninstall',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    final ok = await showConfirmDialog(
                                      context,
                                      title: 'Uninstall ${e.name}?',
                                      message:
                                          'Its sources disappear from Browse. '
                                          'Library entries stay.',
                                      confirmLabel: 'Uninstall',
                                    );
                                    if (ok) {
                                      await ref
                                          .read(
                                            installedExtensionsProvider
                                                .notifier,
                                          )
                                          .uninstall(e.pkgName);
                                    }
                                  },
                                ),
                              ],
                            ),
                    ),
                  SectionLabel('Available · ${shown.length}'),
                  for (final a in shown)
                    ExtensionTile(
                      name: a.name,
                      subtitle:
                          'v${a.versionName} · ${languageName(a.lang)}'
                          '${a.isNsfw ? ' · 18+' : ''}'
                          '${a.isSupported ? '' : ' · unsupported lib ${a.libVersion}'}',
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
                        note: a.isSupported
                            ? null
                            : 'Needs extension lib ${a.libVersion}, which '
                                  'MyKit doesn\'t support yet.',
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
                              child: const Text('Install'),
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

class _AddRepoPrompt extends ConsumerStatefulWidget {
  const _AddRepoPrompt();

  @override
  ConsumerState<_AddRepoPrompt> createState() => _AddRepoPromptState();
}

class _AddRepoPromptState extends ConsumerState<_AddRepoPrompt> {
  final _url = TextEditingController(text: keiyoushiRepoUrl);
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
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.extension_outlined, size: 64, color: Colors.white24),
        const SizedBox(height: 16),
        Text(
          'Add an extension repository',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'MyKit runs Mihon-compatible extensions. Each extension is '
          'verified against the repository\'s signing key before it loads.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'Repository URL',
            errorText: _error,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loading ? null : _add,
          icon: _loading ? const SmallSpinner() : const Icon(Icons.add),
          label: const Text('Add repository'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sheets
// ---------------------------------------------------------------------------

Future<void> _showRepos(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final repos = ref.watch(extensionReposProvider);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Repositories')),
              for (final r in repos)
                ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: Text(r.name),
                  subtitle: Text(
                    'Key ${r.signingKey.substring(0, 16)}…',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        ref.read(extensionReposProvider.notifier).remove(r.url),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Add repository'),
                onTap: () async {
                  final url = await showTextInputDialog(
                    context,
                    title: 'Repository URL',
                    hint: 'https://…/index.min.json',
                    confirmLabel: 'Add',
                  );
                  if (url == null) return;
                  try {
                    await ref.read(extensionReposProvider.notifier).add(url);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not add: $e')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    ),
  );
}

Future<void> _showFilters(BuildContext context) {
  const common = [
    'all',
    'en',
    'ar',
    'es',
    'fr',
    'id',
    'ja',
    'ko',
    'pt-BR',
    'ru',
    'tr',
    'vi',
    'zh',
  ];
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final s = ref.watch(mangaSettingsProvider);
        final n = ref.read(mangaSettingsProvider.notifier);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Languages', style: TextStyle(color: mangaAccent)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final l in common)
                      FilterChip(
                        label: Text(languageName(l)),
                        selected: s.langs.contains(l),
                        onSelected: (_) => n.toggleLang(l),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show 18+ extensions and sources'),
                  value: s.showNsfw,
                  onChanged: n.setShowNsfw,
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// Bits
// ---------------------------------------------------------------------------
