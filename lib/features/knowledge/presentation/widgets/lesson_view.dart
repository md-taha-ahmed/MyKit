import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/ai/gemini_client.dart';
import '../../../../core/ai/gemini_key_screen.dart';
import '../../../../core/widgets/simple_markdown.dart';
import '../../data/knowledge_catalog.dart';
import '../../domain/knowledge_models.dart';
import '../providers/knowledge_providers.dart';

const arabicBody = TextStyle(fontSize: 18.5, height: 1.95);

Future<void> openLink(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
  } catch (_) {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

/// A lesson exactly as in its source, its reference, and (below a clear
/// line) the AI helper.
class LessonView extends ConsumerWidget {
  const LessonView({
    super.key,
    required this.lesson,
    this.showHelper = true,
    this.footer,
  });

  final Lesson lesson;
  final bool showHelper;

  /// Extra buttons under the reference ("next passage"…).
  final Widget? footer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final track = KnowledgeCatalog.byId(lesson.trackId);
    final helperOn = ref.watch(
      knowledgeSettingsProvider.select((s) => s.aiHelper),
    );
    final blocks = lesson.blocks;
    // The title is shown above; don't repeat it as the first heading.
    final body =
        blocks.isNotEmpty &&
            blocks.first.heading &&
            blocks.first.text == lesson.title
        ? blocks.skip(1)
        : blocks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (track != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Chip(
              label: Text(track.topic),
              visualDensity: VisualDensity.compact,
              side: BorderSide.none,
              backgroundColor: knowledgeAccent.withValues(alpha: 0.18),
            ),
          ),
        const SizedBox(height: 6),
        SelectableText(
          lesson.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 14),
        for (final b in body)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: b.heading
                ? Text(
                    b.text,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: knowledgeAccent,
                      fontWeight: FontWeight.w700,
                      height: 1.6,
                    ),
                  )
                : SelectableText(b.text, style: arabicBody),
          ),
        const SizedBox(height: 4),
        _ReferenceCard(lesson: lesson),
        ?footer,
        if (showHelper && helperOn) ...[
          const SizedBox(height: 22),
          _HelperBox(lesson: lesson),
        ],
      ],
    );
  }
}

class _ReferenceCard extends ConsumerWidget {
  const _ReferenceCard({required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final r = lesson.reference;
    final saved = ref.watch(savedLessonsProvider).any((l) => l.id == lesson.id);
    final cite = [r.source, ?r.author, ?r.chapter, ?r.location].join('، ');

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.menu_book_outlined,
                  size: 18,
                  color: knowledgeAccent,
                ),
                const SizedBox(width: 8),
                Text('المصدر', style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              cite,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
            ),
            if (r.edition case final e?)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  e,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => openLink(r.checkUrl ?? r.url),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(
                    r.checkUrl != null && r.checkUrl!.contains('shamela')
                        ? 'في المكتبة الشاملة'
                        : 'اقرأ الأصل',
                  ),
                ),
                if (r.checkUrl != null)
                  TextButton(
                    onPressed: () => openLink(r.url),
                    child: const Text('النص المستخدم'),
                  ),
                IconButton(
                  tooltip: saved ? 'إزالة من المحفوظات' : 'حفظ',
                  onPressed: () {
                    final n = ref.read(savedLessonsProvider.notifier);
                    saved ? n.remove(lesson.id) : n.add(lesson);
                  },
                  icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
                ),
                IconButton(
                  tooltip: 'نسخ مع المصدر',
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(
                        text:
                            '${lesson.title}\n\n${lesson.plainText}\n\n— $cite',
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('نُسخ النص مع المصدر')),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The AI explains the passage; it's labelled as not a source.
class _HelperBox extends ConsumerWidget {
  const _HelperBox({required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final explanation = ref.watch(lessonExplanationProvider(lesson.id));
    final notifier = ref.read(lessonExplanationProvider(lesson.id).notifier);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text('مساعد الفهم', style: theme.textTheme.titleSmall),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'شرح بالذكاء الاصطناعي — ليس مصدراً',
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          switch (explanation) {
            AsyncData(value: final text?) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SimpleMarkdown(
                  text,
                  style: const TextStyle(fontSize: 16, height: 1.8),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed: () => notifier.explain(lesson),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('شرح جديد'),
                  ),
                ),
              ],
            ),
            AsyncLoading() => const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
            AsyncError(:final error) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$error',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                if (!ref.watch(geminiClientProvider).isConfigured)
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      if (await openGeminiKeySetup(context)) {
                        await notifier.explain(lesson);
                      }
                    },
                    icon: const Icon(Icons.key),
                    label: const Text('إعداد مفتاح Gemini'),
                  ),
                TextButton(
                  onPressed: () => notifier.explain(lesson),
                  child: const Text('حاول مرة أخرى'),
                ),
              ],
            ),
            _ => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'معاني الكلمات، الفكرة الرئيسية، وأسئلة للمراجعة — من هذا النص فقط.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () => notifier.explain(lesson),
                  icon: const Icon(Icons.lightbulb_outline),
                  label: const Text('اشرح لي'),
                ),
              ],
            ),
          },
        ],
      ),
    );
  }
}
