import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/core/i18n/ar.dart';
import 'package:mykit/core/i18n/i18n.dart';

/// `'literal'` as Dart reads it (the escapes used in this codebase).
String _unescape(String s) => s
    .replaceAll(r"\'", "'")
    .replaceAll(r'\"', '"')
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\$', r'$')
    .replaceAll(r'\\', r'\');

void main() {
  tearDown(() => I18n.apply(AppLanguage.english));

  test('English passes through; Arabic translates and fills placeholders', () {
    I18n.apply(AppLanguage.english);
    expect(tr('{n} unread', {'n': 3}), '3 unread');
    I18n.apply(AppLanguage.arabic);
    expect(tr('Settings'), 'الإعدادات');
    expect(tr('{n} unread', {'n': 3}), '3 غير مقروءة');
    // Text without a translation stays as it is.
    expect(tr('Some brand name'), 'Some brand name');
  });

  test('every tr() text in lib/ has an Arabic translation', () {
    final call = RegExp(r"""\btr\(\s*'((?:[^'\\]|\\.)*)'\s*[,)]""");
    final missing = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.contains('core/i18n')) continue;
      for (final m in call.allMatches(f.readAsStringSync())) {
        final key = _unescape(m.group(1)!);
        if (!arabicStrings.containsKey(key)) missing.add('$key  (${f.path})');
      }
    }
    expect(missing, isEmpty, reason: 'Add these to lib/core/i18n/ar.dart');
  });

  test('translations keep every {placeholder}', () {
    final ph = RegExp(r'\{[^{}]+\}');
    for (final MapEntry(:key, :value) in arabicStrings.entries) {
      final a = ph.allMatches(key).map((m) => m[0]).toList()..sort();
      final b = ph.allMatches(value).map((m) => m[0]).toList()..sort();
      expect(b, a, reason: key);
    }
  });
}
