import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/stremio_entities.dart';
import '../../movies_routes.dart';
import '../providers/movies_providers.dart';
import '../widgets/movies_widgets.dart';

/// Movies | Series tabs with "Continue watching" and the add-ons' catalogs.
class MoviesHomeScreen extends ConsumerStatefulWidget {
  const MoviesHomeScreen({super.key});

  @override
  ConsumerState<MoviesHomeScreen> createState() => _MoviesHomeScreenState();
}

class _MoviesHomeScreenState extends ConsumerState<MoviesHomeScreen> {
  @override
  void initState() {
    super.initState();
    // Find peers sooner: start the torrent engine while the user browses.
    ref.read(moviesRepositoryProvider).warmUpTorrents().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: MediaType.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Movies & Series'),
          actions: [
            IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search),
              onPressed: () => context.push(MoviesRoutes.search),
            ),
            IconButton(
              tooltip: 'Add-ons',
              icon: const Icon(Icons.extension_outlined),
              onPressed: () => context.push(MoviesRoutes.addons),
            ),
          ],
          bottom: TabBar(
            indicatorColor: moviesAccent,
            labelColor: Colors.white,
            tabs: [for (final t in MediaType.values) Tab(text: t.label)],
          ),
        ),
        body: TabBarView(
          children: [for (final t in MediaType.values) _TypeTab(type: t)],
        ),
      ),
    );
  }
}

class _TypeTab extends ConsumerWidget {
  const _TypeTab({required this.type});

  final MediaType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogs = ref.watch(catalogsProvider(type));
    final failed = [
      for (final a in ref.watch(addonsProvider).value ?? const <AddonState>[])
        if (a.error != null) a.error!,
    ];
    final continueWatching = ref
        .watch(continueWatchingProvider)
        .where((e) => e.type == type.id)
        .toList();

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(addonsProvider);
        ref.invalidate(catalogItemsProvider);
        await ref.read(catalogsProvider(type).future);
      },
      child: catalogs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          children: [
            MessageView(
              icon: Icons.cloud_off,
              title: 'Could not load add-ons',
              message: '$e',
            ),
          ],
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (continueWatching.isNotEmpty) ...[
              const SectionHeader('Continue watching'),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: continueWatching.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) =>
                      _ContinueCard(entry: continueWatching[i]),
                ),
              ),
            ],
            if (list.isEmpty && failed.isNotEmpty)
              MessageView(
                icon: Icons.cloud_off,
                title: 'Could not reach the add-ons',
                message: 'Check your internet connection.\n${failed.first}',
                action: FilledButton(
                  onPressed: () => ref.invalidate(addonsProvider),
                  child: const Text('Retry'),
                ),
              )
            else if (list.isEmpty)
              MessageView(
                icon: Icons.extension_off_outlined,
                title: 'No ${type.label.toLowerCase()} catalogs',
                message: 'Install a catalog add-on such as Cinemeta.',
                action: FilledButton(
                  onPressed: () => context.push(MoviesRoutes.addons),
                  child: const Text('Manage add-ons'),
                ),
              ),
            for (final c in list) _CatalogRow(catalog: c),
          ],
        ),
      ),
    );
  }
}

class _CatalogRow extends ConsumerWidget {
  const _CatalogRow({required this.catalog});

  final CatalogDef catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(catalogItemsProvider(catalog));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          catalog.name,
          onMore: () => context.push(
            MoviesRoutes.catalog(
              catalog.addonUrl,
              catalog.type,
              catalog.id,
              catalog.name,
            ),
          ),
        ),
        SizedBox(
          height: 228,
          child: items.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: TextButton.icon(
                onPressed: () => ref.invalidate(catalogItemsProvider(catalog)),
                icon: const Icon(Icons.refresh),
                label: Text('$e'),
              ),
            ),
            data: (metas) => ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: metas.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => PosterCard(meta: metas[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _ContinueCard extends ConsumerWidget {
  const _ContinueCard({required this.entry});

  final WatchEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: 220,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => context.push(
          entry.type == MediaType.series.id
              ? MoviesRoutes.title(entry.type, entry.metaId)
              : MoviesRoutes.streams(entry.type, entry.metaId, entry.videoId),
        ),
        onLongPress: () async {
          final remove = await showModalBottomSheet<bool>(
            context: context,
            builder: (context) => SafeArea(
              child: ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove from Continue watching'),
                onTap: () => Navigator.pop(context, true),
              ),
            ),
          );
          if (remove == true) {
            ref.read(watchHistoryProvider.notifier).remove(entry.videoId);
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 110,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(entry.background ?? entry.poster),
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        size: 40,
                        color: Colors.white70,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: WatchProgressBar(entry.fraction),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            if (entry.episodeLabel != null)
              Text(
                entry.episodeLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: Colors.white54),
              ),
          ],
        ),
      ),
    );
  }
}
