import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/entities/anime_entities.dart';
import '../providers/anime_providers.dart';
import '../widgets/anime_widgets.dart';
import '../widgets/manga_widgets.dart';

enum _Listing { popular, latest, search }

/// Popular / latest / search results of one anime source, with infinite scroll.
class AnimeSourceBrowseScreen extends ConsumerStatefulWidget {
  const AnimeSourceBrowseScreen({
    super.key,
    required this.sourceId,
    this.startWithLatest = false,
  });

  final String sourceId;
  final bool startWithLatest;

  @override
  ConsumerState<AnimeSourceBrowseScreen> createState() =>
      _AnimeSourceBrowseScreenState();
}

class _AnimeSourceBrowseScreenState
    extends ConsumerState<AnimeSourceBrowseScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  final _items = <Anime>[];
  final _seen = <String>{};

  late _Listing _listing = widget.startWithLatest
      ? _Listing.latest
      : _Listing.popular;
  int _page = 0;
  bool _hasNext = true;
  bool _loading = false;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) _loadMore();
    });
    _reset();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _reset([_Listing? listing]) {
    setState(() {
      if (listing != null) _listing = listing;
      _generation++;
      _items.clear();
      _seen.clear();
      _page = 0;
      _hasNext = true;
      _error = null;
      _loading = false;
    });
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasNext) return;
    final generation = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = ref.read(animeRepositoryProvider);
    final next = _page + 1;
    try {
      final result = switch (_listing) {
        _Listing.popular => await repo.popular(widget.sourceId, next),
        _Listing.latest => await repo.latest(widget.sourceId, next),
        _Listing.search => await repo.search(
          widget.sourceId,
          _search.text.trim(),
          next,
        ),
      };
      if (!mounted || generation != _generation) return;
      final fresh = result.animes.where((m) => _seen.add(m.key)).toList();
      ref.read(animeCacheProvider.notifier).putAll(fresh);
      setState(() {
        _items.addAll(fresh);
        _page = next;
        // Guard against sources that always claim another page.
        _hasNext = result.hasNextPage && fresh.isNotEmpty;
      });
    } catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(animeSourceProvider(widget.sourceId));
    return Scaffold(
      appBar: AppBar(
        title: _listing == _Listing.search
            ? TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: tr('Search'),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                onSubmitted: (_) => _reset(),
              )
            : Text(source?.name ?? tr('Source')),
        actions: [
          IconButton(
            icon: Icon(
              _listing == _Listing.search ? Icons.close : Icons.search,
            ),
            onPressed: () => _reset(
              _listing == _Listing.search ? _Listing.popular : _Listing.search,
            ),
          ),
        ],
        bottom: _listing == _Listing.search
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: Text(tr('Popular')),
                        selected: _listing == _Listing.popular,
                        onSelected: (_) => _reset(_Listing.popular),
                      ),
                      const SizedBox(width: 8),
                      if (source?.supportsLatest ?? false)
                        ChoiceChip(
                          label: Text(tr('Latest')),
                          selected: _listing == _Listing.latest,
                          onSelected: (_) => _reset(_Listing.latest),
                        ),
                    ],
                  ),
                ),
              ),
      ),
      body: _items.isEmpty && _error != null
          ? MangaErrorView(error: _error!, onRetry: _reset)
          : _items.isEmpty && _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? Center(
              child: Text(
                _listing == _Listing.search && _search.text.isEmpty
                    ? tr('Type a title and press search.')
                    : tr('Nothing found.'),
                style: const TextStyle(color: Colors.white54),
              ),
            )
          : CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverGrid(
                    gridDelegate: mangaGridDelegate,
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => AnimeGridCard(anime: _items[i]),
                      childCount: _items.length,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: Center(
                      child: _loading
                          ? const CircularProgressIndicator()
                          : _error != null
                          ? TextButton(
                              onPressed: _loadMore,
                              child: Text(
                                tr('Failed to load more · Retry\n{_error}', {
                                  '_error': _error,
                                }),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
