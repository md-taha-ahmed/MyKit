import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../../core/ai/gemini_client.dart';
import '../../../../core/storage/shared_preferences_provider.dart';
import '../../../rss/data/datasources/rss_remote_data_source.dart';
import '../../data/knowledge_catalog.dart';
import '../../data/knowledge_notifications.dart';
import '../../data/knowledge_remote.dart';
import '../../data/knowledge_store.dart';
import '../../data/source_check_task.dart';
import '../../data/source_updater.dart';
import '../../domain/knowledge_models.dart';

const knowledgeAccent = Color(0xFF8D6E63);

final _httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final knowledgeRemoteProvider = Provider<KnowledgeRemote>(
  (ref) => KnowledgeRemote(ref.watch(_httpClientProvider)),
);

final knowledgeStoreProvider = Provider<KnowledgeStore>(
  (ref) => KnowledgeStore(ref.watch(sharedPreferencesProvider)),
);

final knowledgeNotificationsProvider = Provider<KnowledgeNotifications>(
  (ref) => KnowledgeNotifications(),
);

// -----------------------------------------------------------------------------
// Settings
// -----------------------------------------------------------------------------

final knowledgeSettingsProvider =
    NotifierProvider<KnowledgeSettingsNotifier, KnowledgeSettings>(
      KnowledgeSettingsNotifier.new,
    );

class KnowledgeSettingsNotifier extends Notifier<KnowledgeSettings> {
  @override
  KnowledgeSettings build() {
    final s = ref.read(knowledgeStoreProvider).settings;
    // Keeps the reminders in step after a restore or an update.
    Future.microtask(() => _schedule(s));
    return s;
  }

  Future<void> update(KnowledgeSettings s) async {
    state = s;
    await ref.read(knowledgeStoreProvider).saveSettings(s);
    await _schedule(s);
  }

  Future<void> _schedule(KnowledgeSettings s) async {
    final topics = <int, String>{};
    if (s.notify) {
      for (final MapEntry(key: day, value: id) in s.schedule.entries) {
        final track = KnowledgeCatalog.byId(id);
        if (track != null) topics[day] = '${track.topic}: ${track.title}';
      }
    }
    try {
      await ref
          .read(knowledgeNotificationsProvider)
          .schedule(topics, s.minutes);
    } catch (_) {}
    await SourceCheckScheduler.sync(
      enabled:
          s.sourceAlerts && ref.read(knowledgeStoreProvider).sources.isNotEmpty,
    );
  }
}

// -----------------------------------------------------------------------------
// Reading positions, history, saved
// -----------------------------------------------------------------------------

final trackPositionsProvider =
    NotifierProvider<TrackPositionsNotifier, Map<String, TrackPosition>>(
      TrackPositionsNotifier.new,
    );

class TrackPositionsNotifier extends Notifier<Map<String, TrackPosition>> {
  @override
  Map<String, TrackPosition> build() =>
      ref.read(knowledgeStoreProvider).positions;

  Future<void> set(String trackId, TrackPosition p) async {
    state = {...state, trackId: p};
    await ref.read(knowledgeStoreProvider).savePositions(state);
  }

  /// Back to the beginning of a track.
  Future<void> reset(String trackId) async {
    state = {...state}..remove(trackId);
    await ref.read(knowledgeStoreProvider).savePositions(state);
  }
}

/// How far through a track, 0–1 (null when not started or unknown).
double? trackProgress(KnowledgeTrack track, TrackPosition? p) {
  if (p == null) return null;
  if (p.finished) return 1;
  switch (track.kind) {
    case TrackKind.book:
      final start = track.book!.startOffset;
      final total = p.total, offset = p.offset;
      if (total == null || offset == null || total <= start) return null;
      return ((offset - start) / (total - start)).clamp(0, 1);
    case TrackKind.wikiSeries:
      return p.index / track.articles.length;
    case TrackKind.onThisDay:
      return null;
  }
}

final lessonHistoryProvider =
    NotifierProvider<LessonListNotifier, List<Lesson>>(
      () => LessonListNotifier(saved: false),
    );

final savedLessonsProvider = NotifierProvider<LessonListNotifier, List<Lesson>>(
  () => LessonListNotifier(saved: true),
);

class LessonListNotifier extends Notifier<List<Lesson>> {
  LessonListNotifier({required this.saved});

  final bool saved;

  KnowledgeStore get _store => ref.read(knowledgeStoreProvider);

  @override
  List<Lesson> build() => saved ? _store.saved : _store.history;

  Future<void> _save() =>
      saved ? _store.saveSaved(state) : _store.saveHistory(state);

  Future<void> add(Lesson l) async {
    state = [l, ...state.where((x) => x.id != l.id)];
    await _save();
  }

  Future<void> remove(String id) async {
    state = state.where((x) => x.id != id).toList();
    await _save();
  }

  bool contains(String id) => state.any((x) => x.id == id);
}

// -----------------------------------------------------------------------------
// Getting lessons
// -----------------------------------------------------------------------------

final knowledgeControllerProvider = Provider<KnowledgeController>(
  KnowledgeController.new,
);

class KnowledgeController {
  KnowledgeController(this._ref);

  final Ref _ref;
  final _busy = <String, Future<Lesson>>{};

  /// The next passage of [track]; moves its position forward. Concurrent
  /// calls for one track share the same request.
  Future<Lesson> readNext(KnowledgeTrack track) =>
      _busy[track.id] ??= _readNext(track).whenComplete(() {
        _busy.remove(track.id);
      });

  Future<Lesson> _readNext(KnowledgeTrack track) async {
    final remote = _ref.read(knowledgeRemoteProvider);
    final positions = _ref.read(trackPositionsProvider.notifier);
    final position =
        _ref.read(trackPositionsProvider)[track.id] ?? const TrackPosition();
    final Lesson lesson;
    switch (track.kind) {
      case TrackKind.book:
        if (position.finished) {
          throw const KnowledgeException('أكملت هذا الكتاب، بارك الله فيك.');
        }
        final r = await remote.nextPassage(track, position);
        lesson = r.lesson;
        await positions.set(track.id, r.next);
      case TrackKind.wikiSeries:
        if (position.index >= track.articles.length) {
          throw const KnowledgeException('أكملت هذه السلسلة.');
        }
        lesson = await remote.article(track, position.index);
        final next = position.index + 1;
        await positions.set(
          track.id,
          TrackPosition(index: next, finished: next >= track.articles.length),
        );
      case TrackKind.onThisDay:
        return remote.onThisDay(track, DateTime.now());
    }
    final last = {..._ref.read(knowledgeStoreProvider).lastRead}
      ..[track.id] = lesson;
    await _ref.read(knowledgeStoreProvider).saveLastRead(last);
    return lesson;
  }

  /// One article of a series, without moving the position.
  Future<Lesson> article(KnowledgeTrack track, int index) =>
      _ref.read(knowledgeRemoteProvider).article(track, index);

  Lesson? lastRead(String trackId) =>
      _ref.read(knowledgeStoreProvider).lastRead[trackId];
}

/// Today's lesson: the track scheduled for this weekday, fetched once and
/// kept (so it's there offline and stays the same all day).
final todayLessonProvider = AsyncNotifierProvider<TodayLessonNotifier, Lesson>(
  TodayLessonNotifier.new,
);

class TodayLessonNotifier extends AsyncNotifier<Lesson> {
  String? _day;

  /// The day this lesson is for (to notice midnight).
  String? get day => _day;

  @override
  Future<Lesson> build() async {
    final today = dayKey(DateTime.now());
    _day = today;
    for (final l in ref.read(lessonHistoryProvider)) {
      if (l.day == today) return l;
    }
    final settings = ref.read(knowledgeSettingsProvider);
    final id = settings.schedule[DateTime.now().weekday] ?? 'seerah';
    final track = KnowledgeCatalog.byId(id) ?? KnowledgeCatalog.seerah;
    final lesson = (await ref.read(knowledgeControllerProvider).readNext(track))
        .copyWith(day: today);
    await ref.read(lessonHistoryProvider.notifier).add(lesson);
    return lesson;
  }

  /// Rebuilds if the date changed since the lesson was picked.
  void checkDay() {
    if (_day != dayKey(DateTime.now())) ref.invalidateSelf();
  }
}

/// "On this day" from Arabic Wikipedia, kept for the day.
final onThisDayProvider = FutureProvider<Lesson>((ref) async {
  final store = ref.read(knowledgeStoreProvider);
  final today = dayKey(DateTime.now());
  final cached = store.onThisDay;
  if (cached != null && cached.day == today) return cached;
  final lesson = await ref
      .read(knowledgeRemoteProvider)
      .onThisDay(KnowledgeCatalog.onThisDay, DateTime.now());
  await store.saveOnThisDay(lesson);
  return lesson;
});

// -----------------------------------------------------------------------------
// AI helper (explains the text; never a source)
// -----------------------------------------------------------------------------

const _helperSystem = '''
أنت مساعد تعلّم داخل تطبيق. سيُعطى لك نص منقول من مصدر (كتاب تراثي أو مقالة).
مهمتك الوحيدة: مساعدة القارئ على فهم هذا النص نفسه.

قواعد صارمة:
- لا تضف أي آية أو حديث أو قول أو اسم أو تاريخ أو معلومة غير موجودة في النص.
- لا تُصدر فتوى ولا ترجّح بين الأقوال. إن كان في النص حكم فاشرح ما يقوله النص فقط.
- إن احتاج الفهم إلى معلومة خارج النص فقل: «النص لا يذكر ذلك».
- اكتب بالعربية الفصحى المبسطة، وباختصار.

اكتب بهذا الشكل بالضبط (Markdown):
### معاني الكلمات
- الكلمة: معناها (من 3 إلى 6 كلمات صعبة من النص)
### الفكرة الرئيسية
سطران أو ثلاثة.
### ماذا نتعلم
- 2 إلى 3 نقاط مأخوذة من النص.
### أسئلة للمراجعة
1. سؤال (الإجابة من النص في سطر تالٍ يبدأ بـ «الجواب:»)
2. …
3. …
''';

const _helperSystemModern =
    '''
$_helperSystem
وأضف في النهاية:
### صلة بعالمنا اليوم
سطران عن أثر هذا الحدث كما يذكره النص نفسه فقط.
''';

/// The explanation of a lesson (by id): cached, or asked from Gemini on
/// demand.
final lessonExplanationProvider =
    AsyncNotifierProvider.family<LessonExplanationNotifier, String?, String>(
      LessonExplanationNotifier.new,
    );

class LessonExplanationNotifier extends AsyncNotifier<String?> {
  LessonExplanationNotifier(this.lessonId);

  final String lessonId;

  @override
  Future<String?> build() async =>
      ref.read(knowledgeStoreProvider).explanation(lessonId);

  Future<void> explain(Lesson lesson) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final gemini = ref.read(geminiClientProvider);
      if (!gemini.isConfigured) {
        throw const AiException('أضف مفتاح Gemini من إعدادات القارئ أولاً.');
      }
      final modern = lesson.trackId == KnowledgeCatalog.modernWorld.id;
      final text = await gemini.generate(
        system: modern ? _helperSystemModern : _helperSystem,
        temperature: 0.2,
        messages: [
          (
            fromUser: true,
            text:
                'المصدر: ${lesson.reference.source}'
                '${lesson.reference.author != null ? ' — ${lesson.reference.author}' : ''}\n'
                'العنوان: ${lesson.title}\n\n'
                'النص:\n${lesson.plainText}',
          ),
        ],
      );
      await ref.read(knowledgeStoreProvider).saveExplanation(lesson.id, text);
      return text;
    });
  }
}

// -----------------------------------------------------------------------------
// Sources (sites and channels; pages without a feed are watched)
// -----------------------------------------------------------------------------

final knowledgeSourcesProvider =
    NotifierProvider<KnowledgeSourcesNotifier, List<KnowledgeSource>>(
      KnowledgeSourcesNotifier.new,
    );

class KnowledgeSourcesNotifier extends Notifier<List<KnowledgeSource>> {
  @override
  List<KnowledgeSource> build() => ref.read(knowledgeStoreProvider).sources;

  /// Finds the site's feed, or falls back to watching the page itself.
  Future<KnowledgeSource> add(String input) async {
    final uri = RssRemoteDataSource.normalize(input);
    final rss = RssRemoteDataSource(ref.read(_httpClientProvider));
    KnowledgeSource source;
    try {
      final preview = await rss.discover(uri.toString());
      source = KnowledgeSource(
        id: const Uuid().v4(),
        name: preview.feed.title,
        url: uri.toString(),
        feedUrl: preview.url,
      );
    } catch (_) {
      final page = await ref
          .read(knowledgeRemoteProvider)
          .watch(uri.toString());
      if (page.links.isEmpty) {
        throw const KnowledgeException('لم أجد مقالات في هذه الصفحة.');
      }
      source = KnowledgeSource(
        id: const Uuid().v4(),
        name: page.title.isEmpty ? uri.host : page.title,
        url: uri.toString(),
      );
    }
    state = [...state, source];
    await ref.read(knowledgeStoreProvider).saveSources(state);
    await _syncSchedule();
    unawaited(ref.read(sourceItemsProvider.notifier).refresh());
    return source;
  }

  /// The background check runs only while there's something to follow.
  Future<void> _syncSchedule() => SourceCheckScheduler.sync(
    enabled:
        ref.read(knowledgeSettingsProvider).sourceAlerts && state.isNotEmpty,
  );

  Future<void> rename(String id, String name) async {
    state = [
      for (final s in state)
        s.id == id
            ? KnowledgeSource(
                id: s.id,
                name: name,
                url: s.url,
                feedUrl: s.feedUrl,
              )
            : s,
    ];
    await ref.read(knowledgeStoreProvider).saveSources(state);
  }

  Future<void> remove(String id) async {
    state = state.where((s) => s.id != id).toList();
    await ref.read(knowledgeStoreProvider).saveSources(state);
    await _syncSchedule();
    await ref.read(sourceItemsProvider.notifier).dropSource(id);
  }
}

final sourceItemsProvider =
    NotifierProvider<SourceItemsNotifier, SourceItemsState>(
      SourceItemsNotifier.new,
    );

class SourceItemsState {
  const SourceItemsState({
    this.items = const [],
    this.loading = false,
    this.failed = const {},
  });

  final List<SourceItem> items;
  final bool loading;

  /// Source ids that couldn't be refreshed last time.
  final Set<String> failed;
}

class SourceItemsNotifier extends Notifier<SourceItemsState> {
  static const _refreshEvery = Duration(hours: 3);

  KnowledgeStore get _store => ref.read(knowledgeStoreProvider);

  @override
  SourceItemsState build() {
    // The background check may have found articles while MyKit was away.
    final lifecycle = AppLifecycleListener(onResume: reloadFromDisk);
    ref.onDispose(lifecycle.dispose);
    return SourceItemsState(items: _store.items);
  }

  Future<void> reloadFromDisk() async {
    await _store.reload();
    if (state.loading) return;
    state = SourceItemsState(items: _store.items, failed: state.failed);
  }

  /// Checks when the last check (here or in the background) was a while ago.
  Future<void> refreshIfStale() async {
    await reloadFromDisk();
    final last = _store.lastSourceCheck;
    if (last != null && DateTime.now().difference(last) < _refreshEvery) return;
    await refresh();
  }

  Future<void> refresh() async {
    if (state.loading) return;
    state = SourceItemsState(
      items: state.items,
      loading: true,
      failed: state.failed,
    );
    try {
      final update = await SourceUpdater(
        _store,
        ref.read(_httpClientProvider),
      ).run();
      state = SourceItemsState(items: update.items, failed: update.failed);
    } catch (_) {
      state = SourceItemsState(items: state.items, failed: state.failed);
    }
  }

  Future<void> markSeen(String url) async {
    if (!state.items.any((i) => i.url == url && i.isNew)) return;
    await _replace([
      for (final i in state.items) i.url == url ? i.copyWith(isNew: false) : i,
    ]);
  }

  Future<void> markAllSeen() => _replace([
    for (final i in state.items) i.isNew ? i.copyWith(isNew: false) : i,
  ]);

  Future<void> dropSource(String id) =>
      _replace(state.items.where((i) => i.sourceId != id).toList());

  Future<void> _replace(List<SourceItem> items) async {
    state = SourceItemsState(
      items: items,
      loading: state.loading,
      failed: state.failed,
    );
    await _store.saveItems(items);
  }
}
