import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/stremio_entities.dart';
import '../providers/movies_providers.dart';
import '../widgets/movies_widgets.dart';

/// Whole catalog as a grid, loading more pages (`skip`) on scroll.
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({
    super.key,
    required this.addonUrl,
    required this.type,
    required this.id,
    required this.name,
  });

  final String addonUrl;
  final String type;
  final String id;
  final String name;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  final _items = <MetaPreview>[];
  final _ids = <String>{};
  bool _loading = false;
  bool _done = false;
  String? _error;

  late final _catalog = CatalogDef(
    addonUrl: widget.addonUrl,
    type: widget.type,
    id: widget.id,
    name: widget.name,
    extraSupported: const {'skip'},
    extraRequired: const {},
  );

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(moviesRepositoryProvider)
          .catalog(_catalog, skip: _items.length);
      final fresh = page.where((m) => _ids.add(m.id)).toList();
      if (!mounted) return;
      setState(() {
        _items.addAll(fresh);
        _done = fresh.isEmpty;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 600) _loadMore();
          return false;
        },
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 140,
                  childAspectRatio: 0.52,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: _items.length,
                itemBuilder: (_, i) =>
                    PosterCard(meta: _items[i], width: double.infinity),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Center(
                  child: _loading
                      ? const CircularProgressIndicator()
                      : _error != null
                      ? TextButton.icon(
                          onPressed: _loadMore,
                          icon: const Icon(Icons.refresh),
                          label: Text(_error!),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
