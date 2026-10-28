import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/dialogs.dart';
import '../../domain/entities/rss_feed.dart';
import '../../domain/repositories/rss_repository.dart';
import '../providers/rss_providers.dart';

/// Bottom sheet to subscribe to a feed. Returns the new feed, if any.
Future<RssFeed?> showAddFeedSheet(
  BuildContext context, {
  String? initialCategoryId,
}) {
  return showModalBottomSheet<RssFeed>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AddFeedSheet(initialCategoryId: initialCategoryId),
  );
}

const _suggestions = <(String, String)>[
  ('Hacker News', 'https://hnrss.org/frontpage'),
  ('The Verge', 'https://www.theverge.com/rss/index.xml'),
  ('BBC World', 'https://feeds.bbci.co.uk/news/world/rss.xml'),
  ('Ars Technica', 'https://feeds.arstechnica.com/arstechnica/index'),
  ('Flutter blog', 'https://medium.com/feed/flutter'),
];

class _AddFeedSheet extends ConsumerStatefulWidget {
  const _AddFeedSheet({this.initialCategoryId});

  final String? initialCategoryId;

  @override
  ConsumerState<_AddFeedSheet> createState() => _AddFeedSheetState();
}

class _AddFeedSheetState extends ConsumerState<_AddFeedSheet> {
  static const _newCategory = '__new__';

  final _url = TextEditingController();
  final _title = TextEditingController();
  late String _categoryId;

  bool _loading = false;
  bool _saving = false;
  String? _error;
  FeedPreview? _preview;

  @override
  void initState() {
    super.initState();
    final categories = ref.read(rssLibraryProvider).categories;
    final initial = widget.initialCategoryId;
    _categoryId = categories.any((c) => c.id == initial)
        ? initial!
        : categories.first.id;
  }

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _find([String? url]) async {
    if (url != null) _url.text = url;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _preview = null;
    });
    try {
      final preview = await ref.read(rssRepositoryProvider).preview(_url.text);
      if (!mounted) return;
      if (ref.read(rssLibraryProvider.notifier).isSubscribed(preview.url)) {
        setState(() => _error = 'You already follow this feed.');
        return;
      }
      _title.text = preview.feed.title;
      setState(() => _preview = preview);
    } on FeedException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onCategoryChanged(String? value) async {
    if (value == null) return;
    if (value != _newCategory) {
      setState(() => _categoryId = value);
      return;
    }
    final name = await showTextInputDialog(
      context,
      title: 'New category',
      hint: 'e.g. Tech, News, Design',
      confirmLabel: 'Create',
    );
    if (name == null) return;
    final category = await ref
        .read(rssLibraryProvider.notifier)
        .addCategory(name);
    if (mounted) setState(() => _categoryId = category.id);
  }

  Future<void> _subscribe() async {
    final preview = _preview;
    if (preview == null) return;
    setState(() => _saving = true);
    final feed = await ref
        .read(rssLibraryProvider.notifier)
        .addFeed(preview: preview, title: _title.text, categoryId: _categoryId);
    if (mounted) Navigator.pop(context, feed);
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(rssLibraryProvider).categories;
    final preview = _preview;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add feed', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text(
              'Paste a feed URL or just a website address — '
              'MyKit will find its feed.',
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _url,
              autofocus: true,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Feed or website URL',
                hintText: 'example.com/feed',
                prefixIcon: const Icon(Icons.link),
                errorText: _error,
                errorMaxLines: 3,
              ),
              onSubmitted: (_) => _find(),
            ),
            const SizedBox(height: 12),
            if (preview == null) ...[
              FilledButton.icon(
                onPressed: _loading ? null : _find,
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_loading ? 'Looking for feed…' : 'Find feed'),
              ),
              const SizedBox(height: 20),
              const Text(
                'Suggestions',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final (name, url) in _suggestions)
                    ActionChip(
                      avatar: const Icon(Icons.rss_feed, size: 16),
                      label: Text(name),
                      onPressed: _loading ? null : () => _find(url),
                    ),
                ],
              ),
            ] else ...[
              _PreviewCard(preview: preview),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey(_categoryId),
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in categories)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                  const DropdownMenuItem(
                    value: _newCategory,
                    child: Row(
                      children: [
                        Icon(Icons.add, size: 18),
                        SizedBox(width: 8),
                        Text('New category…'),
                      ],
                    ),
                  ),
                ],
                onChanged: _onCategoryChanged,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _preview = null),
                    child: const Text('Back'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _saving ? null : _subscribe,
                    icon: const Icon(Icons.add),
                    label: const Text('Subscribe'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});

  final FeedPreview preview;

  @override
  Widget build(BuildContext context) {
    final articles = preview.feed.articles;
    return Card(
      color: const Color(0xFF38383C),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: Colors.greenAccent,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    preview.feed.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${articles.length} articles · ${Uri.parse(preview.url).host}',
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            for (final a in articles.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '• ${a.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
