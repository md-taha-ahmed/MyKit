import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/i18n/i18n.dart';
import '../providers/offline_providers.dart';
import '../providers/rss_providers.dart';
import 'feeds_drawer.dart';

/// "Download for offline": save articles (text and images) before a trip.
Future<void> showOfflineSheet(BuildContext context, ArticleFilter filter) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _OfflineSheet(filter: filter),
    );

class _OfflineSheet extends ConsumerStatefulWidget {
  const _OfflineSheet({required this.filter});

  final ArticleFilter filter;

  @override
  ConsumerState<_OfflineSheet> createState() => _OfflineSheetState();
}

class _OfflineSheetState extends ConsumerState<_OfflineSheet> {
  late bool _onlySelection = _isScoped;
  bool _images = true;

  /// A folder or feed is selected (not All / Saved / Liked).
  bool get _isScoped =>
      widget.filter.feedId != null ||
      (widget.filter.categoryId != null &&
          widget.filter.categoryId != savedArticlesFilter &&
          widget.filter.categoryId != likedArticlesFilter);

  ArticleFilter get _scope => _onlySelection ? widget.filter : allArticles;

  static const _presets = [100, 300, 600, 1000, 0];

  /// Number entry for a custom amount; null if cancelled.
  static Future<int?> _askNumber(BuildContext context, int current) async {
    final controller = TextEditingController(
      text: current == 0 ? '' : '$current',
    );
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        void submit() {
          final n = int.tryParse(controller.text.trim());
          if (n != null && n > 0) Navigator.pop(context, n);
        }

        return AlertDialog(
          title: Text(tr('Number of articles')),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(hintText: tr('e.g. 1500')),
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Cancel')),
            ),
            FilledButton(onPressed: submit, child: Text(tr('Set'))),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  static String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(0)} KB'
      : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(offlineDownloadProvider);
    final notifier = ref.read(offlineDownloadProvider.notifier);
    final count = ref.watch(filteredArticlesProvider(_scope)).length;
    final toSave = state.limit == 0 ? count : count.clamp(0, state.limit);
    final selectionName = rssFilterTitle(ref, widget.filter);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('Read offline'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              'Save the full text and pictures of your articles to the phone, so you can read them with no connection — on a plane or abroad. Feeds are refreshed first.',
            ),
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (_isScoped)
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: true,
                  label: Text(selectionName, overflow: TextOverflow.ellipsis),
                ),
                ButtonSegment(value: false, label: Text(tr('All feeds'))),
              ],
              selected: {_onlySelection},
              onSelectionChanged: state.running
                  ? null
                  : (v) => setState(() => _onlySelection = v.first),
            ),
          const SizedBox(height: 12),
          Text(
            tr('How many articles (newest first)'),
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final n in _presets)
                ChoiceChip(
                  label: Text(n == 0 ? tr('All') : '$n'),
                  selected: state.limit == n,
                  onSelected: state.running
                      ? null
                      : (_) => notifier.setLimit(n),
                ),
              ChoiceChip(
                avatar: const Icon(Icons.edit, size: 16),
                label: Text(
                  _presets.contains(state.limit)
                      ? tr('Other…')
                      : '${state.limit}',
                ),
                selected: !_presets.contains(state.limit),
                onSelected: state.running
                    ? null
                    : (_) async {
                        final n = await _askNumber(context, state.limit);
                        if (n != null) await notifier.setLimit(n);
                      },
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Include pictures')),
            subtitle: Text(tr('Uses more space')),
            value: _images,
            onChanged: state.running
                ? null
                : (v) => setState(() => _images = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Keep it up to date')),
            subtitle: Text(tr('Also save new articles after each refresh')),
            value: state.autoUpdate,
            onChanged: notifier.setAutoUpdate,
          ),
          const SizedBox(height: 8),
          if (state.running) ...[
            LinearProgressIndicator(
              value: state.total == 0 ? null : state.progress,
            ),
            const SizedBox(height: 8),
            Text(
              state.total == 0
                  ? tr('Refreshing feeds…')
                  : tr('Saving {done} of {total}…', {
                      'done': state.done,
                      'total': state.total,
                    }),
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: notifier.cancel, child: Text(tr('Stop'))),
          ] else
            FilledButton.icon(
              onPressed: toSave == 0
                  ? null
                  : () => notifier.download(filter: _scope, images: _images),
              icon: const Icon(Icons.download_for_offline_outlined),
              label: Text(tr('Download {toSave} articles', {'toSave': toSave})),
            ),
          if (state.message != null) ...[
            const SizedBox(height: 10),
            Text(state.message!, style: const TextStyle(color: Colors.white70)),
          ],
          const Divider(height: 28),
          Row(
            children: [
              const Icon(Icons.offline_pin_outlined, color: Colors.white54),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  [
                    tr('{count} articles saved · {size}', {
                      'count': state.savedCount,
                      'size': _size(state.bytes),
                    }),
                    if (state.lastRun != null)
                      tr('last {date}', {
                        'date': DateFormat(
                          'd MMM, HH:mm',
                        ).format(state.lastRun!),
                      }),
                  ].join('\n'),
                  style: const TextStyle(color: Colors.white60, height: 1.4),
                ),
              ),
              TextButton(
                onPressed: state.running || state.savedCount == 0
                    ? null
                    : notifier.clear,
                child: Text(tr('Delete all')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
