import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/feed_article.dart';
import '../providers/rss_providers.dart';

void _snack(
  ScaffoldMessengerState messenger,
  String text, {
  SnackBarAction? action,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        action: action,
        duration: const Duration(seconds: 3),
        // Snackbars with an action persist by default; let Undo time out.
        persist: false,
      ),
    );
}

/// Bookmarks / un-bookmarks with feedback.
Future<void> toggleSaveArticle(
  BuildContext context,
  WidgetRef ref,
  FeedArticle article,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final saved = await ref
      .read(rssReactionsProvider.notifier)
      .toggleSave(article);
  _snack(messenger, saved ? 'Saved to bookmarks' : 'Removed from bookmarks');
}

/// Deletes an article with an Undo. In the Saved view "delete" removes the
/// bookmark instead (the article itself may no longer be in any feed).
Future<void> deleteArticle(
  BuildContext context,
  WidgetRef ref,
  FeedArticle article, {
  required bool fromSaved,
}) async {
  // Captured up front: the caller may navigate away right after.
  final messenger = ScaffoldMessenger.of(context);
  final notifier = ref.read(rssReactionsProvider.notifier);
  if (fromSaved) {
    await notifier.toggleSave(article);
    _snack(
      messenger,
      'Bookmark removed',
      action: SnackBarAction(
        label: 'UNDO',
        onPressed: () => notifier.toggleSave(article),
      ),
    );
    return;
  }
  await notifier.delete(article.id);
  _snack(
    messenger,
    'Article deleted',
    action: SnackBarAction(
      label: 'UNDO',
      onPressed: () => notifier.undoDelete(article.id),
    ),
  );
}

/// Coloured background shown behind a swiping article tile.
class SwipeBackground extends StatelessWidget {
  const SwipeBackground({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.alignment,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final left = alignment == Alignment.centerLeft;
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!left)
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (!left) const SizedBox(width: 8),
          Icon(icon),
          if (left) const SizedBox(width: 8),
          if (left)
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
