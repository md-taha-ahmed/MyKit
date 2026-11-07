import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/sahaba_models.dart';
import 'reading_progress.dart';

final sahabaIndexProvider = FutureProvider<List<SahabaPerson>>((ref) async {
  final text = await rootBundle.loadString('assets/sahaba/index.txt');
  return SahabaPerson.parseIndex(text);
});

final sahabaPersonProvider =
    FutureProvider.family<Map<SahabaBook, List<SahabaChapter>>, String>((
      ref,
      id,
    ) async {
      final text = await rootBundle.loadString('assets/sahaba/$id.txt');
      return parseSahabaFile(text);
    });

/// Which chapter a person is on: `umar/riyad/12`.
String sahabaKey(String person, SahabaBook book, int index) =>
    '$person/${book.name}/$index';

final sahabaProgressProvider =
    NotifierProvider<ReadingProgressNotifier, ReadingProgress>(
      () => ReadingProgressNotifier('sahaba'),
    );
