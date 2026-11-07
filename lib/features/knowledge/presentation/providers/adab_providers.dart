import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/adab_models.dart';
import 'reading_progress.dart';

final adabIndexProvider = FutureProvider<Map<AdabBook, AdabBookStats>>((
  ref,
) async {
  final text = await rootBundle.loadString('assets/adab/index.txt');
  return AdabBookStats.parseIndex(text);
});

final adabBookProvider = FutureProvider.family<List<AdabChapter>, AdabBook>((
  ref,
  book,
) async {
  final text = await rootBundle.loadString('assets/adab/${book.name}.txt');
  return parseAdabFile(text);
});

/// Which chapter a book is on: `uyun/12`.
String adabKey(AdabBook book, int index) => '${book.name}/$index';

final adabProgressProvider =
    NotifierProvider<ReadingProgressNotifier, ReadingProgress>(
      () => ReadingProgressNotifier('adab'),
    );
