import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mykit/core/storage/shared_preferences_provider.dart';
import 'package:mykit/core/tools/tool_definition.dart';
import 'package:mykit/core/tools/tool_switch.dart';
import 'package:mykit/core/tools/tools_provider.dart';
import 'package:mykit/features/habits/data/app_signals.dart';
import 'package:mykit/features/habits/data/nudges.dart';
import 'package:shared_preferences/shared_preferences.dart';

ToolDefinition _tool(
  String id,
  String path, {
  Future<void> Function(Ref ref, bool on)? onToggle,
}) => ToolDefinition(
  id: id,
  name: id,
  description: id,
  icon: Icons.circle,
  color: Colors.blue,
  rootPath: path,
  routes: [GoRoute(path: path, builder: (_, _) => const SizedBox())],
  onToggle: onToggle,
);

AppSignals _signals({bool foodOn = true, bool lessonOn = true}) => AppSignals(
  day: '2026-11-03',
  lessonRead: false,
  meals: const {},
  kcal: 0,
  workoutPlanned: null,
  workoutDone: false,
  questsDue: 0,
  questsAnswered: 0,
  tasksDue: 0,
  tasksOverdue: 0,
  foodOn: foodOn,
  lessonOn: lessonOn,
);

void main() {
  test('links into a turned-off tool are blocked, others are not', () {
    final tools = [_tool('music', '/music'), _tool('books', '/books')];
    const off = {'music'};
    expect(ToolSwitch.blocks('/music', tools, off), isTrue);
    expect(ToolSwitch.blocks('/music/album/1', tools, off), isTrue);
    expect(ToolSwitch.blocks('/musical', tools, off), isFalse);
    expect(ToolSwitch.blocks('/books', tools, off), isFalse);
    expect(ToolSwitch.blocks('/', tools, off), isFalse);
  });

  test('turning off saves, tells the tool, and survives a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final calls = <bool>[];
    final tool = _tool(
      'music',
      '/music',
      onToggle: (_, on) async => calls.add(on),
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        toolsProvider.overrideWithValue([tool]),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(disabledToolsProvider.notifier);

    await notifier.setOn(tool, false);
    expect(prefs.getString(ToolSwitch.key), 'music');
    expect(ToolSwitch.isOn(prefs, 'music'), isFalse);
    expect(ToolSwitch.isOn(prefs, 'books'), isTrue);

    await notifier.silenceDisabled();
    await notifier.setOn(tool, true);
    expect(calls, [false, false, true]);
    expect(ToolSwitch.isOn(prefs, 'music'), isTrue);
  });

  test('the System does not ask about turned-off sections', () {
    final night = DateTime(2026, 11, 3, 22);
    List<String> ids(AppSignals s) =>
        Nudges.open(s, night).map((n) => n.id).toList();

    expect(ids(_signals()), ['breakfast', 'lunch', 'dinner', 'lesson']);
    expect(ids(_signals(foodOn: false)), ['lesson']);
    expect(ids(_signals(lessonOn: false)), ['breakfast', 'lunch', 'dinner']);

    final text = _signals(foodOn: false, lessonOn: false).describe();
    expect(text, isNot(contains('food:')));
    expect(text, isNot(contains('workout:')));
    expect(text, isNot(contains('lesson')));
    expect(text, contains('quests answered'));
  });
}
