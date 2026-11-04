import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/story_models.dart';
import '../../rise_fall_routes.dart';
import '../providers/rise_fall_providers.dart';

/// The problems that repeat across countries.
class PatternsScreen extends ConsumerWidget {
  const PatternsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(storiesProvider).value ?? const <StoryCountry>[];
    int count(StoryPattern t) => {
      for (final c in all)
        if (c.parts.any((p) => p.patterns.contains(t))) c.id,
    }.length;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الأنماط')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 4, 8, 10),
              child: Text(
                'مشكلة واحدة في دول مختلفة: كيف تعامل معها كل بلد، ومن فشل.',
                style: TextStyle(color: Colors.white70, height: 1.5),
              ),
            ),
            for (final t in StoryPattern.values)
              ListTile(
                title: Text(t.label),
                subtitle: Text('في ${count(t)} دول'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => context.push(RiseFallRoutes.pattern(t.name)),
              ),
          ],
        ),
      ),
    );
  }
}

class PatternScreen extends ConsumerWidget {
  const PatternScreen({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pattern = StoryPattern.values.byName(name);
    final all = ref.watch(storiesProvider).value ?? const <StoryCountry>[];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(pattern.label)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
          children: [
            for (final c in all)
              if (c.parts.where((p) => p.patterns.contains(pattern)).toList()
                  case final parts when parts.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 14, 8, 2),
                  child: Text(
                    c.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                for (final p in parts) _PartTile(country: c, part: p),
              ],
          ],
        ),
      ),
    );
  }
}

class _PartTile extends StatelessWidget {
  const _PartTile({required this.country, required this.part});

  final StoryCountry country;
  final StoryPart part;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    leading: Icon(Icons.circle, size: 12, color: moodColors[part.mood]),
    minLeadingWidth: 12,
    title: Text(
      '${part.title} (${part.period})',
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    ),
    subtitle: Text(part.oneLine, style: const TextStyle(height: 1.5)),
    onTap: () => context.push(RiseFallRoutes.part(country.id, part.index)),
  );
}

/// Two countries side by side, by the problems they share.
class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({super.key});

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  String _a = 'germany';
  String _b = 'yemen';

  Widget _picker(
    List<StoryCountry> all,
    String value,
    ValueChanged<String> on,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    items: [
      for (final c in all) DropdownMenuItem(value: c.id, child: Text(c.name)),
    ],
    onChanged: (v) {
      if (v != null) on(v);
    },
  );

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(storiesProvider).value ?? const <StoryCountry>[];
    final a = all.where((c) => c.id == _a).firstOrNull;
    final b = all.where((c) => c.id == _b).firstOrNull;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('قارن دولتين')),
        body: a == null || b == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: _picker(
                            all,
                            _a,
                            (v) => setState(() => _a = v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _picker(
                            all,
                            _b,
                            (v) => setState(() => _b = v),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final t in StoryPattern.values)
                    if (a.parts.any((p) => p.patterns.contains(t)) &&
                        b.parts.any((p) => p.patterns.contains(t))) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 18, 8, 2),
                        child: Text(
                          t.label,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      for (final c in [a, b]) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                          child: Text(
                            c.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        for (final p in c.parts.where(
                          (p) => p.patterns.contains(t),
                        ))
                          _PartTile(country: c, part: p),
                      ],
                    ],
                ],
              ),
      ),
    );
  }
}
