import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/manga_entities.dart';
import '../../manga_routes.dart';
import '../providers/manga_providers.dart';
import '../widgets/manga_widgets.dart';

/// Details + chapter list, like Mihon's manga screen.
class MangaDetailsScreen extends ConsumerStatefulWidget {
  const MangaDetailsScreen({super.key, required this.mangaKey});

  final String mangaKey;

  @override
  ConsumerState<MangaDetailsScreen> createState() => _MangaDetailsScreenState();
}

class _MangaDetailsScreenState extends ConsumerState<MangaDetailsScreen> {
  bool _newestFirst = true;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cached = ref.watch(mangaCacheProvider)[widget.mangaKey];
    if (cached == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Not found.')),
      );
    }
    final details = ref.watch(mangaDetailsProvider(widget.mangaKey));
    final manga = details.value ?? cached;
    final chapters = ref.watch(chaptersProvider(widget.mangaKey));
    final library = ref.watch(mangaLibraryProvider);
    final entry = ref
        .read(mangaLibraryProvider.notifier)
        .progressFor(manga.key);
    final inLibrary = library.any((e) => e.manga.key == manga.key);
    final source = ref.watch(mangaSourceProvider(manga.sourceId));

    void read(Chapter c) => context.push(MangaRoutes.reader(manga.key, c.url));

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(Icons.public),
            onPressed: () async {
              final url = await ref.read(mangaRepositoryProvider).webUrl(manga);
              if (url != null) {
                await launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(mangaDetailsProvider(widget.mangaKey));
          ref.invalidate(chaptersProvider(widget.mangaKey));
          await ref.read(chaptersProvider(widget.mangaKey).future);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 110, child: MangaCover(manga: manga)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            manga.title,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          if (manga.author != null || manga.artist != null)
                            Text(
                              {
                                manga.author,
                                manga.artist,
                              }.whereType<String>().join(' · '),
                              style: const TextStyle(color: Colors.white70),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              MangaStatus.of(manga.status).label,
                              if (source != null) source.name,
                            ].join(' · '),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                          if (details.isLoading)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: LinearProgressIndicator(),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => ref
                            .read(mangaLibraryProvider.notifier)
                            .toggle(manga),
                        icon: Icon(
                          inLibrary ? Icons.favorite : Icons.favorite_border,
                          color: inLibrary ? mangaAccent : null,
                        ),
                        label: Text(
                          inLibrary ? 'In library' : 'Add to library',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: mangaAccent,
                        ),
                        onPressed: chapters.value?.isNotEmpty ?? false
                            ? () => read(_resumeChapter(chapters.value!, entry))
                            : null,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(
                          entry?.lastChapterUrl != null ? 'Resume' : 'Start',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if ((manga.description ?? '').isNotEmpty)
              SliverToBoxAdapter(
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text(
                      manga.description!,
                      maxLines: _expanded ? null : 4,
                      overflow: _expanded ? null : TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            if (manga.genres.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final g in manga.genres)
                        Chip(
                          label: Text(g, style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
              ),
            ...chapters.when(
              loading: () => [
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              ],
              error: (e, _) => [
                SliverToBoxAdapter(
                  child: MangaErrorView(
                    error: e,
                    onRetry: () =>
                        ref.invalidate(chaptersProvider(widget.mangaKey)),
                  ),
                ),
              ],
              data: (list) {
                final ordered = _newestFirst ? list : list.reversed.toList();
                return [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 4, 0),
                      child: Row(
                        children: [
                          Text(
                            '${list.length} chapters',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: _newestFirst
                                ? 'Newest first'
                                : 'Oldest first',
                            icon: Icon(
                              _newestFirst
                                  ? Icons.arrow_downward
                                  : Icons.arrow_upward,
                            ),
                            onPressed: () =>
                                setState(() => _newestFirst = !_newestFirst),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: ordered.length,
                    itemBuilder: (context, i) {
                      final c = ordered[i];
                      final isRead =
                          entry?.readChapters.contains(c.url) ?? false;
                      final isCurrent = entry?.lastChapterUrl == c.url;
                      return ListTile(
                        onTap: () => read(c),
                        onLongPress: inLibrary
                            ? () => ref
                                  .read(mangaLibraryProvider.notifier)
                                  .setRead(manga, c.url, !isRead)
                            : null,
                        title: Text(
                          c.name,
                          style: TextStyle(
                            color: isRead ? Colors.white38 : null,
                            fontWeight: isCurrent ? FontWeight.w700 : null,
                          ),
                        ),
                        subtitle: Text(
                          [
                            if (c.dateUpload > 0)
                              DateFormat.yMMMd().format(
                                DateTime.fromMillisecondsSinceEpoch(
                                  c.dateUpload,
                                ),
                              ),
                            if (c.scanlator?.isNotEmpty ?? false) c.scanlator!,
                            if (isCurrent && !isRead)
                              'Page ${(entry?.lastPage ?? 0) + 1}',
                          ].join(' · '),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.white54,
                          ),
                        ),
                        trailing: isRead
                            ? const Icon(Icons.done, color: Colors.white38)
                            : null,
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Last-read chapter, else the first (oldest) one.
  static Chapter _resumeChapter(List<Chapter> chapters, LibraryEntry? entry) {
    final last = entry?.lastChapterUrl;
    if (last != null) {
      for (final c in chapters) {
        if (c.url == last) return c;
      }
    }
    return chapters.last;
  }
}
