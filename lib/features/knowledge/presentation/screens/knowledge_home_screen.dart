import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/knowledge_catalog.dart';
import '../../data/knowledge_remote.dart';
import '../../domain/knowledge_models.dart';
import '../../knowledge_routes.dart';
import '../providers/knowledge_providers.dart';
import '../widgets/lesson_view.dart';

const _weekdays = {
  6: 'السبت',
  7: 'الأحد',
  1: 'الاثنين',
  2: 'الثلاثاء',
  3: 'الأربعاء',
  4: 'الخميس',
  5: 'الجمعة',
};

/// علم وتاريخ: today's lesson, the library, followed sources and saved
/// lessons, all in Arabic, right to left.
class KnowledgeHomeScreen extends ConsumerStatefulWidget {
  const KnowledgeHomeScreen({super.key});

  @override
  ConsumerState<KnowledgeHomeScreen> createState() =>
      _KnowledgeHomeScreenState();
}

class _KnowledgeHomeScreenState extends ConsumerState<KnowledgeHomeScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(todayLessonProvider.notifier).checkDay(),
    );
    // Asks once, so the daily reminder can show (Android 13+).
    Future.microtask(() async {
      final settings = ref.read(knowledgeSettingsProvider);
      if (settings.notify) {
        await ref.read(knowledgeNotificationsProvider).requestPermission();
      }
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('علم وتاريخ'),
            actions: [
              IconButton(
                tooltip: 'الإعدادات',
                onPressed: () => _showSettings(context),
                icon: const Icon(Icons.tune),
              ),
            ],
            bottom: const TabBar(
              isScrollable: false,
              tabs: [
                Tab(text: 'درس اليوم'),
                Tab(text: 'المكتبة'),
                Tab(text: 'المصادر'),
                Tab(text: 'المحفوظات'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [_TodayTab(), _LibraryTab(), _SourcesTab(), _SavedTab()],
          ),
        ),
      ),
    );
  }

  void _showSettings(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const Directionality(
      textDirection: TextDirection.rtl,
      child: _SettingsSheet(),
    ),
  );
}

// -----------------------------------------------------------------------------
// Today
// -----------------------------------------------------------------------------

class _TodayTab extends ConsumerWidget {
  const _TodayTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lesson = ref.watch(todayLessonProvider);
    final now = DateTime.now();
    final date = '${KnowledgeRemote.dayName(now)} ${now.year}';

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(onThisDayProvider);
        await ref
            .read(todayLessonProvider.future)
            .catchError((_) => lesson.value!);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 40),
        children: [
          Text(
            '${_weekdays[now.weekday]}، $date',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          switch (lesson) {
            AsyncData(:final value) => LessonView(
              lesson: value,
              footer: _ContinueButton(trackId: value.trackId),
            ),
            AsyncError(:final error) => _ErrorBox(
              message: error is KnowledgeException
                  ? error.message
                  : 'تعذّر تحميل درس اليوم.',
              onRetry: () => ref.invalidate(todayLessonProvider),
            ),
            _ => const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()),
            ),
          },
          const SizedBox(height: 28),
          const _OnThisDayCard(),
        ],
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: OutlinedButton.icon(
      onPressed: () => context.push(KnowledgeRoutes.read(trackId)),
      icon: const Icon(Icons.chrome_reader_mode_outlined),
      label: const Text('أكمل القراءة في هذا الكتاب'),
    ),
  );
}

class _OnThisDayCard extends ConsumerWidget {
  const _OnThisDayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final otd = ref.watch(onThisDayProvider);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: switch (otd) {
          AsyncData(:final value) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.public, color: knowledgeAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      value.title,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              for (var i = 0; i + 1 < value.blocks.length; i += 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(
                          value.blocks[i].text,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: knowledgeAccent,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          value.blocks[i + 1].text,
                          style: const TextStyle(fontSize: 16, height: 1.7),
                        ),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LessonScreen(lesson: value),
                    ),
                  ),
                  child: const Text('المصدر والشرح'),
                ),
              ),
            ],
          ),
          AsyncError() => Row(
            children: [
              const Icon(Icons.public_off_outlined),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('حدث في مثل هذا اليوم غير متاح الآن.'),
              ),
              TextButton(
                onPressed: () => ref.invalidate(onThisDayProvider),
                child: const Text('إعادة'),
              ),
            ],
          ),
          _ => const SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(
      children: [
        const Icon(Icons.cloud_off_outlined, size: 40),
        const SizedBox(height: 10),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        FilledButton.tonal(
          onPressed: onRetry,
          child: const Text('حاول مرة أخرى'),
        ),
      ],
    ),
  );
}

// -----------------------------------------------------------------------------
// Library
// -----------------------------------------------------------------------------

class _LibraryTab extends ConsumerWidget {
  const _LibraryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positions = ref.watch(trackPositionsProvider);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          'القراءة من هنا تتقدّم في الدرس اليومي أيضاً.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (final track in KnowledgeCatalog.scheduled)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => context.push(KnowledgeRoutes.read(track.id)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.topic,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: knowledgeAccent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(track.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      track.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Progress(track: track, position: positions[track.id]),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.track, this.position});

  final KnowledgeTrack track;
  final TrackPosition? position;

  @override
  Widget build(BuildContext context) {
    final p = trackProgress(track, position);
    final label = switch (p) {
      null => 'لم تبدأ بعد',
      1 => 'اكتمل',
      final v when track.kind == TrackKind.wikiSeries =>
        '${position!.index} من ${track.articles.length} (${(v * 100).round()}٪)',
      final v => '${(v * 100).toStringAsFixed(v < 0.1 ? 1 : 0)}٪',
    };
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: p ?? 0,
              minHeight: 6,
              color: knowledgeAccent,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Sources
// -----------------------------------------------------------------------------

/// Suggestions to start with (the user can remove them).
const _suggested = [
  (name: 'الإسلام سؤال وجواب', url: 'https://islamqa.info/ar'),
  (name: 'شبكة الألوكة', url: 'https://www.alukah.net/'),
  (name: 'إسلام أون لاين', url: 'https://islamonline.net/'),
];

class _SourcesTab extends ConsumerStatefulWidget {
  const _SourcesTab();

  @override
  ConsumerState<_SourcesTab> createState() => _SourcesTabState();
}

class _SourcesTabState extends ConsumerState<_SourcesTab> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(sourceItemsProvider.notifier).refreshIfStale(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sources = ref.watch(knowledgeSourcesProvider);
    final state = ref.watch(sourceItemsProvider);
    final names = {for (final s in sources) s.id: s.name};

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addSource(context),
        icon: const Icon(Icons.add),
        label: const Text('إضافة مصدر'),
      ),
      body: RefreshIndicator(
        onRefresh: ref.read(sourceItemsProvider.notifier).refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            if (state.loading) const LinearProgressIndicator(),
            if (sources.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
                child: Text(
                  _checkedLabel(
                    ref.read(knowledgeStoreProvider).lastSourceCheck,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (sources.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final s in sources)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: InputChip(
                          label: Text(s.name, overflow: TextOverflow.ellipsis),
                          avatar: Icon(
                            state.failed.contains(s.id)
                                ? Icons.error_outline
                                : (s.watchesPage
                                      ? Icons.visibility_outlined
                                      : Icons.rss_feed),
                            size: 16,
                          ),
                          onPressed: () => _manageSource(context, s),
                        ),
                      ),
                  ],
                ),
              ),
            if (sources.isEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'تابع مواقع وقنوات تثق بها',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'أضف رابط موقع أو قناة يوتيوب. إن لم يكن للموقع RSS، يتابع MyKit صفحته '
                'ويُظهر المقالات الجديدة هنا.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 16),
              Text('اقتراحات:', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in _suggested)
                    ActionChip(
                      label: Text(s.name),
                      avatar: const Icon(Icons.add, size: 16),
                      onPressed: () => _add(context, s.url),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            for (final item in state.items)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                title: Text(
                  item.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: item.isNew ? FontWeight.w700 : FontWeight.w400,
                    height: 1.5,
                  ),
                ),
                subtitle: Text(
                  '${names[item.sourceId] ?? ''} · ${_ago(item.date)}',
                  style: theme.textTheme.bodySmall,
                ),
                trailing: item.isNew
                    ? const Badge(
                        label: Text('جديد'),
                        backgroundColor: knowledgeAccent,
                      )
                    : null,
                onTap: () {
                  ref.read(sourceItemsProvider.notifier).markSeen(item.url);
                  openLink(item.url);
                },
              ),
          ],
        ),
      ),
    );
  }

  static String _checkedLabel(DateTime? at) {
    final when = at == null ? 'لم يُفحص بعد' : 'آخر فحص ${_ago(at)}';
    return '$when · يُفحص تلقائياً كل 4 ساعات تقريباً';
  }

  static String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes.clamp(1, 59)} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    if (diff.inDays < 30) return 'منذ ${diff.inDays} يوم';
    return '${KnowledgeRemote.dayName(d)} ${d.year}';
  }

  Future<void> _add(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('جارٍ البحث عن المقالات…')),
    );
    try {
      final s = await ref.read(knowledgeSourcesProvider.notifier).add(url);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              s.watchesPage
                  ? 'أُضيف «${s.name}» — لا يوجد RSS، سأتابع الصفحة.'
                  : 'أُضيف «${s.name}».',
            ),
          ),
        );
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('تعذّرت الإضافة: $e')));
    }
  }

  Future<void> _addSource(BuildContext context) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إضافة مصدر'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              hintText: 'رابط موقع أو قناة يوتيوب',
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
    if (url != null && url.trim().isNotEmpty && context.mounted) {
      await _add(context, url.trim());
    }
  }

  Future<void> _manageSource(BuildContext context, KnowledgeSource s) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(s.name),
                subtitle: Text(
                  s.watchesPage ? 'متابعة الصفحة (لا يوجد RSS)' : 'RSS',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('فتح الموقع'),
                onTap: () => Navigator.pop(context, 'open'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('إعادة التسمية'),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('حذف'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'open':
        await openLink(s.url);
      case 'delete':
        await ref.read(knowledgeSourcesProvider.notifier).remove(s.id);
      case 'rename':
        final controller = TextEditingController(text: s.name);
        final name = await showDialog<String>(
          context: context,
          builder: (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('اسم المصدر'),
              content: TextField(controller: controller, autofocus: true),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, controller.text),
                  child: const Text('حفظ'),
                ),
              ],
            ),
          ),
        );
        if (name != null && name.trim().isNotEmpty) {
          await ref
              .read(knowledgeSourcesProvider.notifier)
              .rename(s.id, name.trim());
        }
    }
  }
}

// -----------------------------------------------------------------------------
// Saved & history
// -----------------------------------------------------------------------------

class _SavedTab extends ConsumerWidget {
  const _SavedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedLessonsProvider);
    final history = ref.watch(lessonHistoryProvider);
    final theme = Theme.of(context);

    Widget tile(Lesson l, {bool showDay = false}) {
      final track = KnowledgeCatalog.byId(l.trackId);
      return ListTile(
        title: Text(l.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [?track?.topic, if (showDay && l.day != null) l.day!].join(' · '),
        ),
        leading: const Icon(Icons.article_outlined, color: knowledgeAccent),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => LessonScreen(lesson: l)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('المحفوظة', style: theme.textTheme.titleMedium),
        ),
        if (saved.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text('اضغط 🔖 تحت أي درس لحفظه هنا.'),
          ),
        for (final l in saved) tile(l),
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text('الدروس السابقة', style: theme.textTheme.titleMedium),
        ),
        for (final l in history) tile(l, showDay: true),
      ],
    );
  }
}

/// One lesson on its own page (from the archive, saved…).
class LessonScreen extends StatelessWidget {
  const LessonScreen({super.key, required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(
        title: Text(KnowledgeCatalog.byId(lesson.trackId)?.title ?? 'درس'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
        children: [LessonView(lesson: lesson)],
      ),
    ),
  );
}

// -----------------------------------------------------------------------------
// Settings
// -----------------------------------------------------------------------------

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(knowledgeSettingsProvider);
    final notifier = ref.read(knowledgeSettingsProvider.notifier);
    final theme = Theme.of(context);
    final time = TimeOfDay(hour: s.minutes ~/ 60, minute: s.minutes % 60);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('الإعدادات', style: theme.textTheme.titleLarge),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('تذكير بدرس اليوم'),
              value: s.notify,
              onChanged: (v) async {
                if (v) {
                  await ref
                      .read(knowledgeNotificationsProvider)
                      .requestPermission();
                }
                await notifier.update(s.copyWith(notify: v));
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: s.notify,
              title: const Text('وقت التذكير'),
              trailing: Text(time.format(context)),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: time,
                );
                if (picked != null) {
                  await notifier.update(
                    s.copyWith(minutes: picked.hour * 60 + picked.minute),
                  );
                }
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إشعار بالمقالات الجديدة'),
              subtitle: const Text(
                'يفحص مصادرك كل 4 ساعات تقريباً، حتى والتطبيق مغلق',
              ),
              value: s.sourceAlerts,
              onChanged: (v) async {
                if (v) {
                  await ref
                      .read(knowledgeNotificationsProvider)
                      .requestPermission();
                }
                await notifier.update(s.copyWith(sourceAlerts: v));
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('مساعد الفهم (الذكاء الاصطناعي)'),
              subtitle: const Text('يشرح النص فقط، ولا يُعتمد مصدراً'),
              value: s.aiHelper,
              onChanged: (v) => notifier.update(s.copyWith(aiHelper: v)),
            ),
            const Divider(height: 24),
            Text('ماذا أتعلم كل يوم', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final MapEntry(key: day, value: name) in _weekdays.entries)
              Row(
                children: [
                  SizedBox(width: 80, child: Text(name)),
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value:
                          KnowledgeCatalog.byId(s.schedule[day] ?? '') != null
                          ? s.schedule[day]
                          : KnowledgeCatalog.seerah.id,
                      items: [
                        for (final t in KnowledgeCatalog.scheduled)
                          DropdownMenuItem(
                            value: t.id,
                            child: Text(
                              '${t.topic} — ${t.title}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (id) {
                        if (id == null) return;
                        notifier.update(
                          s.copyWith(schedule: {...s.schedule, day: id}),
                        );
                      },
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Text(
              'النصوص من كتب أصلية (مكتبة OpenITI المفتوحة، بطبعاتها المذكورة) ومن ويكيبيديا '
              'العربية لتاريخ العالم. الدروس الفقهية نصوص وليست فتوى؛ للمسائل الشخصية اسأل أهل العلم.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
