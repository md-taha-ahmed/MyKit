import '../../../../core/i18n/i18n.dart';
import '../entities/feed_article.dart';

enum ReadingLength { preview, short, medium, long }

/// How long an article takes to read, from the text the feed provides (or a
/// fuller copy saved for offline reading).
class ReadingTime {
  const ReadingTime(this.minutes, this.length);

  /// 0 means under a minute.
  final int minutes;
  final ReadingLength length;

  /// Average silent reading speeds (words per minute). Arabic words carry
  /// more per word and are read more slowly.
  static const _wpm = 230;
  static const _wpmArabic = 180;

  /// Fewer words than this with no full content: the feed only has a teaser.
  static const _teaserWords = 80;

  static final _arabic = RegExp('[\u0600-\u06FF]');
  static final _space = RegExp(r'\s+');

  static ReadingTime of(FeedArticle article, {String? fullText}) {
    final text = fullText != null && fullText.length > article.content.length
        ? fullText
        : (article.content.isNotEmpty ? article.content : article.summary);
    return forText(
      text,
      teaserOnly: fullText == null && article.content.isEmpty,
    );
  }

  static ReadingTime forText(String text, {bool teaserOnly = false}) {
    final trimmed = text.trim();
    final words = trimmed.isEmpty ? 0 : trimmed.split(_space).length;
    if (teaserOnly && words < _teaserWords) {
      return const ReadingTime(0, ReadingLength.preview);
    }
    final sample = trimmed.length > 500 ? trimmed.substring(0, 500) : trimmed;
    final arabic = _arabic.allMatches(sample).length * 3 > sample.length;
    final minutes = (words / (arabic ? _wpmArabic : _wpm)).round();
    return ReadingTime(
      minutes,
      minutes < 3
          ? ReadingLength.short
          : minutes < 8
          ? ReadingLength.medium
          : ReadingLength.long,
    );
  }

  String get label => switch (length) {
    ReadingLength.preview => tr('Preview'),
    _ when minutes < 1 => tr('< 1 min'),
    _ => tr('{m} min', {'m': minutes}),
  };
}
