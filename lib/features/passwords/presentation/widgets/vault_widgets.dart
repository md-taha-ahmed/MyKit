import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/services/password_tools.dart';
import '../providers/vault_providers.dart';

/// Blocks screenshots, screen recording and the recent-apps preview while
/// any Passwords screen is showing.
class SecureScope extends ConsumerStatefulWidget {
  const SecureScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SecureScope> createState() => _SecureScopeState();
}

class _SecureScopeState extends ConsumerState<SecureScope> {
  static int _open = 0;

  @override
  void initState() {
    super.initState();
    if (_open++ == 0) ref.read(vaultNativeProvider).setSecure(true);
  }

  @override
  void dispose() {
    if (--_open == 0) ref.read(vaultNativeProvider).setSecure(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Coloured bar + label for a password's strength.
class StrengthMeter extends StatelessWidget {
  const StrengthMeter(this.password, {super.key});

  final String password;

  static Color colorOf(PasswordStrength s) => switch (s) {
    PasswordStrength.veryWeak => const Color(0xFFE5484D),
    PasswordStrength.weak => const Color(0xFFE5784D),
    PasswordStrength.fair => const Color(0xFFE5A93A),
    PasswordStrength.strong => const Color(0xFF4CC38A),
    PasswordStrength.veryStrong => const Color(0xFF34C759),
  };

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    final s = strengthOf(password);
    final color = colorOf(s);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (s.index + 1) / PasswordStrength.values.length,
                color: color,
                backgroundColor: Colors.white10,
                minHeight: 5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(s.label, style: TextStyle(fontSize: 12.5, color: color)),
        ],
      ),
    );
  }
}

/// Bottom sheet that generates a password. Returns it when "Use" is tapped.
Future<String?> showPasswordGenerator(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _GeneratorSheet(),
    );

class _GeneratorSheet extends StatefulWidget {
  const _GeneratorSheet();

  @override
  State<_GeneratorSheet> createState() => _GeneratorSheetState();
}

class _GeneratorSheetState extends State<_GeneratorSheet> {
  var _options = const GeneratorOptions();
  late String _password = generatePassword(_options);

  void _update(GeneratorOptions o) => setState(() {
    _options = o;
    _password = generatePassword(o);
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('Generate password'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    _password,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 17,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tr('New one'),
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _update(_options),
                ),
              ],
            ),
          ),
          StrengthMeter(_password),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(tr('Length')),
              Expanded(
                child: Slider(
                  value: _options.length.toDouble(),
                  min: 8,
                  max: 64,
                  divisions: 56,
                  label: '${_options.length}',
                  onChanged: (v) =>
                      _update(_options.copyWith(length: v.round())),
                ),
              ),
              SizedBox(width: 28, child: Text('${_options.length}')),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilterChip(
                label: Text(tr('A–Z')),
                selected: _options.upper,
                onSelected: (v) => _update(_options.copyWith(upper: v)),
              ),
              FilterChip(
                label: Text(tr('a–z')),
                selected: _options.lower,
                onSelected: (v) => _update(_options.copyWith(lower: v)),
              ),
              FilterChip(
                label: const Text('0–9'),
                selected: _options.digits,
                onSelected: (v) => _update(_options.copyWith(digits: v)),
              ),
              FilterChip(
                label: const Text('!@#'),
                selected: _options.symbols,
                onSelected: (v) => _update(_options.copyWith(symbols: v)),
              ),
              FilterChip(
                label: Text(tr('No look-alikes')),
                selected: _options.avoidAmbiguous,
                onSelected: (v) =>
                    _update(_options.copyWith(avoidAmbiguous: v)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context, _password),
            child: Text(tr('Use this password')),
          ),
        ],
      ),
    );
  }
}

/// Letter avatar for an entry (first letter of the site or title).
class EntryAvatar extends StatelessWidget {
  const EntryAvatar({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final letter = label.isEmpty ? '?' : label.characters.first.toUpperCase();
    final hue = (label.toLowerCase().hashCode % 360).abs().toDouble();
    final color = HSLColor.fromAHSL(1, hue, 0.45, 0.45).toColor();
    return CircleAvatar(
      radius: 20,
      backgroundColor: color.withValues(alpha: 0.25),
      child: Text(
        letter,
        style: TextStyle(
          color: HSLColor.fromAHSL(1, hue, 0.7, 0.75).toColor(),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
