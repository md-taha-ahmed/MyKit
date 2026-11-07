import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/knowledge_models.dart';
import '../providers/knowledge_providers.dart';
import '../providers/reading_progress.dart';
import 'lesson_view.dart';

int? previousWithText(List<bool> hasText, int index) {
  for (var i = index - 1; i >= 0; i--) {
    if (hasText[i]) return i;
  }
  return null;
}

int? nextWithText(List<bool> hasText, int index) {
  for (var i = index + 1; i < hasText.length; i++) {
    if (hasText[i]) return i;
  }
  return null;
}

/// A row in a list of chapters. One with no text only heads those under it.
class ChapterRow extends StatelessWidget {
  const ChapterRow({
    super.key,
    required this.title,
    required this.main,
    required this.hasText,
    required this.isRead,
    required this.onTap,
  });

  final String title;

  /// A main chapter, rather than one inside it.
  final bool main;
  final bool hasText;
  final bool isRead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Text(
      title,
      style: main
          ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)
          : theme.textTheme.bodyMedium?.copyWith(height: 1.6),
    );
    if (!hasText) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: text,
      );
    }
    return Padding(
      padding: EdgeInsetsDirectional.only(start: main ? 0 : 14, bottom: 6),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: text),
                if (isRead) ...[
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.check_circle,
                    size: 18,
                    color: knowledgeAccent,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One chapter, word for word. Remembers how far down you were, so a power
/// cut doesn't lose your place.
class ChapterReader extends ConsumerStatefulWidget {
  const ChapterReader({
    super.key,
    required this.appBarTitle,
    required this.lesson,
    required this.progress,
    required this.progressKey,
    required this.previous,
    required this.next,
    required this.onOpen,
  });

  final String appBarTitle;
  final Lesson lesson;
  final NotifierProvider<ReadingProgressNotifier, ReadingProgress> progress;
  final String progressKey;
  final int? previous;
  final int? next;
  final ValueChanged<int> onOpen;

  @override
  ConsumerState<ChapterReader> createState() => _ChapterReaderState();
}

class _ChapterReaderState extends ConsumerState<ChapterReader> {
  late final ScrollController _scroll;
  late double _lastSaved;

  ReadingProgressNotifier get _progress => ref.read(widget.progress.notifier);

  @override
  void initState() {
    super.initState();
    _lastSaved = _progress.scroll(widget.progressKey);
    _scroll = ScrollController(initialScrollOffset: _lastSaved)
      ..addListener(_onScroll);
    Future.microtask(() => _progress.opened(widget.progressKey));
  }

  void _onScroll() {
    final position = _scroll.position;
    if ((position.pixels - _lastSaved).abs() >= 200) {
      _lastSaved = position.pixels;
      _progress.saveScroll(widget.progressKey, position.pixels);
    }
    _markIfAtEnd();
  }

  /// The reference and the helper sit under the text.
  void _markIfAtEnd() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 500) {
      _progress.markRead(widget.progressKey);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _markIfAtEnd());
    final previous = widget.previous;
    final next = widget.next;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.appBarTitle)),
        // Not a lazy list: the saved place has to be reachable on opening.
        body: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
          child: LessonView(
            lesson: widget.lesson,
            footer: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  if (previous != null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => widget.onOpen(previous),
                        child: const Text('السابق'),
                      ),
                    ),
                  if (previous != null && next != null)
                    const SizedBox(width: 10),
                  if (next != null)
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          _progress.markRead(widget.progressKey);
                          widget.onOpen(next);
                        },
                        child: const Text('الفصل التالي'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
