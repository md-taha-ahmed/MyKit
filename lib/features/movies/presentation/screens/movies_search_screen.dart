import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n.dart';
import '../../domain/entities/stremio_entities.dart';
import '../providers/movies_providers.dart';
import '../widgets/movies_widgets.dart';

/// Searches movies and series in every add-on with a searchable catalog.
class MoviesSearchScreen extends ConsumerStatefulWidget {
  const MoviesSearchScreen({super.key});

  @override
  ConsumerState<MoviesSearchScreen> createState() => _MoviesSearchScreenState();
}

class _MoviesSearchScreenState extends ConsumerState<MoviesSearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: tr('Title, or IMDb link / id'),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
          onSubmitted: (v) => setState(() => _query = v.trim()),
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: _query.isEmpty
          ? MessageView(
              icon: Icons.search,
              title: tr('Find something to watch'),
              message: tr(
                'Type a title and press search. You can also paste an IMDb link.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                for (final t in MediaType.values)
                  _ResultsRow(type: t, query: _query),
              ],
            ),
    );
  }
}

class _ResultsRow extends ConsumerWidget {
  const _ResultsRow({required this.type, required this.query});

  final MediaType type;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(
      searchResultsProvider((type: type, query: query)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(type.label),
        SizedBox(
          height: 228,
          child: results.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (metas) => metas.isEmpty
                ? Center(
                    child: Text(
                      tr('No results'),
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: metas.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => PosterCard(meta: metas[i]),
                  ),
          ),
        ),
      ],
    );
  }
}
