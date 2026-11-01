import 'dart:convert';

import '../../../core/ai/gemini_client.dart';
import '../domain/habit_analysis.dart';
import '../domain/habit_models.dart';
import '../domain/patterns.dart';

/// A change the System proposes; applied only when you accept it.
class CoachChange {
  const CoachChange(this.type, this.data);

  /// tiny / full / anchor / time / days / if_then / swap_exercise.
  final String type;
  final Map<String, dynamic> data;

  static CoachChange? fromJson(Object? j) {
    if (j is! Map) return null;
    final type = j['type'];
    if (type is! String) return null;
    return CoachChange(type, Map<String, dynamic>.from(j));
  }
}

/// The System's conclusion at the end of a talk.
class CoachProposal {
  const CoachProposal({
    required this.insight,
    required this.understanding,
    this.life,
    this.changes = const [],
    this.next = '',
  });

  final String insight;
  final HabitUnderstanding understanding;

  /// The rewritten picture of your life (null: unchanged).
  final String? life;
  final List<CoachChange> changes;

  /// The next quest, made doable.
  final String next;
}

/// The System's reply: what it says, and its proposal once it has one.
typedef CoachReply = ({String text, CoachProposal? proposal});

/// A workout habit's context from the Fitness tool.
class WorkoutContext {
  const WorkoutContext({
    required this.routineId,
    required this.routineName,
    required this.exercises,
  });

  final String routineId;
  final String routineName;

  /// Exercises in order, with how often they were skipped and what can
  /// replace them (ids the System may swap to).
  final List<
    ({
      int index,
      String id,
      String name,
      String target,
      int skipped,
      int sessions,
      List<({String id, String name})> alternatives,
    })
  >
  exercises;
}

/// Talks to Gemini as "the System". Everything it needs is gathered on the
/// phone into a small context, so a talk is a few short requests (free
/// plan friendly).
class HabitCoach {
  HabitCoach(this._gemini);

  final GeminiClient _gemini;

  /// After this many answers the System must conclude.
  static const maxTurns = 4;

  static const _system = '''
You are "the System", the voice of a habit app styled after the manhwa Solo Leveling: short, direct, a little dramatic, but warm and on the user's side. You are also grounded in behaviour science: habits form by repeating a behaviour in the same context until it is automatic (often around two months, very variable); tiny versions keep the chain alive; if-then plans ("If X, then I will Y") help; missing once doesn't matter, missing twice starts a slide; harsh self-criticism lowers motivation while self-compassion raises it; obstacles can be practical (cue, time, energy, environment) or emotional (fear of failing, feeling incapable, shame).

The user lives in an unstable situation (Yemen, a war zone; moving between places, power and internet cuts, security, family needs). Treat that as real life, not an excuse. Never shame, never use toxic positivity. If they sound overwhelmed or in distress, put them first: acknowledge it, shrink the quest to almost nothing, and gently suggest talking to someone they trust. You are not a therapist and don't diagnose.

How to talk:
- One short message at a time (2–5 sentences). Ask at most ONE question per message.
- First understand the real reason. Dig under the surface answer: is it practical or emotional? Connect it to their history and to what you already understand (given below). Name patterns you see, with evidence.
- If an exercise or task feels impossible (e.g. "I can't do pull-ups"), explore the feeling, then make it doable: an easier progression or a swap to an alternative from the list given.
- When you understand enough (usually after 1–3 answers, or when told to conclude), give your conclusion in your message, then add a JSON block in ```json fences:
{"insight": "one sentence about the real reason",
 "understanding": {"root": "the root cause as you now understand it", "evidence": "what in the history shows it", "helps": "what works for them", "fails": "what doesn't", "confidence": 0-100},
 "life": "the updated picture of their life situation, or \\"\\" if nothing new",
 "changes": [ ... 0 to 3 changes ... ],
 "next": "the next quest, made doable"}
Rewrite "understanding" as a whole: keep what is still true, correct what was wrong, add what's new.
Allowed changes:
 {"type":"tiny","text":"new 2-minute version"}
 {"type":"full","text":"new full version"}
 {"type":"anchor","text":"new cue: after I ..."}
 {"type":"time","minutes": minutes after midnight}
 {"type":"days","weekdays":[1-7, Monday=1]}
 {"type":"if_then","if":"situation","then":"response"}
 {"type":"swap_exercise","routine":"routine id","index": exercise index,"to":"exercise id from its alternatives"}
 {"type":"task","title":"a concrete to-do","due":"yyyy-mm-dd or omit"}
 {"type":"aid","feeling":"a feeling from their aid kit (or a new one)","action":"what helps"}
Only propose swaps using the exact ids listed as alternatives.

You also see the rest of their day in the app: the daily lesson, food and calories, the workout, quests, tasks, and social-media time. For this user, heavy scrolling and eating over target usually mean a low mood — notice it gently, connect it, and ask. Their aid kit lists what they wrote helps for each feeling, with how often it actually helped: suggest the ones that work.
''';

  /// Your data, compact: the habit, recent days, reasons, what the System
  /// already understands, your life, and the workout if linked.
  static String context({
    required Habit habit,
    required List<CheckIn> checks,
    required HabitUnderstanding understanding,
    required LifeContext life,
    required List<CoachNote> notes,
    required Set<String> hardDays,
    List<AutomaticityCheck> weekly = const [],
    WorkoutContext? workout,
    String acrossApp = '',
    List<HabitTask> tasks = const [],
    List<AidEntry> aidKit = const [],
    ({int helped, int rated}) Function(String actionId)? aidScore,
    HabitUnderstanding? dayPattern,
    List<CoachNote> dayNotes = const [],
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final byDay = {for (final c in checks) c.day: c};
    final b = StringBuffer()
      ..writeln('TODAY: ${habitDay(today)} (weekday ${today.weekday})')
      ..writeln('HABIT: ${habit.name}')
      ..writeln('  full: ${habit.full}')
      ..writeln('  tiny: ${habit.tiny}')
      ..writeln('  anchor: after ${habit.anchor}')
      ..writeln('  days: ${(habit.weekdays.toList()..sort()).join(',')}')
      ..writeln(
        '  reminder: ${habit.reminderMinutes == null ? 'none' : _time(habit.reminderMinutes!)}',
      );
    if (habit.identity.isNotEmpty) b.writeln('  identity: ${habit.identity}');
    if (habit.outcome.isNotEmpty) b.writeln('  why: ${habit.outcome}');
    for (final o in habit.obstacles) {
      b.writeln('  if ${o.when} -> ${o.then}');
    }
    b.writeln('  started ${today.difference(habit.createdAt).inDays} days ago');

    // The last 28 due days: ✓ full, ½ tiny, ✗ missed (reason), ~ excused.
    final days = HabitAnalysis.dueDays(
      habit,
      today.subtract(const Duration(days: 40)),
      today,
    ).take(28);
    b.writeln('LAST DAYS (newest first):');
    for (final d in days) {
      final key = habitDay(d);
      final c = byDay[key];
      final mark = switch (c?.status) {
        CheckStatus.full => '✓',
        CheckStatus.tiny => '½',
        CheckStatus.missed => '✗',
        CheckStatus.excused => '~',
        null => hardDays.contains(key) ? '~' : '?',
      };
      final extra = [
        if (c?.reason != null) c!.reason!.name,
        if (c?.mood != null) 'mood ${c!.mood}/5',
        if (c != null && c.note.isNotEmpty) '"${_clip(c.note, 80)}"',
      ].join(', ');
      b.writeln('  $key $mark${extra.isEmpty ? '' : ' ($extra)'}');
    }
    final reasons = HabitAnalysis.reasons(checks);
    if (reasons.isNotEmpty) {
      b.writeln(
        'REASONS SO FAR: ${reasons.map((r) => '${r.$1.name}×${r.$2}').join(', ')}',
      );
    }
    final rate = HabitAnalysis.rate(checks);
    if (rate != null) {
      b.writeln('DONE RATE (30 days): ${(rate * 100).round()}%');
    }
    if (weekly.isNotEmpty) {
      b.writeln(
        'AUTOMATICITY (1-7, weekly): ${weekly.map((w) => w.average.toStringAsFixed(1)).join(' → ')}',
      );
    }

    b.writeln('WHAT YOU UNDERSTAND SO FAR:');
    if (understanding.isEmpty) {
      b.writeln('  (nothing yet)');
    } else {
      b
        ..writeln('  root cause: ${understanding.rootCause}')
        ..writeln('  evidence: ${understanding.evidence}')
        ..writeln('  helps: ${understanding.helps}')
        ..writeln('  fails: ${understanding.fails}')
        ..writeln('  confidence: ${understanding.confidence}');
    }
    if (notes.isNotEmpty) {
      b.writeln('PAST TALKS (newest first):');
      for (final n in notes.take(6)) {
        b.writeln(
          '  ${habitDay(n.date)}: ${_clip(n.insight, 140)}'
          '${n.changes.isEmpty ? '' : ' | changed: ${n.changes.join('; ')}'}',
        );
      }
    }
    b.writeln(
      'LIFE CONTEXT: ${life.summary.isEmpty ? '(not told yet)' : life.summary}',
    );
    if (acrossApp.isNotEmpty) b.write(acrossApp);
    if (dayPattern != null && !dayPattern.isEmpty) {
      b.writeln(
        'THEIR DOWN-DAY PATTERN (from day talks): ${dayPattern.rootCause}'
        '${dayPattern.helps.isEmpty ? '' : '; helps: ${dayPattern.helps}'}',
      );
    }
    for (final n in dayNotes.take(3)) {
      b.writeln('RECENT DAY ${habitDay(n.date)}: ${_clip(n.insight, 140)}');
    }
    final open = tasks.where((t) => !t.done).take(10).toList();
    if (open.isNotEmpty) {
      b.writeln('OPEN TASKS:');
      for (final t in open) {
        b.writeln(
          '  - ${_clip(t.title, 80)}${t.due == null ? '' : ' (due ${t.due})'}',
        );
      }
    }
    if (aidKit.isNotEmpty) {
      b.writeln('AID KIT (their own remedies):');
      for (final e in aidKit) {
        final actions = [
          for (final a in e.actions)
            switch (aidScore?.call(a.id)) {
              final s? when s.rated > 0 =>
                '${_clip(a.text, 50)} (helped ${s.helped}/${s.rated})',
              _ => _clip(a.text, 50),
            },
        ];
        b.writeln(
          '  ${e.feeling}: ${actions.isEmpty ? '(nothing yet)' : actions.join('; ')}',
        );
      }
    }

    if (workout != null) {
      b.writeln(
        'WORKOUT LINKED: routine "${workout.routineName}" (id ${workout.routineId})',
      );
      for (final e in workout.exercises) {
        b.writeln(
          '  #${e.index} ${e.name} [${e.id}] ${e.target}'
          '${e.sessions > 0 ? ' — skipped in ${e.skipped} of last ${e.sessions} sessions' : ''}',
        );
        if (e.alternatives.isNotEmpty) {
          b.writeln(
            '     alternatives: ${e.alternatives.map((a) => '${a.name} [${a.id}]').join('; ')}',
          );
        }
      }
    }
    return b.toString();
  }

  static const _dayMode = '''

THIS TALK IS ABOUT THE WHOLE DAY, not one quest. Look at everything (scrolling, food, workout, lesson, quests, mood, what they tell you). Find what's behind the day — an event, a feeling, tiredness — and how the parts connect (e.g. low mood → scrolling → eating → skipping). In "understanding", describe their general down-day pattern across days (root = what usually starts it, helps = what gets them out). Allowed changes here: task and aid only.''';

  /// Everything about today and recent days, for a whole-day talk.
  static String dayContext({
    required String acrossApp,
    required List<DaySnapshot> days,
    required List<DayPattern> patterns,
    required HabitUnderstanding understanding,
    required LifeContext life,
    required List<CoachNote> notes,
    required List<({String name, String? today, String rootCause})> quests,
    List<HabitTask> tasks = const [],
    List<AidEntry> aidKit = const [],
    ({int helped, int rated}) Function(String actionId)? aidScore,
  }) {
    final b = StringBuffer()..write(acrossApp);
    final usual = DayPatterns.usualSocial(days);
    b.writeln('RECENT DAYS (newest first):');
    for (final d in days.take(10)) {
      b.writeln(
        '  ${d.day}: social ${d.socialMinutes ?? '?'} min, food ${d.kcal}'
        '${d.kcalTarget == null ? '' : '/${d.kcalTarget}'} kcal, workout '
        '${d.workoutPlanned ? (d.workoutDone ? 'done' : 'skipped') : 'rest'}, '
        'lesson ${d.lessonRead ? 'read' : 'no'}, quests ${d.questsDone}/${d.questsDue}'
        '${d.mood == null ? '' : ', mood ${d.mood!.toStringAsFixed(1)}'}'
        '${d.hard ? ', hard day' : ''}',
      );
    }
    if (usual != null) b.writeln('USUAL SOCIAL MEDIA: ~$usual min/day');
    for (final p in patterns) {
      b.writeln(
        'PATTERN: ${p.text}: ${(p.onHeavy * 100).round()}% on heavy-scrolling days vs ${(p.onNormal * 100).round()}% otherwise',
      );
    }
    b.writeln('QUESTS:');
    for (final q in quests) {
      b.writeln(
        '  ${q.name}: today ${q.today ?? 'not answered'}'
        '${q.rootCause.isEmpty ? '' : '; known blocker: ${q.rootCause}'}',
      );
    }
    b.writeln('DOWN-DAY PATTERN SO FAR:');
    b.writeln(
      understanding.isEmpty
          ? '  (nothing yet)'
          : '  root: ${understanding.rootCause}\n  evidence: ${understanding.evidence}\n  helps: ${understanding.helps}\n  fails: ${understanding.fails}\n  confidence: ${understanding.confidence}',
    );
    for (final n in notes.take(6)) {
      b.writeln('PAST DAY ${habitDay(n.date)}: ${_clip(n.insight, 140)}');
    }
    b.writeln(
      'LIFE CONTEXT: ${life.summary.isEmpty ? '(not told yet)' : life.summary}',
    );
    final open = tasks.where((t) => !t.done).take(8);
    if (open.isNotEmpty) {
      b.writeln(
        'OPEN TASKS: ${open.map((t) => _clip(t.title, 50)).join('; ')}',
      );
    }
    for (final e in aidKit) {
      b.writeln(
        'AID KIT ${e.feeling}: ${e.actions.map((a) {
          final s = aidScore?.call(a.id);
          return s == null || s.rated == 0 ? a.text : '${a.text} (helped ${s.helped}/${s.rated})';
        }).join('; ')}',
      );
    }
    return b.toString();
  }

  /// A short weekly reflection and one experiment for next week.
  Future<WeeklyReview> weeklyReview({
    required String context,
    required bool arabic,
  }) async {
    final text = await _gemini.generate(
      system: '''$_system
Now write the WEEKLY REVIEW instead of a talk: in under 180 words, in Markdown with short headings: what went well (be specific), what got in the way and the pattern behind it (connect scrolling, food, mood, quests), and one small EXPERIMENT for next week that fits their real life. End with a JSON block: {"experiment": "the experiment in one sentence"}.
${arabic ? 'Write in Arabic.' : 'Write in English.'}''',
      messages: [(fromUser: true, text: 'THE WEEK (from the app):\n$context')],
      temperature: 0.5,
    );
    final m = RegExp(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```').firstMatch(text);
    var experiment = '';
    var visible = text;
    if (m != null) {
      visible = text.replaceRange(m.start, m.end, '').trim();
      try {
        experiment = '${(jsonDecode(m.group(1)!) as Map)['experiment'] ?? ''}'
            .trim();
      } catch (_) {}
    }
    return WeeklyReview(
      date: DateTime.now(),
      text: visible,
      experiment: experiment,
    );
  }

  /// One step of the talk. [talk] is the conversation so far (the user's
  /// latest message last). [aboutDay]: a whole-day talk.
  Future<CoachReply> reply({
    required String context,
    required List<CoachMessage> talk,
    required bool arabic,
    bool aboutDay = false,
  }) async {
    final answers = talk.where((m) => m.fromUser).length;
    final conclude = answers >= maxTurns
        ? '\nThis is the last message: conclude now, with the JSON block.'
        : answers >= 2
        ? '\nIf you understand enough, conclude now with the JSON block.'
        : '';
    final language = arabic
        ? 'Reply in Arabic (clear Modern Standard Arabic). JSON keys stay in English; JSON values in Arabic.'
        : 'Reply in English unless the user writes in another language.';
    final messages = <AiMessage>[
      (
        fromUser: true,
        text: 'CONTEXT (from the app, not written by the user):\n$context',
      ),
      (fromUser: false, text: 'Understood. I have the context.'),
      for (final m in talk) (fromUser: m.fromUser, text: m.text),
    ];
    final text = await _gemini.generate(
      system: '$_system${aboutDay ? _dayMode : ''}\n$language$conclude',
      messages: messages,
      temperature: 0.5,
    );
    return parse(text);
  }

  /// Splits the visible message from the JSON proposal.
  static CoachReply parse(String text) {
    final fence = RegExp(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```');
    var match = fence.firstMatch(text);
    String? json = match?.group(1);
    var visible = match == null
        ? text
        : text.replaceRange(match.start, match.end, '');
    if (json == null) {
      // A bare JSON object at the end.
      final start = text.lastIndexOf('{"insight"');
      if (start >= 0) {
        json = text.substring(start);
        visible = text.substring(0, start);
      }
    }
    CoachProposal? proposal;
    if (json != null) {
      try {
        final j = jsonDecode(json) as Map<String, dynamic>;
        final u = (j['understanding'] as Map?) ?? const {};
        proposal = CoachProposal(
          insight: '${j['insight'] ?? ''}'.trim(),
          understanding: HabitUnderstanding(
            rootCause: '${u['root'] ?? ''}'.trim(),
            evidence: '${u['evidence'] ?? ''}'.trim(),
            helps: '${u['helps'] ?? ''}'.trim(),
            fails: '${u['fails'] ?? ''}'.trim(),
            confidence: (u['confidence'] as num?)?.round().clamp(0, 100) ?? 0,
            updatedAt: DateTime.now(),
          ),
          life: switch ('${j['life'] ?? ''}'.trim()) {
            '' => null,
            final s => s,
          },
          changes: [
            for (final c in (j['changes'] as List?) ?? const [])
              ?CoachChange.fromJson(c),
          ],
          next: '${j['next'] ?? ''}'.trim(),
        );
      } catch (_) {
        proposal = null;
      }
    }
    return (text: visible.trim(), proposal: proposal);
  }

  static String _time(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  static String _clip(String s, int n) =>
      s.length <= n ? s : '${s.substring(0, n)}…';
}
