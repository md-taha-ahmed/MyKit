import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykit/features/limiter/domain/limiter_settings.dart';

void main() {
  test('defaults cover app, Lite and web for each platform', () {
    final s = LimiterSettings.defaults;
    expect(s.group('instagram')!.packages, contains('com.instagram.lite'));
    expect(s.group('facebook')!.packages, contains('com.facebook.lite'));
    expect(s.group('x')!.domains, containsAll(['x.com', 'twitter.com']));
    expect(
      s.group('youtube')!.packages,
      contains('app.revanced.android.youtube'),
    );
  });

  test('settings with focus hours survive JSON', () {
    final s = LimiterSettings.defaults.copyWith(
      focus: [
        const FocusWindow(
          start: TimeOfDay(hour: 23, minute: 0),
          end: TimeOfDay(hour: 7, minute: 30),
          days: {1, 5, 7},
          groups: {'instagram', 'x'},
        ),
      ],
    );
    final back = LimiterSettings.fromJson(s.toJson());
    expect(back.focus.single.label, '23:00–07:30');
    expect(back.focus.single.days, {1, 5, 7});
    expect(back.toJson(), s.toJson());
  });
}
