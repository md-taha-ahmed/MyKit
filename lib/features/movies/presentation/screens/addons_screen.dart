import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/widgets/dialogs.dart';
import '../../domain/entities/stremio_entities.dart';
import '../providers/movies_providers.dart';
import '../widgets/movies_widgets.dart';

/// Installed Stremio add-ons: add by URL, remove, reorder, configure.
class AddonsScreen extends ConsumerWidget {
  const AddonsScreen({super.key});

  static const _suggested = [
    (
      name: 'Torrentio',
      url: 'https://torrentio.strem.fun/manifest.json',
      what: 'Torrent streams for movies, series and anime',
    ),
    (
      name: 'OpenSubtitles v3',
      url: 'https://opensubtitles-v3.strem.io/manifest.json',
      what: 'Subtitles in many languages',
    ),
    (
      name: 'Cinemeta',
      url: 'https://v3-cinemeta.strem.io/manifest.json',
      what: 'Catalogs, search and details (required for browsing)',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urls = ref.watch(addonUrlsProvider);
    final states = ref.watch(addonsProvider);
    final byUrl = {
      for (final s in states.value ?? const <AddonState>[]) s.url: s,
    };
    final missing = _suggested.where((s) => !urls.contains(s.url)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Add-ons')),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'reset') {
                final ok = await showConfirmDialog(
                  context,
                  title: tr('Reset add-ons?'),
                  message: tr(
                    'Back to Cinemeta, Torrentio and OpenSubtitles with default settings.',
                  ),
                  confirmLabel: tr('Reset'),
                );
                if (ok) ref.read(addonUrlsProvider.notifier).resetToDefaults();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'reset',
                child: Text(tr('Reset to defaults')),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        // The app theme makes FABs circular; extended ones need a stadium.
        shape: const StadiumBorder(),
        backgroundColor: moviesAccent,
        onPressed: () => _install(context, ref),
        icon: const Icon(Icons.add),
        label: Text(tr('Add-on URL')),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                tr(
                  'Works with Stremio add-ons. Order matters: details come from the first add-on that has them. Long-press and drag to reorder.',
                ),
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
            ),
          ),
          SliverReorderableList(
            itemCount: urls.length,
            onReorder: ref.read(addonUrlsProvider.notifier).reorder,
            itemBuilder: (context, i) {
              final url = urls[i];
              return ReorderableDelayedDragStartListener(
                key: ValueKey(url),
                index: i,
                child: _AddonTile(url: url, state: byUrl[url]),
              );
            },
          ),
          if (missing.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionHeader(tr('Suggested'))),
            SliverList.list(
              children: [
                for (final s in missing)
                  ListTile(
                    leading: const Icon(Icons.extension_outlined),
                    title: Text(s.name),
                    subtitle: Text(tr(s.what)),
                    trailing: TextButton(
                      onPressed: () => _installUrl(context, ref, s.url),
                      child: Text(tr('Install')),
                    ),
                  ),
              ],
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }

  Future<void> _install(BuildContext context, WidgetRef ref) async {
    final url = await showTextInputDialog(
      context,
      title: tr('Install add-on'),
      hint: 'https://…/manifest.json or stremio://…',
      confirmLabel: tr('Install'),
    );
    if (url == null || url.trim().isEmpty || !context.mounted) return;
    await _installUrl(context, ref, url);
  }

  Future<void> _installUrl(
    BuildContext context,
    WidgetRef ref,
    String url,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final m = await ref.read(addonUrlsProvider.notifier).install(url);
      messenger.showSnackBar(
        SnackBar(content: Text(tr('Installed {name}', {'name': m.name}))),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr('Could not install: {e}', {'e': e}))),
      );
    }
  }
}

class _AddonTile extends ConsumerWidget {
  const _AddonTile({required this.url, required this.state});

  final String url;
  final AddonState? state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = state?.manifest;
    final resources = m == null
        ? ''
        : {
            for (final r in m.resources)
              switch (r.name) {
                'catalog' => tr('Catalogs'),
                'meta' => tr('Details'),
                'stream' => tr('Streams'),
                'subtitles' => tr('Subtitles'),
                _ => r.name,
              },
          }.join(' · ');

    return ListTile(
      leading: SizedBox.square(
        dimension: 40,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: m?.logo != null
              ? NetImage(m!.logo, fit: BoxFit.contain, icon: Icons.extension)
              : const Icon(Icons.extension),
        ),
      ),
      title: Text(m?.name ?? Uri.parse(url).host),
      subtitle: Text(
        state == null
            ? tr('Loading…')
            : state!.error != null
            ? tr('Failed to load: {0}', {'0': state!.error})
            : '${m!.version.isEmpty ? '' : 'v${m.version} · '}$resources',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: state?.error != null ? Colors.redAccent : null),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          switch (v) {
            case 'configure':
              await launchUrl(
                Uri.parse('${m!.transportUrl}/configure'),
                mode: LaunchMode.externalApplication,
              );
            case 'remove':
              final ok = await showConfirmDialog(
                context,
                title: tr('Remove {name}?', {'name': m?.name ?? tr('add-on')}),
                message: tr('You can install it again later.'),
                confirmLabel: tr('Remove'),
              );
              if (ok) ref.read(addonUrlsProvider.notifier).remove(url);
          }
        },
        itemBuilder: (_) => [
          if (m?.configurable ?? false)
            PopupMenuItem(value: 'configure', child: Text(tr('Configure…'))),
          PopupMenuItem(value: 'remove', child: Text(tr('Remove'))),
        ],
      ),
      onTap: m == null ? null : () => _showInfo(context, m),
    );
  }

  void _showInfo(BuildContext context, AddonManifest m) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                m.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                m.description,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              SelectableText(
                m.manifestUrl,
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
              if (m.configurable) ...[
                const SizedBox(height: 12),
                Text(
                  tr(
                    'Configure opens the add-on\'s page. Copy the install link it gives you and add it here with "Add-on URL" — it replaces this one.',
                  ),
                  style: TextStyle(fontSize: 12.5, color: Colors.white60),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
