import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/adab_models.dart';
import '../../domain/sahaba_models.dart';
import '../../knowledge_routes.dart';
import '../providers/adab_providers.dart';
import '../providers/knowledge_providers.dart';
import '../widgets/chapter_reader.dart';

const _aboutText =
    'النصوص من الكتب كما طُبعت، بلا تلخيص ولا إعادة صياغة، وقد حُذفت منها أرقام '
    'الحواشي لأن الحواشي نفسها ليست في النسخة الرقمية.\n\n'
    'هذه كتب أدب لا كتب حديث أو تاريخ محقق: يجمع مؤلفوها الأخبار والأشعار للمتعة '
    'والفائدة دون اشتراط الصحة. وفيها، على عادة زمانها، أشعار في الغزل والخمر '
    'ونوادر صريحة الألفاظ.\n\n'
    'مساعد الفهم يشرح النص فقط. وقد تقع أخطاء إملائية من النسخة الرقمية؛ يمكنك '
    'مقابلتها بالأصل من زر المصدر تحت كل فصل.';

/// The seven books.
class AdabHomeScreen extends ConsumerWidget {
  const AdabHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stats = ref.watch(adabIndexProvider).value;
    final last = ref.watch(adabProgressProvider.select((s) => s.last));
    final read = ref.watch(adabProgressProvider.select((s) => s.read));
    final lastParts = last?.split('/');
    final lastBook = lastParts == null
        ? null
        : AdabBook.values.where((b) => b.name == lastParts[0]).firstOrNull;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الأدب')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                leading: const Icon(Icons.info_outline, color: knowledgeAccent),
                title: const Text('عن هذه الكتب'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(_aboutText, style: TextStyle(height: 1.8)),
                ],
              ),
            ),
            if (lastBook != null)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: const Icon(
                    Icons.play_arrow_rounded,
                    color: knowledgeAccent,
                  ),
                  title: const Text('تابع القراءة'),
                  subtitle: Text(lastBook.title),
                  onTap: () => context.push(
                    KnowledgeRoutes.adabChapter(lastBook.name, lastParts![1]),
                  ),
                ),
              ),
            for (final book in AdabBook.values)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () =>
                      context.push(KnowledgeRoutes.adabBook(book.name)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          book.author,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: knowledgeAccent,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(book.about, style: const TextStyle(height: 1.6)),
                        if (stats?[book] case final s?) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${sahabaReadingTime(s.words)} · '
                            'قرأت ${_readIn(read, book)} من ${s.chapters} فصلاً',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

int _readIn(Set<String> read, AdabBook book) =>
    read.where((k) => k.startsWith('${book.name}/')).length;

/// A book's chapters, with a search over their titles.
class AdabBookScreen extends ConsumerStatefulWidget {
  const AdabBookScreen({super.key, required this.book});

  final AdabBook book;

  @override
  ConsumerState<AdabBookScreen> createState() => _AdabBookScreenState();
}

class _AdabBookScreenState extends ConsumerState<AdabBookScreen> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final chapters = ref.watch(adabBookProvider(book));
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(book.title)),
        body: chapters.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('تعذّر فتح الكتاب: $e')),
          data: _list,
        ),
      ),
    );
  }

  Widget _list(List<AdabChapter> chapters) {
    final read = ref.watch(adabProgressProvider.select((s) => s.read));
    final query = normalizeArabic(_query.trim());
    final shown = <int>[
      for (var i = 0; i < chapters.length; i++)
        if (query.isEmpty ||
            (chapters[i].hasText &&
                normalizeArabic(chapters[i].title).contains(query)))
          i,
    ];
    // A lazy list: al-Iqd has hundreds of chapters.
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: shown.length + 1,
      itemBuilder: (context, row) {
        if (row == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'ابحث في عناوين الفصول',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          );
        }
        final i = shown[row - 1];
        final chapter = chapters[i];
        return ChapterRow(
          title: chapter.title,
          main: chapter.level == 1,
          hasText: chapter.hasText,
          isRead: read.contains(adabKey(widget.book, i)),
          onTap: () =>
              context.push(KnowledgeRoutes.adabChapter(widget.book.name, '$i')),
        );
      },
    );
  }
}

/// One chapter of a book, with the next and previous ones that have text.
class AdabReaderScreen extends ConsumerWidget {
  const AdabReaderScreen({super.key, required this.book, required this.index});

  final AdabBook book;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapters = ref.watch(adabBookProvider(book)).value;
    if (chapters == null || index >= chapters.length) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final hasText = [for (final c in chapters) c.hasText];
    return ChapterReader(
      appBarTitle: book.title,
      lesson: chapters[index].toLesson(book, index),
      progress: adabProgressProvider,
      progressKey: adabKey(book, index),
      previous: previousWithText(hasText, index),
      next: nextWithText(hasText, index),
      onOpen: (target) => context.pushReplacement(
        KnowledgeRoutes.adabChapter(book.name, '$target'),
      ),
    );
  }
}
