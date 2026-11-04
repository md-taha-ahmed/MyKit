import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ai/gemini_client.dart';
import '../../../../core/ai/gemini_key_screen.dart';
import '../../domain/story_models.dart';
import '../../rise_fall_routes.dart';
import '../providers/rise_fall_providers.dart';

/// One part, section by section, with its text size kept between parts.
class PartReaderScreen extends ConsumerStatefulWidget {
  const PartReaderScreen({super.key, required this.id, required this.part});

  final String id;
  final int part;

  @override
  ConsumerState<PartReaderScreen> createState() => _PartReaderScreenState();
}

class _PartReaderScreenState extends ConsumerState<PartReaderScreen> {
  late final ScrollController _scroll;
  var _lastSaved = 0.0;

  @override
  void initState() {
    super.initState();
    _lastSaved = ref
        .read(storyScrollMemoryProvider)
        .read(widget.id, widget.part);
    _scroll = ScrollController(initialScrollOffset: _lastSaved)
      ..addListener(_rememberPlace);
    Future.microtask(
      () => ref
          .read(storyProgressProvider.notifier)
          .opened(widget.id, widget.part),
    );
  }

  void _rememberPlace() {
    final offset = _scroll.offset;
    if ((offset - _lastSaved).abs() < 200) return;
    _lastSaved = offset;
    ref.read(storyScrollMemoryProvider).write(widget.id, widget.part, offset);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final country = ref.watch(storyCountryProvider(widget.id));
    if (country == null || widget.part >= country.parts.length) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final p = country.parts[widget.part];
    final size = ref.watch(storyTextSizeProvider);
    final progress = ref.read(storyProgressProvider.notifier);
    final isRead = ref
        .watch(storyProgressProvider)
        .isRead(widget.id, widget.part);
    final hasNext = widget.part + 1 < country.parts.length;
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(country.name),
          actions: [
            IconButton(
              tooltip: 'تصغير الخط',
              icon: const Icon(Icons.text_decrease),
              onPressed: () =>
                  ref.read(storyTextSizeProvider.notifier).change(-1),
            ),
            IconButton(
              tooltip: 'تكبير الخط',
              icon: const Icon(Icons.text_increase),
              onPressed: () =>
                  ref.read(storyTextSizeProvider.notifier).change(1),
            ),
          ],
        ),
        // Not a lazy list: the saved place in a long chapter has to be reachable
        // as soon as the screen opens.
        body: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${p.period} · ${p.mood.label} · الجزء ${widget.part + 1} من ${country.parts.length}',
                style: TextStyle(color: moodColors[p.mood], fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                p.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in p.patterns)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        t.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () =>
                          context.push(RiseFallRoutes.pattern(t.name)),
                    ),
                ],
              ),
              for (final s in p.sections) ...[
                const SizedBox(height: 22),
                if (s.heading.isNotEmpty)
                  Text(
                    s.heading,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: size + 1,
                    ),
                  ),
                const SizedBox(height: 8),
                SelectableText(
                  s.body,
                  style: TextStyle(fontSize: size, height: 1.8),
                ),
              ],
              const SizedBox(height: 26),
              OutlinedButton.icon(
                onPressed: () => _ask(context, ref, country, p),
                icon: const Icon(Icons.help_outline),
                label: const Text('اسأل عن هذا الجزء'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () async {
                  await progress.setRead(widget.id, widget.part, true);
                  if (!context.mounted) return;
                  if (hasNext) {
                    context.pushReplacement(
                      RiseFallRoutes.part(widget.id, widget.part + 1),
                    );
                  } else {
                    context.pop();
                  }
                },
                icon: Icon(hasNext ? Icons.arrow_back : Icons.check),
                label: Text(hasNext ? 'انتهيت، الجزء التالي' : 'انتهت القصة'),
              ),
              if (isRead)
                TextButton(
                  onPressed: () =>
                      progress.setRead(widget.id, widget.part, false),
                  child: const Text('تعليم كغير مقروء'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _ask(
    BuildContext context,
    WidgetRef ref,
    StoryCountry country,
    StoryPart part,
  ) async {
    if (!ref.read(geminiClientProvider).isConfigured) {
      if (!await openGeminiKeySetup(context)) return;
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: _AskSheet(country: country, part: part),
      ),
    );
  }
}

class _AskSheet extends ConsumerStatefulWidget {
  const _AskSheet({required this.country, required this.part});

  final StoryCountry country;
  final StoryPart part;

  @override
  ConsumerState<_AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends ConsumerState<_AskSheet> {
  final _question = TextEditingController();
  String? _answer;
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final q = _question.text.trim();
    if (q.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final text = await ref
          .read(geminiClientProvider)
          .generate(
            system:
                'أنت تساعد قارئاً عربياً يفهم تاريخ ${widget.country.name}. '
                'أجب بالعربية البسيطة وباختصار. اعتمد على النص المرفق أولاً. '
                'إن أضفت شيئاً من خارجه فقل ذلك صراحة، وإن لم تكن متأكداً فقل إنك غير متأكد.',
            messages: [
              (
                fromUser: true,
                text:
                    'النص:\n${widget.part.title}\n${widget.part.fullText}\n\nالسؤال: $q',
              ),
            ],
          );
      if (mounted) setState(() => _answer = text);
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      0,
      16,
      16 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          TextField(
            controller: _question,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'سؤالك',
              hintText: 'مثلاً: لماذا فشل هذا الإصلاح؟',
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _busy ? null : _send,
            child: Text(_busy ? 'لحظة…' : 'اسأل'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
          if (_answer != null) ...[
            const SizedBox(height: 14),
            SelectableText(_answer!, style: const TextStyle(height: 1.7)),
            const SizedBox(height: 8),
            const Text(
              'إجابة من Gemini، وليست مصدراً. تحقق من المهم.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ],
      ),
    ),
  );
}
