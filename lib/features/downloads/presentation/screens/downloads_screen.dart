import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../movies/presentation/widgets/movies_widgets.dart'
    show MessageView;
import '../../domain/download_item.dart';
import '../providers/downloads_providers.dart';
import '../widgets/download_widgets.dart';

/// Everything saved for offline (of the given [kinds]), by title. Works with
/// no internet: covers and names are stored with the downloads.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key, required this.kinds, this.accent});

  final Set<DownloadKind> kinds;
  final Color? accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref
        .watch(downloadsProvider)
        .where((i) => kinds.contains(i.kind))
        .toList();
    final notifier = ref.read(downloadsProvider.notifier);
    final anyActive = items.any((i) => i.isActive);
    final anyStopped = items.any(
      (i) => i.state == DownloadState.paused || i.state == DownloadState.failed,
    );

    final groups = <String, List<DownloadItem>>{};
    for (final i in items) {
      (groups[i.groupKey] ??= []).add(i);
    }
    final ordered = groups.values.toList()
      ..sort((a, b) => _latest(b).compareTo(_latest(a)));
    for (final g in ordered) {
      g.sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        return byOrder != 0 ? byOrder : a.addedAt.compareTo(b.addedAt);
      });
    }
    final used = items.fold<int>(0, (sum, i) => sum + i.bytes);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Downloads')),
        actions: [
          if (anyActive)
            IconButton(
              tooltip: tr('Pause all'),
              icon: const Icon(Icons.pause),
              onPressed: () {
                for (final i in items) {
                  if (i.isActive) notifier.pause(i.id);
                }
              },
            ),
          if (anyStopped)
            IconButton(
              tooltip: tr('Resume all'),
              icon: const Icon(Icons.play_arrow),
              onPressed: () {
                for (final i in items) {
                  if (i.state == DownloadState.paused ||
                      i.state == DownloadState.failed) {
                    notifier.resume(i.id);
                  }
                }
              },
            ),
        ],
      ),
      body: items.isEmpty
          ? MessageView(
              icon: Icons.download_for_offline_outlined,
              title: tr('Nothing downloaded yet'),
              message: tr(
                'Tap the download button next to a chapter, an episode or a source to keep it on your phone. It plays with no internet.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _StorageLine(used: used),
                for (final g in ordered) ...[
                  _GroupHeader(items: g),
                  for (final i in g) _ItemTile(item: i, accent: accent),
                  const Divider(height: 1),
                ],
              ],
            ),
    );
  }

  static DateTime _latest(List<DownloadItem> g) =>
      g.map((i) => i.addedAt).reduce((a, b) => a.isAfter(b) ? a : b);
}

class _StorageLine extends ConsumerWidget {
  const _StorageLine({required this.used});

  final int used;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final free = ref.watch(downloadsFreeSpaceProvider).value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        [
          tr('Using {size}', {'size': formatBytes(used)}),
          if (free != null) tr('{size} free', {'size': formatBytes(free)}),
        ].join(' · '),
        style: const TextStyle(color: Colors.white54, fontSize: 12.5),
      ),
    );
  }
}

class _GroupHeader extends ConsumerWidget {
  const _GroupHeader({required this.items});

  final List<DownloadItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = items.first;
    final cover = items.map((i) => i.coverPath).whereType<String>().firstOrNull;
    final size = items.fold<int>(0, (s, i) => s + i.bytes);
    final done = items.where((i) => i.isDone).length;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 40,
          height: 56,
          child: cover == null
              ? Container(
                  color: Colors.white10,
                  child: const Icon(Icons.image_outlined, size: 20),
                )
              : Image.file(
                  File(cover),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(color: Colors.white10),
                ),
        ),
      ),
      title: Text(
        first.groupTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [
          if (first.kind != DownloadKind.movie || items.length > 1)
            tr('{done} of {n} saved', {'done': done, 'n': items.length}),
          if (size > 0) formatBytes(size),
        ].join(' · '),
        style: const TextStyle(color: Colors.white54, fontSize: 12.5),
      ),
      trailing: IconButton(
        tooltip: tr('Delete all'),
        icon: const Icon(Icons.delete_outline, color: Colors.white54),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(tr('Delete downloads?')),
              content: Text(
                tr(
                  '{title}: {n} items, {size}. You can download them again later.',
                  {
                    'title': first.groupTitle,
                    'n': items.length,
                    'size': formatBytes(size),
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(tr('Cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(tr('Delete')),
                ),
              ],
            ),
          );
          if (ok ?? false) {
            await ref
                .read(downloadsProvider.notifier)
                .deleteGroup(first.groupKey);
          }
        },
      ),
    );
  }
}

class _ItemTile extends ConsumerWidget {
  const _ItemTile({required this.item, this.accent});

  final DownloadItem item;
  final Color? accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = item.itemTitle.isNotEmpty
        ? item.itemTitle
        : (item.source['release'] as String?)?.split('\n').first ?? tr('Movie');
    final showBar =
        item.state == DownloadState.running ||
        (item.state != DownloadState.done && item.progress > 0);
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.only(start: 72, end: 4),
      onTap: () => item.isDone
          ? openDownload(context, ref, item)
          : showDownloadActions(context, ref, item),
      onLongPress: () => showDownloadActions(context, ref, item),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            downloadStatusText(item),
            style: TextStyle(
              fontSize: 12,
              color: item.state == DownloadState.failed
                  ? Colors.orangeAccent
                  : Colors.white54,
            ),
          ),
          if (showBar) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: item.progress > 0.01 ? item.progress : null,
              minHeight: 3,
              color: accent,
            ),
          ],
        ],
      ),
      trailing: IconButton(
        icon: item.isDone
            ? Icon(
                item.kind == DownloadKind.manga
                    ? Icons.chrome_reader_mode_outlined
                    : Icons.play_circle_outline,
                color: accent,
              )
            : DownloadStateIcon(item: item, accent: accent),
        onPressed: () => item.isDone
            ? openDownload(context, ref, item)
            : showDownloadActions(context, ref, item),
      ),
    );
  }
}
