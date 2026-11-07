import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/i18n.dart';
import '../../data/datasources/open_subtitles_client.dart';
import '../../domain/entities/stremio_entities.dart';
import '../providers/movies_providers.dart';

/// What's playing, so the search can start without typing.
class SubtitleSearchRequest {
  const SubtitleSearchRequest({
    required this.metaId,
    required this.videoId,
    required this.name,
    required this.seriesLike,
    this.episodeLabel,
  });

  final String metaId;
  final String videoId;
  final String name;

  /// Anime and shows look for a show first; films for a film.
  final bool seriesLike;
  final String? episodeLabel;
}

Future<SubtitleInfo?> showSubtitleSearchSheet(
  BuildContext context,
  SubtitleSearchRequest request,
) => showModalBottomSheet<SubtitleInfo>(
  context: context,
  isScrollControlled: true,
  backgroundColor: const Color(0xF0141418),
  builder: (_) => _SubtitleSearchSheet(request: request),
);

class _SubtitleSearchSheet extends ConsumerStatefulWidget {
  const _SubtitleSearchSheet({required this.request});

  final SubtitleSearchRequest request;

  @override
  ConsumerState<_SubtitleSearchSheet> createState() =>
      _SubtitleSearchSheetState();
}

class _SubtitleSearchSheetState extends ConsumerState<_SubtitleSearchSheet> {
  late final _query = TextEditingController(text: widget.request.name);
  final _season = TextEditingController(text: '1');
  final _episode = TextEditingController(text: '1');

  OpenSubtitlesClient get _client => ref.read(openSubtitlesClientProvider);

  SubtitleTitle? _title;
  List<SubtitleTitle>? _titles;
  List<SubtitleInfo>? _results;
  String? _language;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final request = widget.request;
    final fromId = parseImdbVideoId(request.videoId);
    final known = ref
        .read(moviesRepositoryProvider)
        .getSubtitleTitle(request.metaId);
    _season.text = '${fromId?.season ?? 1}';
    _episode.text =
        '${fromId?.episode ?? episodeNumberFromLabel(request.episodeLabel) ?? 1}';
    if (fromId != null) {
      _useTitle(
        SubtitleTitle(
          imdbId: fromId.imdbId,
          name: request.name,
          isSeries: fromId.isSeries,
        ),
      );
    } else if (known != null) {
      _useTitle(known);
    } else {
      _searchTitles();
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _season.dispose();
    _episode.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() request) async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      await request();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _searchTitles() => _run(() async {
    final titles = await _client.searchTitles(
      _query.text,
      seriesFirst: widget.request.seriesLike,
    );
    if (mounted) setState(() => _titles = titles);
  });

  void _useTitle(SubtitleTitle title) {
    setState(() {
      _title = title;
      _results = null;
    });
    // So the next episode doesn't ask which show this is again.
    if (parseImdbVideoId(widget.request.videoId) == null) {
      ref
          .read(moviesRepositoryProvider)
          .saveSubtitleTitle(widget.request.metaId, title);
    }
    _searchSubtitles();
  }

  Future<void> _searchSubtitles() => _run(() async {
    final results = await _client.subtitles(
      _title!,
      season: int.tryParse(_season.text) ?? 1,
      episode: int.tryParse(_episode.text) ?? 1,
    );
    if (!mounted) return;
    final preferred = ref.read(subtitleLanguageProvider);
    final codes = results.map((s) => languageCode(s.lang)).toSet();
    setState(() {
      _results = results;
      _language = codes.contains(preferred)
          ? preferred
          : codes.isEmpty
          ? null
          : codes.first;
    });
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              ListTile(
                dense: true,
                title: Text(
                  tr('Search OpenSubtitles'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              ...(_title == null ? _titleStep() : _subtitleStep()),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: CircularProgressIndicator(color: moviesAccent),
                  ),
                ),
              if (_failed)
                _Note(
                  tr(
                    'Could not reach OpenSubtitles. Check your connection and try again.',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _titleStep() => [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
      child: TextField(
        controller: _query,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _searchTitles(),
        decoration: InputDecoration(
          isDense: true,
          hintText: tr('Search by title'),
          suffixIcon: IconButton(
            tooltip: tr('Search'),
            icon: const Icon(Icons.search),
            onPressed: _searchTitles,
          ),
        ),
      ),
    ),
    if (!_loading && !_failed && (_titles?.isEmpty ?? false))
      _Note(tr('No titles found. Try the English name.')),
    for (final t in _titles ?? const <SubtitleTitle>[])
      ListTile(
        dense: true,
        title: Text(t.name),
        subtitle: Text(
          [t.isSeries ? tr('Series') : tr('Movie'), ?t.year].join(' · '),
        ),
        onTap: () => _useTitle(t),
      ),
  ];

  List<Widget> _subtitleStep() {
    final title = _title!;
    final results = _results;
    final preferred = ref.read(subtitleLanguageProvider);
    final codes = {for (final s in results ?? []) languageCode(s.lang)}.toList()
      ..sort((a, b) {
        if (a == preferred) return -1;
        if (b == preferred) return 1;
        return (languageNames[a] ?? a).compareTo(languageNames[b] ?? b);
      });
    return [
      ListTile(
        dense: true,
        title: Text(title.name),
        trailing: TextButton(
          onPressed: () {
            setState(() {
              _title = null;
              _results = null;
              _failed = false;
            });
            if (_titles == null) _searchTitles();
          },
          child: Text(tr('Change title')),
        ),
      ),
      if (title.isSeries)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(child: _NumberField(_season, tr('Season'))),
              const SizedBox(width: 12),
              Expanded(child: _NumberField(_episode, tr('Episode'))),
              IconButton(
                tooltip: tr('Search'),
                icon: const Icon(Icons.search),
                onPressed: _searchSubtitles,
              ),
            ],
          ),
        ),
      if (codes.isNotEmpty)
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final l in codes)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(languageNames[l] ?? l),
                    selected: l == _language,
                    selectedColor: moviesAccent.withValues(alpha: 0.35),
                    onSelected: (_) {
                      ref.read(subtitleLanguageProvider.notifier).set(l);
                      setState(() => _language = l);
                    },
                  ),
                ),
            ],
          ),
        ),
      if (!_loading && !_failed && (results?.isEmpty ?? false))
        _Note(tr('No subtitles found. Check the season and episode.')),
      for (final s in results ?? const <SubtitleInfo>[])
        if (languageCode(s.lang) == _language)
          ListTile(
            dense: true,
            title: Text(s.fileName ?? s.languageName),
            onTap: () => Navigator.pop(context, s),
          ),
    ];
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField(this.controller, this.label);

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(isDense: true, labelText: label),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Text(text, style: const TextStyle(color: Colors.white60)),
  );
}
