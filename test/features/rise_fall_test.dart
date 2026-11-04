import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/features/rise_fall/domain/story_models.dart';
import 'package:mykit/features/rise_fall/presentation/providers/rise_fall_providers.dart';

StoryCountry _load(String id) =>
    StoryCountry.parse(id, File('assets/rise_fall/$id.txt').readAsStringSync());

void main() {
  test('every country parses, with all sections, sources and long parts', () {
    for (final id in storyCountryIds) {
      final c = _load(id);
      expect(c.parts.length, greaterThanOrEqualTo(5), reason: id);
      expect(c.sources.length, greaterThanOrEqualTo(4), reason: id);
      for (final p in c.parts) {
        expect(p.sections.length, greaterThanOrEqualTo(7), reason: p.title);
        expect(p.patterns, isNotEmpty);
        // The point is not to be a summary.
        expect(p.words, greaterThan(350), reason: '$id: ${p.title}');
      }
    }
  });

  test('every country has both falls and something else', () {
    for (final id in storyCountryIds) {
      final moods = _load(id).parts.map((p) => p.mood).toSet();
      expect(moods, contains(StoryMood.fall), reason: id);
      expect(moods.length, greaterThan(1), reason: id);
    }
  });

  test('every pattern appears in several countries, or comparing is empty', () {
    final all = storyCountryIds.map(_load).toList();
    for (final t in StoryPattern.values) {
      final n = all.where((c) => c.parts.any((p) => p.patterns.contains(t)));
      expect(n.length, greaterThanOrEqualTo(3), reason: t.name);
    }
  });

  test('every country is long chapters ending in summary and debate', () {
    for (final id in storyCountryIds) {
      final c = _load(id);
      expect(c.note, isNotNull, reason: id);
      for (final p in c.parts) {
        expect(p.isChapter, isTrue, reason: '$id: ${p.title}');
        expect(p.words, greaterThan(1100), reason: '$id: ${p.title}');
        expect(p.sections[p.sections.length - 2].body, p.takeaway);
        expect(p.sections.last.body, p.debate);
        expect(p.sections.every((s) => s.body.isNotEmpty), isTrue);
      }
    }
  });

  test('a chapter without its summary is an error', () {
    expect(
      () => StoryCountry.parse(
        'x',
        '@name a\n@group ruin\n@tagline b\n@part\n@title c\n@period d\n'
            '@mood fall\n@patterns war\n@oneline e\n@story\n## h\nbody\n'
            '@debate\nf\n',
      ),
      throwsFormatException,
    );
  });

  test('a missing section is an error, not an empty heading', () {
    expect(
      () => StoryCountry.parse(
        'x',
        '@name a\n@group ruin\n@tagline b\n@part\n@title c\n',
      ),
      throwsFormatException,
    );
  });
}
