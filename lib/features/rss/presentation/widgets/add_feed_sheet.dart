import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/widgets/dialogs.dart';
import '../../domain/entities/rss_feed.dart';
import '../../domain/repositories/rss_repository.dart';
import '../../rss_routes.dart';
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

final _suggestions = <(String, String)>[
  (tr('Hacker News'), 'https://hnrss.org/frontpage'),
  (tr('The Verge'), 'https://www.theverge.com/rss/index.xml'),
  (tr('BBC World'), 'https://feeds.bbci.co.uk/news/world/rss.xml'),
  (tr('Ars Technica'), 'https://feeds.arstechnica.com/arstechnica/index'),
  (tr('Flutter blog'), 'https://medium.com/feed/flutter'),
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
        setState(() => _error = tr('You already follow this feed.'));
        return;
      }
      _title.text = preview.feed.title;
      setState(() => _preview = preview);
    } on FeedException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = tr('Something went wrong: {e}', {'e': e}));
      }
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
      title: tr('New category'),
      hint: tr('e.g. Tech, News, Design'),
      confirmLabel: tr('Create'),
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
    final library = ref.watch(rssLibraryProvider);
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
            Text(tr('Add feed'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              tr(
                'Paste a feed URL or just a website address — MyKit will find its feed.',
              ),
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
                labelText: tr('Feed or website URL'),
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
                label: Text(
                  _loading ? tr('Looking for feed…') : tr('Find feed'),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading
                    ? null
                    : () {
                        // Grab the router before the sheet's context goes away.
                        final router = GoRouter.of(context);
                        Navigator.pop(context);
                        router.push(RssRoutes.youtubeImport);
                      },
                icon: const Icon(Icons.subscriptions, color: Color(0xFFFF3B30)),
                label: Text(tr('Import YouTube subscriptions')),
              ),
              const SizedBox(height: 20),
              Text(
                tr('Suggestions'),
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
                decoration: InputDecoration(labelText: tr('Name')),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey(_categoryId),
                initialValue: _categoryId,
                decoration: InputDecoration(labelText: tr('Category')),
                items: [
                  for (final (:category, depth: _) in library.tree())
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(
                        library.pathOf(category.id),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  DropdownMenuItem(
                    value: _newCategory,
                    child: Row(
                      children: [
                        Icon(Icons.add, size: 18),
                        SizedBox(width: 8),
                        Text(tr('New category…')),
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
                    child: Text(tr('Back')),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _saving ? null : _subscribe,
                    icon: const Icon(Icons.add),
                    label: Text(tr('Subscribe')),
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
              tr('{length} articles · {0}', {
                'length': articles.length,
                '0': Uri.parse(preview.url).host,
              }),
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
