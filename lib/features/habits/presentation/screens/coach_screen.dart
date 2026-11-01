import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ai/gemini_client.dart';
import '../../../../core/ai/gemini_key_screen.dart';
import '../../../../core/i18n/i18n.dart';
import '../../../../core/widgets/simple_markdown.dart';
import '../../data/habit_coach.dart';
import '../../domain/habit_models.dart';
import '../providers/habit_providers.dart';
import '../widgets/habit_widgets.dart';

/// A talk with the System about one quest: it asks what happened, digs for
/// the real reason using your history, then proposes changes you accept
/// with a tap. Your messages are saved first, so nothing is lost offline.
class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key, required this.habitId});

  final String habitId;

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  var _waiting = false;
  String? _error;
  CoachProposal? _proposal;
  final _accepted = <int>{};

  HabitsNotifier get _notifier => ref.read(habitsProvider.notifier);

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final s = ref.read(habitsProvider);
      final habit = s.habit(widget.habitId);
      if (habit == null) return;
      final talk = s.talks[widget.habitId];
      if (talk == null || talk.isEmpty) {
        await _notifier.openTalk(widget.habitId, _opening(s, habit));
      } else if (talk.last.fromUser) {
        // Saved while offline: carry on now.
        await _run(_notifier.retry(widget.habitId));
      }
    });
  }

  /// The first question is local: no request until you answer.
  String _opening(HabitsState s, Habit habit) {
    final today = s.checksOf(habit.id)[habitDay(DateTime.now())];
    if (today?.status == CheckStatus.missed) {
      return tr(
        '[SYSTEM] Quest "{name}" was not completed today. You said: {reason}. Tell me what really happened — what was going on in your head when it was time?',
        {
          'name': habit.name,
          'reason': today?.reason == null ? '—' : reasonLabel(today!.reason!),
        },
      );
    }
    return tr(
      '[SYSTEM] Let\'s talk about "{name}". What feels hard about it right now?',
      {'name': habit.name},
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _waiting) return;
    _input.clear();
    await _run(_notifier.send(widget.habitId, text));
  }

  Future<void> _run(Future<CoachReply> request) async {
    setState(() {
      _waiting = true;
      _error = null;
    });
    _toEnd();
    try {
      final reply = await request;
      if (!mounted) return;
      setState(() {
        if (reply.proposal != null) {
          _proposal = reply.proposal;
          _accepted
            ..clear()
            ..addAll(List.generate(reply.proposal!.changes.length, (i) => i));
        }
      });
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _waiting = false);
      _toEnd();
    }
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });

  String _describe(CoachChange c) => switch (c.type) {
    'tiny' => tr('New tiny version: {text}', {'text': c.data['text'] ?? ''}),
    'full' => tr('New full version: {text}', {'text': c.data['text'] ?? ''}),
    'anchor' => tr('New anchor: after {text}', {'text': c.data['text'] ?? ''}),
    'time' => tr('Reminder at {time}', {
      'time': switch (c.data['minutes']) {
        final num m =>
          '${(m ~/ 60).toString().padLeft(2, '0')}:${(m.toInt() % 60).toString().padLeft(2, '0')}',
        _ => '?',
      },
    }),
    'days' => tr('Days: {days}', {
      'days': (c.data['weekdays'] as List?)?.join(', ') ?? '',
    }),
    'if_then' => tr('If {when}, then {then}', {
      'when': c.data['if'] ?? '',
      'then': c.data['then'] ?? '',
    }),
    'swap_exercise' => tr('Swap an exercise in your workout → {to}', {
      'to': '${c.data['to'] ?? ''}'.replaceAll('_', ' '),
    }),
    _ => c.type,
  };

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(habitsProvider);
    final habit = s.habit(widget.habitId);
    final talk = s.talks[widget.habitId] ?? const <CoachMessage>[];
    final configured = ref.watch(geminiClientProvider).isConfigured;
    final answered = talk.where((m) => m.fromUser).isNotEmpty;

    if (habit == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('The System')),
        actions: [
          if (talk.isNotEmpty)
            IconButton(
              tooltip: tr('End this talk'),
              onPressed: () async {
                await _notifier.closeTalk(widget.habitId);
                if (context.mounted) context.pop();
              },
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
              children: [
                for (final m in talk) _Bubble(m),
                if (!answered && !_waiting)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final quick in [
                          tr('I felt I can\'t do it'),
                          tr('I was afraid of failing'),
                          tr('I had no energy'),
                          tr('I forgot until it was too late'),
                          tr('Something happened around me'),
                        ])
                          ActionChip(
                            label: Text(quick),
                            onPressed: () {
                              _input.text = quick;
                              _input.selection = TextSelection.collapsed(
                                offset: quick.length,
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                if (_waiting)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                if (_error != null)
                  SystemPanel(
                    glow: Colors.orangeAccent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(_error!),
                        const SizedBox(height: 4),
                        Text(
                          tr(
                            'Your message is saved. The talk continues when you\'re back online.',
                          ),
                          style: const TextStyle(color: Colors.white60),
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: TextButton(
                            onPressed: () =>
                                _run(_notifier.retry(widget.habitId)),
                            child: Text(tr('Try again')),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_proposal != null) _proposalCard(_proposal!),
              ],
            ),
          ),
          if (!configured)
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: () => openGeminiKeySetup(context),
                icon: const Icon(Icons.key),
                label: Text(tr('Set up AI (free Gemini key) to talk')),
              ),
            )
          else if (_proposal == null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: tr('Tell the System…'),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _waiting ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _proposalCard(CoachProposal p) {
    final u = p.understanding;
    return SystemPanel(
      title: tr('[SYSTEM] ANALYSIS COMPLETE'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (p.insight.isNotEmpty)
            Text(
              p.insight,
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.45),
            ),
          if (u.rootCause.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              tr('Root cause'),
              style: const TextStyle(color: habitsAccent, fontSize: 12.5),
            ),
            Text(u.rootCause, style: const TextStyle(height: 1.45)),
            Text(
              tr('Confidence {n}%', {'n': u.confidence}),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          if (p.changes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              tr('Proposed changes'),
              style: const TextStyle(color: habitsAccent, fontSize: 12.5),
            ),
            for (final (i, c) in p.changes.indexed)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _accepted.contains(i),
                onChanged: (v) => setState(
                  () => v == true ? _accepted.add(i) : _accepted.remove(i),
                ),
                title: Text(_describe(c)),
              ),
          ],
          if (p.next.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              tr('Next quest'),
              style: const TextStyle(color: habitsAccent, fontSize: 12.5),
            ),
            Text(p.next, style: const TextStyle(height: 1.45)),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () async {
              await _notifier.applyProposal(widget.habitId, p, [
                for (final i in _accepted) p.changes[i],
              ]);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(tr('The System updated your quest.'))),
              );
              context.pop();
            },
            child: Text(
              _accepted.isEmpty ? tr('Keep the insight') : tr('Apply'),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _proposal = null),
            child: Text(tr('Keep talking')),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.m);

  final CoachMessage m;

  @override
  Widget build(BuildContext context) {
    final user = m.fromUser;
    return Align(
      alignment: user
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: user
                ? habitsAccent.withValues(alpha: 0.18)
                : const Color(0xFF0D1626),
            borderRadius: BorderRadius.circular(14),
            border: user
                ? null
                : Border.all(color: habitsAccent.withValues(alpha: 0.5)),
          ),
          child: user
              ? Text(m.text, style: const TextStyle(height: 1.45))
              : SimpleMarkdown(
                  m.text,
                  style: const TextStyle(height: 1.5, fontSize: 15),
                ),
        ),
      ),
    );
  }
}
