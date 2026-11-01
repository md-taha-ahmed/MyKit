import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/i18n/i18n.dart';
import '../../setup_routes.dart';
import 'settings_screen.dart';

/// A short tour on a fresh install, then the setup checklist.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _pages = PageController();
  var _page = 0;

  static const _count = 4;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _count - 1) {
      context.go(SetupRoutes.firstRun);
    } else {
      _pages.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = [
      _Page(
        icon: Icons.waving_hand_outlined,
        title: tr('Welcome to MyKit'),
        text: tr(
          'Your everyday tools in one app: news feeds, music, books, passwords, workouts, screen time and more.',
        ),
        extra: Column(
          children: [
            const SizedBox(height: 28),
            Text(tr('Language'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            const LanguagePicker(),
          ],
        ),
      ),
      _Page(
        icon: Icons.grid_view_rounded,
        title: tr('One tile per tool'),
        text: tr(
          'Tap a tile on the home screen to open its tool. The line under its name tells you what\'s new: unread articles, today\'s workout, time used…',
        ),
      ),
      _Page(
        icon: Icons.cloud_done_outlined,
        title: tr('Your data stays yours'),
        text: tr(
          'Everything is kept on this phone. Turn on Google Drive backup and you can restore it all on a new phone, passwords included (encrypted).',
        ),
      ),
      _Page(
        icon: Icons.lightbulb_outline,
        title: tr('Help when you need it'),
        text: tr(
          'The first time you open a tool, a few tips show how it works. Settings (⚙ on the home screen) has the language, the setup checklist and backup.',
        ),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => context.go(SetupRoutes.firstRun),
                child: Text(tr('Skip')),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: pages,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _count; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(
                    _page == _count - 1 ? tr('Set up MyKit') : tr('Next'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.icon,
    required this.title,
    required this.text,
    this.extra,
  });

  final IconData icon;
  final String title;
  final String text;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          CircleAvatar(
            radius: 48,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
            child: Icon(icon, size: 48, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 28),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.55,
            ),
          ),
          ?extra,
        ],
      ),
    );
  }
}
