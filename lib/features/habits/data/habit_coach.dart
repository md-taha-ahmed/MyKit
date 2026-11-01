import 'dart:convert';

import '../../../core/ai/gemini_client.dart';
import '../domain/habit_analysis.dart';
import '../domain/habit_models.dart';

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
Only propose swaps using the exact ids listed as alternatives.
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

  /// One step of the talk. [talk] is the conversation so far (the user's
  /// latest message last).
  Future<CoachReply> reply({
    required String context,
    required List<CoachMessage> talk,
    required bool arabic,
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
      system: '$_system\n$language$conclude',
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
