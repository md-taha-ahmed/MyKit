/// Minimal HTML → plain text conversion for feed content.
abstract final class HtmlText {
  static final _blockBreak = RegExp(
    r'<\s*(br|/p|/div|/li|/h[1-6]|/blockquote|/tr)\b[^>]*>',
    caseSensitive: false,
  );
  static final _dropBlocks = RegExp(
    r'<\s*(script|style)\b[^>]*>.*?<\s*/\s*\1\s*>',
    caseSensitive: false,
    dotAll: true,
  );
  static final _tags = RegExp(r'<[^>]+>');
  static final _img = RegExp(
    r'''<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  );
  static final _entity = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);');

  static const _named = {
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'ndash': '–',
    'mdash': '—',
    'hellip': '…',
    'lsquo': '‘',
    'rsquo': '’',
    'ldquo': '“',
    'rdquo': '”',
    'copy': '©',
    'reg': '®',
    'trade': '™',
  };

  /// Plain text with paragraph breaks preserved as blank lines.
  static String toPlain(String html) {
    var text = html.replaceAll(_dropBlocks, '');
    text = text.replaceAll(_blockBreak, '\n\n');
    text = text.replaceAll(_tags, '');
    text = decodeEntities(text);
    text = text
        .replaceAll('\r', '')
        .replaceAll(RegExp(r'[ \t ]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  /// First `<img src>` in [html], if any.
  static String? firstImage(String html) => _img.firstMatch(html)?.group(1);

  static String decodeEntities(String text) {
    return text.replaceAllMapped(_entity, (m) {
      final code = m.group(1)!;
      if (code.startsWith('#x') || code.startsWith('#X')) {
        final v = int.tryParse(code.substring(2), radix: 16);
        return v == null ? m.group(0)! : String.fromCharCode(v);
      }
      if (code.startsWith('#')) {
        final v = int.tryParse(code.substring(1));
        return v == null ? m.group(0)! : String.fromCharCode(v);
      }
      return _named[code.toLowerCase()] ?? m.group(0)!;
    });
  }

  /// Shortens [text] to [max] characters on a word boundary.
  static String truncate(String text, int max) {
    if (text.length <= max) return text;
    final cut = text.lastIndexOf(' ', max);
    return '${text.substring(0, cut > max * .6 ? cut : max).trimRight()}…';
  }
}
