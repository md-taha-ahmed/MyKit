import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n.dart';
import '../../../../core/storage/shared_preferences_provider.dart';

/// A tip: an icon and one sentence (an English key for [tr]).
typedef ToolTip = ({IconData icon, String text});

/// How each tool works, shown once the first time it's opened.
const toolTips = <String, List<ToolTip>>{
  'countdown': [
    (
      icon: Icons.add,
      text:
          'Tap + to count down to a date, a number of days or an event from your calendar.',
    ),
    (
      icon: Icons.widgets_outlined,
      text:
          'Add a countdown to your home screen as a widget: long-press the home screen → Widgets → MyKit.',
    ),
    (
      icon: Icons.palette_outlined,
      text:
          'Open a countdown to change its colours, font and how the ring fills up.',
    ),
  ],
  'rss': [
    (
      icon: Icons.add,
      text:
          'Add a site by pasting its address — MyKit finds its feed. YouTube channels work too.',
    ),
    (
      icon: Icons.folder_outlined,
      text: 'Sort feeds into categories and folders from the menu (☰).',
    ),
    (
      icon: Icons.swipe,
      text:
          'Swipe an article right to save it. The brief view lets you swipe through articles one by one.',
    ),
    (
      icon: Icons.auto_awesome_outlined,
      text:
          'In an article, Summarize gives the gist and Ask lets you chat about it (needs a free Gemini key).',
    ),
  ],
  'music': [
    (
      icon: Icons.folder_outlined,
      text: 'Your songs are grouped by the folders they\'re in on the phone.',
    ),
    (
      icon: Icons.shuffle,
      text:
          'Tap a song to play, or shuffle a whole folder. Music keeps playing with the screen off.',
    ),
    (icon: Icons.refresh, text: 'Added new songs? Tap Rescan device.'),
  ],
  'books': [
    (icon: Icons.add, text: 'Import PDFs with + and keep them on shelves.'),
    (
      icon: Icons.bookmark_border,
      text:
          'MyKit remembers your page. Bookmark pages while reading and add notes.',
    ),
    (
      icon: Icons.contrast,
      text: 'Tap Aa while reading for dark or sepia pages and scrolling style.',
    ),
  ],
  'manga': [
    (
      icon: Icons.extension_outlined,
      text:
          'First install a source from the Extensions tab (check the language filter).',
    ),
    (
      icon: Icons.explore_outlined,
      text:
          'Find titles in Browse, then add them to your Library to follow new chapters and episodes.',
    ),
    (
      icon: Icons.history,
      text: 'Your reading and watching progress is saved automatically.',
    ),
  ],
  'movies': [
    (
      icon: Icons.extension_outlined,
      text:
          'Streams come from Stremio add-ons. Cinemeta, Torrentio and OpenSubtitles are set up for you.',
    ),
    (
      icon: Icons.search,
      text:
          'Search for a title, pick an episode, then choose a stream — the ones with more 👤 start faster.',
    ),
    (
      icon: Icons.wifi,
      text:
          'Torrent streams need a good connection; mobile data or battery saving can make them slow.',
    ),
  ],
  'fitness': [
    (
      icon: Icons.today_outlined,
      text:
          'Today shows the workout planned for today. Tap Workout to start it.',
    ),
    (
      icon: Icons.event_note_outlined,
      text:
          'Plan your workouts and training days in Plan; the exercise library has instructions for each move.',
    ),
    (
      icon: Icons.show_chart,
      text: 'Log your weight in Progress to see your trend and personal bests.',
    ),
    (
      icon: Icons.restaurant_outlined,
      text:
          'Log food in the Food tab: by photo, by describing it, or by hand. Your target comes from your weight and height.',
    ),
  ],
  'passwords': [
    (
      icon: Icons.lock_outline,
      text:
          'Your master password encrypts the vault. Nobody can recover it, so remember it well.',
    ),
    (
      icon: Icons.fingerprint,
      text:
          'Turn on fingerprint unlock so you don\'t type the master password every time.',
    ),
    (
      icon: Icons.password,
      text:
          'Choose MyKit as the autofill service to fill logins in apps and Chrome. Import a CSV from Settings.',
    ),
  ],
  'screen-time': [
    (
      icon: Icons.accessibility_new,
      text:
          'Turn on "MyKit Screen time" in Accessibility first — that\'s how it counts time.',
    ),
    (
      icon: Icons.timer_outlined,
      text:
          'Tap a platform to change its daily limit. Apps, Lite apps and websites share one limit.',
    ),
    (
      icon: Icons.bedtime_outlined,
      text:
          'Add focus hours to block apps completely at set times, like at night.',
    ),
  ],
  'habits': [
    (
      icon: Icons.flag_outlined,
      text:
          'Each habit is a daily quest with a full and a tiny version. On bad days the tiny one is enough.',
    ),
    (
      icon: Icons.shield_outlined,
      text:
          'Hard day (no power, travel, security…)? Turn on Hard day: misses are excused and only tiny versions count.',
    ),
    (
      icon: Icons.forum_outlined,
      text:
          'Missed a quest? Tell the System why. It looks at your history, finds the real reason and adjusts the quest with you.',
    ),
    (
      icon: Icons.speed,
      text:
          'Once a week, rate how automatic the habit feels. That — not streaks — is your rank, from E to S.',
    ),
  ],
  'knowledge': [
    (
      icon: Icons.menu_book_outlined,
      text:
          'A new lesson every day from the original books, with its exact reference.',
    ),
    (
      icon: Icons.lightbulb_outline,
      text:
          'Tap "اشرح لي" (explain) under a lesson for word meanings and review questions.',
    ),
    (
      icon: Icons.library_books_outlined,
      text:
          'Read ahead in the Library, and follow sites and channels in Sources.',
    ),
  ],
};

/// Shows a tool's tips the first time its screen opens.
class ToolTipsGate extends ConsumerStatefulWidget {
  const ToolTipsGate({super.key, required this.toolId, required this.child});

  final String toolId;
  final Widget child;

  static String _key(String toolId) => 'tips.seen.$toolId';

  /// Shows every tool's tips again (Settings).
  static Future<void> resetAll(WidgetRef ref) async {
    final prefs = ref.read(sharedPreferencesProvider);
    for (final id in toolTips.keys) {
      await prefs.remove(_key(id));
    }
  }

  @override
  ConsumerState<ToolTipsGate> createState() => _ToolTipsGateState();
}

class _ToolTipsGateState extends ConsumerState<ToolTipsGate> {
  @override
  void initState() {
    super.initState();
    final tips = toolTips[widget.toolId];
    final prefs = ref.read(sharedPreferencesProvider);
    final key = ToolTipsGate._key(widget.toolId);
    if (tips == null || (prefs.getBool(key) ?? false)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await prefs.setBool(key, true);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => _TipsSheet(tips: tips),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _TipsSheet extends StatelessWidget {
  const _TipsSheet({required this.tips});

  final List<ToolTip> tips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Quick tips'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 14),
            for (final tip in tips)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(tip.icon, color: theme.colorScheme.primary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        tr(tip.text),
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Got it')),
            ),
          ],
        ),
      ),
    );
  }
}
