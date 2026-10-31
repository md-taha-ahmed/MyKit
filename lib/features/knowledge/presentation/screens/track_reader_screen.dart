import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/knowledge_catalog.dart';
import '../../data/knowledge_remote.dart';
import '../../domain/knowledge_models.dart';
import '../providers/knowledge_providers.dart';
import '../widgets/lesson_view.dart';

/// Reads a book (or article series) passage by passage, from where the
/// daily lessons have reached. Reading on moves that position too.
class TrackReaderScreen extends ConsumerStatefulWidget {
  const TrackReaderScreen({super.key, required this.trackId});

  final String trackId;

  @override
  ConsumerState<TrackReaderScreen> createState() => _TrackReaderScreenState();
}

class _TrackReaderScreenState extends ConsumerState<TrackReaderScreen> {
  late final KnowledgeTrack _track =
      KnowledgeCatalog.byId(widget.trackId) ?? KnowledgeCatalog.seerah;

  /// Passages read in this visit (to go back without re-downloading).
  final _pages = <Lesson>[];
  var _index = 0;
  var _loading = false;
  String? _error;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final last = ref.read(knowledgeControllerProvider).lastRead(_track.id);
    if (last != null) {
      _pages.add(last);
    } else {
      Future.microtask(_next);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_index + 1 < _pages.length) {
      setState(() => _index++);
      _toTop();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lesson = await ref
          .read(knowledgeControllerProvider)
          .readNext(_track);
      if (!mounted) return;
      setState(() {
        _pages.add(lesson);
        _index = _pages.length - 1;
      });
      _toTop();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is KnowledgeException ? e.message : 'تعذّر التحميل.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _previous() {
    if (_index == 0) return;
    setState(() => _index--);
    _toTop();
  }

  void _toTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _openArticle(int i) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lesson = await ref
          .read(knowledgeControllerProvider)
          .article(_track, i);
      if (!mounted) return;
      setState(() {
        _pages.add(lesson);
        _index = _pages.length - 1;
      });
      _toTop();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restart() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('البدء من جديد؟'),
          content: Text('ستعود دروس «${_track.title}» إلى أول الكتاب.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ابدأ'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await ref.read(trackPositionsProvider.notifier).reset(_track.id);
    setState(() {
      _pages.clear();
      _index = 0;
    });
    await _next();
  }

  void _showIndex() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final position = ref.read(trackPositionsProvider)[_track.id];
      return Directionality(
        textDirection: TextDirection.rtl,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (context, controller) => ListView(
            controller: controller,
            children: [
              for (final (i, title) in _track.articles.indexed)
                ListTile(
                  leading: Text('${i + 1}'),
                  title: Text(title),
                  trailing: i < (position?.index ?? 0)
                      ? const Icon(
                          Icons.check,
                          size: 18,
                          color: knowledgeAccent,
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(context);
                    _openArticle(i);
                  },
                ),
            ],
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(trackPositionsProvider)[_track.id];
    final progress = trackProgress(_track, position);
    final lesson = _pages.isEmpty ? null : _pages[_index];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_track.title),
          actions: [
            if (_track.kind == TrackKind.wikiSeries)
              IconButton(
                tooltip: 'الفهرس',
                onPressed: _showIndex,
                icon: const Icon(Icons.list),
              ),
            PopupMenuButton<String>(
              onSelected: (v) => v == 'restart' ? _restart() : null,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'restart',
                  child: Text('البدء من أول الكتاب'),
                ),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: _loading ? null : (progress ?? 0),
              color: knowledgeAccent,
              minHeight: 3,
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        _loading ||
                            (position?.finished ?? false) &&
                                _index + 1 >= _pages.length
                        ? null
                        : _next,
                    icon: const Icon(
                      Icons.arrow_forward,
                    ), // mirrored: points left in RTL
                    label: const Text('التالي'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _index > 0 && !_loading ? _previous : null,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('السابق'),
                ),
              ],
            ),
          ),
        ),
        body: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
          children: [
            if (_error case final e?)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  title: Text(e),
                  trailing: TextButton(
                    onPressed: _next,
                    child: const Text('إعادة'),
                  ),
                ),
              ),
            if (lesson != null)
              LessonView(lesson: lesson)
            else if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}
