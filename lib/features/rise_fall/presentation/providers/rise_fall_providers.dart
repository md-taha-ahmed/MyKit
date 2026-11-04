import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/storage/shared_preferences_provider.dart';
import '../../domain/story_models.dart';

const riseFallAccent = Color(0xFFC62828);

const moodColors = {
  StoryMood.fall: Color(0xFFEF5350),
  StoryMood.rise: Color(0xFF66BB6A),
  StoryMood.mixed: Color(0xFFFFB74D),
};

/// The stories, in the order they're listed. Their files ship in the app, so
/// reading needs no internet.
const storyCountryIds = [
  'germany',
  'japan',
  'south_korea',
  'rwanda',
  'china',
  'poland',
  'vietnam',
  'turkey',
  'malaysia',
  'egypt',
  'yemen',
];

final storiesProvider = FutureProvider<List<StoryCountry>>((ref) async {
  return [
    for (final id in storyCountryIds)
      StoryCountry.parse(
        id,
        await rootBundle.loadString('assets/rise_fall/$id.txt'),
      ),
  ];
});

final storyCountryProvider = Provider.family<StoryCountry?, String>((ref, id) {
  final all = ref.watch(storiesProvider).value ?? const <StoryCountry>[];
  return all.where((c) => c.id == id).firstOrNull;
});

/// What you've read: finished parts per country, and where you last were.
class StoryProgress {
  const StoryProgress({this.read = const {}, this.lastCountry, this.lastPart});

  final Map<String, Set<int>> read;
  final String? lastCountry;
  final int? lastPart;

  int readIn(String id) => read[id]?.length ?? 0;
  bool isRead(String id, int part) => read[id]?.contains(part) ?? false;
}

final storyProgressProvider =
    NotifierProvider<StoryProgressNotifier, StoryProgress>(
      StoryProgressNotifier.new,
    );

class StoryProgressNotifier extends Notifier<StoryProgress> {
  static const _key = 'risefall.progress.v1';

  @override
  StoryProgress build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_key);
    if (raw == null) return const StoryProgress();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return StoryProgress(
        read: {
          for (final e in (j['read'] as Map<String, dynamic>).entries)
            e.key: {for (final i in e.value as List) i as int},
        },
        lastCountry: j['country'] as String?,
        lastPart: j['part'] as int?,
      );
    } catch (_) {
      return const StoryProgress();
    }
  }

  Future<void> _save(StoryProgress p) async {
    state = p;
    await ref
        .read(sharedPreferencesProvider)
        .setString(
          _key,
          jsonEncode({
            'read': {for (final e in p.read.entries) e.key: e.value.toList()},
            'country': ?p.lastCountry,
            'part': ?p.lastPart,
          }),
        );
  }

  Future<void> opened(String id, int part) =>
      _save(StoryProgress(read: state.read, lastCountry: id, lastPart: part));

  Future<void> setRead(String id, int part, bool read) {
    final parts = {...?state.read[id]};
    read ? parts.add(part) : parts.remove(part);
    return _save(
      StoryProgress(
        read: {...state.read, id: parts},
        lastCountry: state.lastCountry,
        lastPart: state.lastPart,
      ),
    );
  }
}

/// Reading text size, kept between parts.
final storyTextSizeProvider = NotifierProvider<StoryTextSize, double>(
  StoryTextSize.new,
);

class StoryTextSize extends Notifier<double> {
  static const _key = 'risefall.textSize';

  @override
  double build() => ref.read(sharedPreferencesProvider).getDouble(_key) ?? 17;

  Future<void> change(double by) async {
    state = (state + by).clamp(14, 26);
    await ref.read(sharedPreferencesProvider).setDouble(_key, state);
  }
}

/// How far down each part you were, so a power cut doesn't lose your place in
/// a long chapter.
class StoryScrollMemory {
  const StoryScrollMemory(this._prefs);

  final SharedPreferences _prefs;

  String _key(String id, int part) => 'risefall.scroll.$id.$part';

  double read(String id, int part) => _prefs.getDouble(_key(id, part)) ?? 0;

  Future<void> write(String id, int part, double offset) =>
      _prefs.setDouble(_key(id, part), offset);
}

final storyScrollMemoryProvider = Provider<StoryScrollMemory>(
  (ref) => StoryScrollMemory(ref.read(sharedPreferencesProvider)),
);
