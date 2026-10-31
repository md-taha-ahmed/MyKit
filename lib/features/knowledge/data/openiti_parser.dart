import 'dart:convert';
import 'dart:typed_data';

import '../domain/knowledge_models.dart';

/// A page of the printed edition (volume, page).
typedef PrintedPage = ({int volume, int page});

class ParsedPassage {
  const ParsedPassage({
    required this.blocks,
    required this.consumed,
    required this.pages,
    required this.lastHeading,
    required this.reachedEnd,
    required this.cutShort,
  });

  final List<LessonBlock> blocks;

  /// Bytes from the start of the chunk to where the next passage begins.
  final int consumed;

  /// Printed pages the passage spans, in order.
  final List<PrintedPage> pages;

  /// The chapter the next passage starts in.
  final String? lastHeading;

  /// Nothing left after this passage.
  final bool reachedEnd;

  /// The chunk ended before the passage did; fetch more and parse again.
  final bool cutShort;

  bool get isEmpty => blocks.every((b) => b.heading);
}

/// Reads one lesson-sized passage out of an OpenITI mARkdown chunk.
///
/// The format: `# ` starts a paragraph, `~~` continues it, `### |` (or `||`)
/// is a heading, and `PageV09P412` marks the end of printed page 412 of
/// volume 9 (Shamela-style `[ص: 32]` headings mark the start of page 32).
/// `ms123` milestones, `@QB@` tags and the header are dropped. The text
/// itself is never changed.
abstract final class OpenItiParser {
  static final _pageTag = RegExp(r'PageV(\d+)P(\d+)');
  static final _shamelaPage = RegExp(r'^\[ص:\s*(\d+)\]$');
  static final _milestone = RegExp(r'\bms\d+\b');
  static final _tag = RegExp(r'@[A-Z]{1,4}\d*@');
  static final _hadithNumber = RegExp(r'^(\d+)\s*[-–]\s*$');
  static final _spaces = RegExp(r'\s+');

  /// [chunk] must start at a line start. Unless [atFileEnd], its last
  /// (possibly cut) line is left for the next fetch.
  static ParsedPassage parse(
    Uint8List chunk, {
    required bool atFileEnd,
    required int minChars,
    required int maxChars,
    String? heading,
  }) {
    final lines = <({int start, int end})>[];
    var lineStart = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] == 0x0A) {
        lines.add((start: lineStart, end: i + 1));
        lineStart = i + 1;
      }
    }
    if (atFileEnd && lineStart < chunk.length) {
      lines.add((start: lineStart, end: chunk.length));
    }

    final blocks = <LessonBlock>[];
    final pages = <PrintedPage>[];
    final paragraph = StringBuffer();
    var chars = 0;
    var currentHeading = heading;
    int? stopAt;
    var stopIndex = lines.length;

    void addPage(int volume, int page) {
      if (volume == 0 && page == 0) return; // "unknown page"
      final p = (volume: volume, page: page);
      if (pages.isEmpty || pages.last != p) pages.add(p);
    }

    /// Strips markup, collecting page markers.
    String clean(String text) {
      for (final m in _pageTag.allMatches(text)) {
        addPage(int.parse(m.group(1)!), int.parse(m.group(2)!));
      }
      return text
          .replaceAll(_pageTag, ' ')
          .replaceAll(_milestone, ' ')
          .replaceAll(_tag, ' ')
          .replaceAll('%~%', ' … ')
          .replaceAll(_spaces, ' ')
          .trim();
    }

    void flush() {
      final text = paragraph.toString().trim();
      paragraph.clear();
      if (text.isEmpty) return;
      blocks.add(LessonBlock(text));
      chars += text.length;
    }

    for (var i = 0; i < lines.length; i++) {
      final raw = utf8
          .decode(
            chunk.sublist(lines[i].start, lines[i].end),
            allowMalformed: true,
          )
          .trimRight();
      if (raw.startsWith('######OpenITI') || raw.startsWith('#META#')) {
        continue;
      }

      final isHeading = raw.startsWith('### ');
      final startsParagraph = isHeading || raw.startsWith('# ');

      if (startsParagraph) {
        flush();
        final hasText = chars > 0;
        if (hasText &&
            (chars >= maxChars || (isHeading && chars >= minChars))) {
          stopAt = lines[i].start;
          stopIndex = i;
          break;
        }
      }

      if (isHeading) {
        final text = clean(raw.replaceFirst(RegExp(r'^###\s*\|+\s*'), ''));
        if (text.isEmpty) continue;
        if (_shamelaPage.firstMatch(text) case final m?) {
          final start = int.parse(m.group(1)!);
          if (start > 1) {
            addPage(pages.isEmpty ? 1 : pages.last.volume, start - 1);
          }
          continue;
        }
        final title = _headingText(text);
        // "الحديث الثاني" names a passage, not the chapter it's in.
        if (!title.startsWith('الحديث')) currentHeading = title;
        blocks.add(LessonBlock(title, heading: true));
      } else if (raw.startsWith('# ')) {
        paragraph.write(
          clean(raw.substring(2).replaceFirst(RegExp(r'^\$+\s*'), '')),
        );
      } else {
        final text = clean(
          raw.startsWith('~~')
              ? raw.substring(2)
              : raw.replaceFirst(RegExp(r'^#+\s*'), ''),
        );
        if (text.isNotEmpty) {
          if (paragraph.isNotEmpty) paragraph.write(' ');
          paragraph.write(text);
        }
      }
    }
    if (stopAt == null) flush();

    // The passage's last lines are on the page whose end marker comes next.
    for (var i = stopIndex; i < lines.length; i++) {
      final raw = utf8.decode(
        chunk.sublist(lines[i].start, lines[i].end),
        allowMalformed: true,
      );
      final m = _pageTag.firstMatch(raw);
      if (m != null && m.group(0) != 'PageV00P000') {
        addPage(int.parse(m.group(1)!), int.parse(m.group(2)!));
        break;
      }
      if (_shamelaPage.firstMatch(
            raw.replaceFirst(RegExp(r'^###\s*\|+\s*'), '').trim(),
          )
          case final s?) {
        final start = int.parse(s.group(1)!);
        if (start > 1) {
          addPage(pages.isEmpty ? 1 : pages.last.volume, start - 1);
        }
        break;
      }
    }

    // Drop trailing headings: they belong to the next passage.
    while (blocks.isNotEmpty && blocks.last.heading && stopAt != null) {
      blocks.removeLast();
    }

    final consumed = stopAt ?? (lines.isEmpty ? 0 : lines.last.end);
    return ParsedPassage(
      blocks: blocks,
      consumed: consumed,
      pages: pages,
      lastHeading: currentHeading,
      reachedEnd: atFileEnd && stopAt == null,
      cutShort: !atFileEnd && stopAt == null,
    );
  }

  static String _headingText(String text) {
    final number = _hadithNumber.firstMatch(text);
    if (number != null) return 'الحديث رقم ${number.group(1)}';
    var t = text;
    if (t.startsWith('[')) t = t.replaceFirst('[', '').replaceFirst(']', '');
    t = t
        .replaceFirst(RegExp(r'^[-–:\s]+'), '')
        .replaceFirst(RegExp(r'[:\s]+$'), '');
    return t;
  }

  /// "ج9، ص412–413" / "ص45".
  static String? location(List<PrintedPage> pages, {required bool volumes}) {
    if (pages.isEmpty) return null;
    final first = pages.first, last = pages.last;
    String vol(PrintedPage p) => volumes ? 'ج${p.volume}، ' : '';
    if (first == last) return '${vol(first)}ص${first.page}';
    if (first.volume == last.volume) {
      return '${vol(first)}ص${first.page}–${last.page}';
    }
    return '${vol(first)}ص${first.page} – ${vol(last)}ص${last.page}';
  }
}
