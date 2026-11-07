import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/sahaba_models.dart';
import '../../knowledge_routes.dart';
import '../providers/knowledge_providers.dart';
import '../providers/sahaba_providers.dart';
import '../widgets/chapter_reader.dart';

/// Who the section opens on, because they were asked for by name.
const _featuredId = 'umar';

const _aboutText =
    'النص من كتابين قديمين كما طُبعا، بلا تلخيص ولا إعادة صياغة: «الرياض النضرة» '
    'للمحب الطبري (مفصّل، في العشرة المبشرين)، و«صفة الصفوة» لابن الجوزي (مختصر، '
    'في 156 صحابياً وصحابية).\n\n'
    'جمع المؤلفان الروايات ولم يشترطا الصحة، ففي الكتابين الصحيح والضعيف وما لا '
    'يثبت. ويذكران كثيراً من أخرج الرواية، كقولهما «خرجه البخاري»، وما لم يُنسب '
    'لا يُعرف حاله من الكتاب وحده؛ فللحكم على رواية بعينها ارجع إلى أهل العلم.\n\n'
    'مساعد الفهم يشرح النص فقط ولا يحكم على صحته. وقد تقع أخطاء إملائية من '
    'النسخة الرقمية؛ يمكنك مقابلتها بالأصل من زر المصدر تحت كل فصل.';

/// Everyone in the book, by class, with search.
class SahabaHomeScreen extends ConsumerStatefulWidget {
  const SahabaHomeScreen({super.key});

  @override
  ConsumerState<SahabaHomeScreen> createState() => _SahabaHomeScreenState();
}

class _SahabaHomeScreenState extends ConsumerState<SahabaHomeScreen> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(sahabaIndexProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('سير الصحابة')),
        body: people.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('تعذّر فتح الكتاب: $e')),
          data: _list,
        ),
      ),
    );
  }

  Widget _list(List<SahabaPerson> people) {
    final theme = Theme.of(context);
    final query = normalizeArabic(_query.trim());
    final shown = query.isEmpty
        ? people
        : people.where((p) => normalizeArabic(p.name).contains(query)).toList();
    final featured = people.firstWhere((p) => p.id == _featuredId);
    final last = ref.watch(sahabaProgressProvider.select((s) => s.last));

    final rows = <Widget>[
      if (query.isEmpty) ...[
        const _AboutCard(),
        if (last != null) _ContinueCard(people: people, lastKey: last),
        _PersonCard(person: featured),
        const SizedBox(height: 8),
      ],
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: TextField(
          decoration: const InputDecoration(
            hintText: 'ابحث عن صحابي أو صحابية',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      if (shown.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('لا يوجد هذا الاسم في الكتابين.'),
        ),
    ];

    String? group;
    for (final p in shown) {
      if (p.group != group) {
        group = p.group;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
            child: Text(
              p.group,
              style: theme.textTheme.titleSmall?.copyWith(
                color: knowledgeAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
      rows.add(_PersonRow(person: p));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: rows,
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.info_outline, color: knowledgeAccent),
        title: const Text('عن هذا النص ومدى صحته'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: const [Text(_aboutText, style: TextStyle(height: 1.8))],
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.people, required this.lastKey});

  final List<SahabaPerson> people;
  final String lastKey;

  @override
  Widget build(BuildContext context) {
    final parts = lastKey.split('/');
    if (parts.length != 3) return const SizedBox.shrink();
    final person = people.where((p) => p.id == parts[0]).firstOrNull;
    if (person == null) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.play_arrow_rounded, color: knowledgeAccent),
        title: const Text('تابع القراءة'),
        subtitle: Text(person.name),
        onTap: () => context.push(
          KnowledgeRoutes.sahabaChapter(parts[0], parts[1], parts[2]),
        ),
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person});

  final SahabaPerson person;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: knowledgeAccent.withValues(alpha: 0.16),
      child: InkWell(
        onTap: () => context.push(KnowledgeRoutes.sahabaPerson(person.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                person.name,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'إسلامه، وصفته، وزهده وخوفه وتواضعه، وشفقته على رعيته، '
                'وخلافته ومقتله.',
                style: TextStyle(height: 1.7),
              ),
              const SizedBox(height: 6),
              Text(
                '${sahabaReadingTime(person.riyadWords)} مفصّلاً · '
                '${sahabaReadingTime(person.sifatWords)} مختصراً',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person});

  final SahabaPerson person;

  @override
  Widget build(BuildContext context) {
    final words = person.riyadWords + person.sifatWords;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        title: Text(person.name),
        subtitle: Text(sahabaReadingTime(words)),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => context.push(KnowledgeRoutes.sahabaPerson(person.id)),
      ),
    );
  }
}

SahabaPerson? _find(List<SahabaPerson>? people, String id) =>
    people?.where((p) => p.id == id).firstOrNull;

/// A person's chapters. Someone with a single chapter opens straight in it.
class SahabaPersonScreen extends ConsumerStatefulWidget {
  const SahabaPersonScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<SahabaPersonScreen> createState() => _SahabaPersonScreenState();
}

class _SahabaPersonScreenState extends ConsumerState<SahabaPersonScreen> {
  SahabaBook? _picked;

  @override
  Widget build(BuildContext context) {
    final person = _find(ref.watch(sahabaIndexProvider).value, widget.id);
    final books = ref.watch(sahabaPersonProvider(widget.id)).value;
    if (person == null || books == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final book = _picked ?? person.books.first;
    final chapters = books[book] ?? const <SahabaChapter>[];
    final readable = [
      for (var i = 0; i < chapters.length; i++)
        if (chapters[i].hasText) i,
    ];
    if (person.books.length == 1 && readable.length == 1) {
      return SahabaReaderScreen(
        id: widget.id,
        book: book,
        index: readable.single,
      );
    }

    final theme = Theme.of(context);
    final read = ref.watch(sahabaProgressProvider.select((s) => s.read));
    final done = readable
        .where((i) => read.contains(sahabaKey(widget.id, book, i)))
        .length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(person.name)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (person.books.length > 1) ...[
              SegmentedButton<SahabaBook>(
                showSelectedIcon: false,
                segments: [
                  for (final b in person.books)
                    ButtonSegment(value: b, label: Text(b.label)),
                ],
                selected: {book},
                onSelectionChanged: (s) => setState(() => _picked = s.single),
              ),
              const SizedBox(height: 10),
            ],
            Text(
              '${book.title}، ${book.author}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              '${sahabaReadingTime(person.words(book))} · '
              'قرأت $done من ${readable.length}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < chapters.length; i++)
              ChapterRow(
                title: chapters[i].title,
                main: chapters[i].level == 1,
                hasText: chapters[i].hasText,
                isRead: read.contains(sahabaKey(widget.id, book, i)),
                onTap: () => context.push(
                  KnowledgeRoutes.sahabaChapter(widget.id, book.name, '$i'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One chapter of a person, with the next and previous ones that have text.
class SahabaReaderScreen extends ConsumerWidget {
  const SahabaReaderScreen({
    super.key,
    required this.id,
    required this.book,
    required this.index,
  });

  final String id;
  final SahabaBook book;
  final int index;

  void _open(BuildContext context, int target) => context.pushReplacement(
    KnowledgeRoutes.sahabaChapter(id, book.name, '$target'),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = _find(ref.watch(sahabaIndexProvider).value, id);
    final chapters = ref.watch(sahabaPersonProvider(id)).value?[book];
    if (person == null || chapters == null || index >= chapters.length) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final hasText = [for (final c in chapters) c.hasText];
    return ChapterReader(
      appBarTitle: person.name,
      lesson: chapters[index].toLesson(person, book, index),
      progress: sahabaProgressProvider,
      progressKey: sahabaKey(id, book, index),
      previous: previousWithText(hasText, index),
      next: nextWithText(hasText, index),
      onOpen: (target) => _open(context, target),
    );
  }
}
