import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../../core/platform/external_apps.dart';
import '../../domain/entities/stremio_entities.dart';
import '../../domain/entities/torrent_stream_status.dart';
import '../../domain/repositories/movies_repository.dart';
import '../providers/movies_providers.dart';
import '../widgets/movies_widgets.dart';

/// What the player needs to play a source and remember progress.
class PlayerArgs {
  const PlayerArgs({
    required this.source,
    required this.type,
    required this.metaId,
    required this.videoId,
    required this.name,
    this.poster,
    this.background,
    this.episodeLabel,
    this.httpHeaders = const {},
    this.subtitles,
    this.audioTracks = const [],
  });

  final StreamSource source;
  final String type;
  final String metaId;
  final String videoId;
  final String name;
  final String? poster;
  final String? background;
  final String? episodeLabel;

  /// Request headers the video host needs (e.g. Referer for anime sources).
  final Map<String, String> httpHeaders;

  /// Subtitles supplied by the caller; null = ask the subtitle add-ons.
  final List<SubtitleInfo>? subtitles;

  /// Separate audio files offered alongside the video.
  final List<({String url, String lang})> audioTracks;
}

/// Full-screen player (libmpv via media_kit). Torrents are streamed through
/// the native engine; subtitles come from the subtitle add-ons.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.args});

  final PlayerArgs args;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Player _player = Player(
    configuration: PlayerConfiguration(
      title: widget.args.name,
      bufferSize: 64 * 1024 * 1024,
    ),
  );
  late final VideoController _video = VideoController(_player);
  late final MoviesRepository _repo = ref.read(moviesRepositoryProvider);
  late final WatchHistoryNotifier _history = ref.read(
    watchHistoryProvider.notifier,
  );

  final _torrent = ValueNotifier<TorrentStreamStatus?>(null);
  final _started = DateTime.now();
  Timer? _poll;
  Timer? _saveTimer;
  StreamSubscription<String>? _errors;
  String? _url;
  String? _error;
  bool _opened = false;
  List<SubtitleInfo> _subtitles = const [];

  /// Titles of the online subtitles we loaded; mpv lists them as tracks too.
  final _loadedSubtitleTitles = <String>{};
  double _subDelay = 0;

  PlayerArgs get _args => widget.args;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _configureMpv();
    _errors = _player.stream.error.listen((e) {
      if (!_opened || !mounted) return;
      // A subtitle/audio file failing, or a hiccup once the video is
      // playing, isn't fatal: tell the user and keep going.
      final loaded = _player.state.duration > Duration.zero;
      if (e.contains('external file') || loaded) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e)));
        return;
      }
      setState(() => _error = e);
    });
    final source = _args.source;
    if (source.url != null) {
      _open(source.url!);
    } else {
      _startTorrent();
    }
    _loadSubtitles();
  }

  Future<void> _configureMpv() async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      // Torrent pieces can take a while to arrive; don't give up on them.
      await platform.setProperty('network-timeout', '120');
      await platform.setProperty('cache', 'yes');
      // When the cache runs dry, refill a few seconds before resuming
      // instead of stuttering frame by frame.
      await platform.setProperty('cache-pause-wait', '4');
      await platform.setProperty('demuxer-max-back-bytes', '33554432');
    }
  }

  Future<void> _startTorrent() async {
    try {
      final status = await _repo.startTorrent(_args.source);
      if (!mounted) return;
      _torrent.value = status;
      _poll = Timer.periodic(const Duration(seconds: 1), (_) => _pollTorrent());
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _pollTorrent() async {
    final id = _torrent.value?.id;
    if (id == null) return;
    try {
      final status = await _repo.torrentStatus(id);
      if (!mounted) return;
      if (status == null) {
        _poll?.cancel();
        return;
      }
      _torrent.value = status;
      if (status.failed) {
        _poll?.cancel();
        setState(() => _error = status.error ?? 'Torrent failed.');
      } else if (status.ready && !_opened && status.url != null) {
        _open(status.url!);
      } else {
        setState(() {});
      }
    } catch (_) {
      // Transient; try again next tick.
    }
  }

  Future<void> _open(String url) async {
    _url = url;
    setState(() => _opened = true);
    final resume = _history.entryFor(_args.videoId);
    final start =
        resume != null &&
            !resume.finished &&
            resume.position > const Duration(seconds: 30)
        ? resume.position - const Duration(seconds: 3)
        : null;
    await _player.open(
      Media(url, start: start, httpHeaders: _args.httpHeaders),
    );
    _saveTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _saveProgress(),
    );
    _applyPreferredSubtitle();
  }

  Future<void> _loadSubtitles() async {
    if (_args.subtitles != null) {
      _subtitles = _args.subtitles!;
      _applyPreferredSubtitle();
      return;
    }
    try {
      final subs = await ref.read(
        subtitlesProvider((type: _args.type, videoId: _args.videoId)).future,
      );
      if (!mounted) return;
      _subtitles = subs;
      _applyPreferredSubtitle();
    } catch (_) {
      // Subtitles are optional.
    }
  }

  bool _autoSubtitleDone = false;

  void _applyPreferredSubtitle() {
    if (_autoSubtitleDone || !_opened || _subtitles.isEmpty) return;
    _autoSubtitleDone = true;
    final lang = ref.read(subtitleLanguageProvider);
    final match = _subtitles
        .where((s) => languageCode(s.lang) == lang)
        .firstOrNull;
    if (match != null) _selectExternal(match, 1);
  }

  /// "English 2" for add-on codes; sources that send names keep their own
  /// label (they already number duplicates).
  String _subLabel(SubtitleInfo s, int n) =>
      languageNames.containsKey(s.lang) ? '${s.languageName} $n' : s.lang;

  Future<void> _selectExternal(SubtitleInfo s, int n) async {
    final title = _subLabel(s, n);
    _loadedSubtitleTitles.add(title);
    if (_args.httpHeaders.isEmpty) {
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(s.url, title: title, language: s.lang),
      );
      return;
    }
    // Hosts that need headers (Referer…) also need them for subtitles, and
    // mpv may fetch the file before the video's headers apply: download it
    // ourselves and hand mpv the text.
    try {
      final res = await http
          .get(Uri.parse(s.url), headers: _args.httpHeaders)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
      await _player.setSubtitleTrack(
        SubtitleTrack.data(
          utf8.decode(res.bodyBytes, allowMalformed: true),
          title: title,
          language: s.lang,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load subtitles ($e)')));
    }
  }

  void _saveProgress() {
    final pos = _player.state.position;
    final dur = _player.state.duration;
    if (dur <= Duration.zero || pos < const Duration(seconds: 10)) return;
    _history.record(
      WatchEntry(
        videoId: _args.videoId,
        metaId: _args.metaId,
        type: _args.type,
        name: _args.name,
        poster: _args.poster,
        background: _args.background,
        episodeLabel: _args.episodeLabel,
        position: pos,
        duration: dur,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    if (_opened) _saveProgress();
    _poll?.cancel();
    _saveTimer?.cancel();
    _errors?.cancel();
    _player.dispose();
    final id = _torrent.value?.id;
    if (id != null) _repo.stopTorrent(id);
    _torrent.dispose();
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _openExternally() async {
    final url = _url ?? _torrent.value?.url;
    if (url == null) return;
    await _player.pause();
    final ok = await ExternalApps.openVideo(url, title: _args.name);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No video player app found.')),
      );
    }
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final controls = MaterialVideoControlsThemeData(
      seekBarPositionColor: moviesAccent,
      seekBarThumbColor: moviesAccent,
      seekOnDoubleTap: true,
      automaticallyImplySkipNextButton: false,
      automaticallyImplySkipPreviousButton: false,
      topButtonBarMargin: const EdgeInsets.symmetric(horizontal: 8),
      topButtonBar: [
        MaterialCustomButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 4),
        Expanded(child: _titleBlock()),
        MaterialCustomButton(
          icon: const Icon(Icons.subtitles_outlined),
          onPressed: _showSubtitles,
        ),
        MaterialCustomButton(
          icon: const Icon(Icons.audiotrack_outlined),
          onPressed: _showAudio,
        ),
        MaterialCustomButton(
          icon: const Icon(Icons.open_in_new),
          onPressed: _openExternally,
        ),
      ],
      bottomButtonBar: const [
        MaterialPlayOrPauseButton(),
        MaterialPositionIndicator(),
        Spacer(),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MaterialVideoControlsTheme(
            normal: controls,
            fullscreen: controls,
            child: Video(
              controller: _video,
              controls: MaterialVideoControls,
              subtitleViewConfiguration: const SubtitleViewConfiguration(
                style: TextStyle(
                  fontSize: 26,
                  height: 1.3,
                  color: Colors.white,
                  backgroundColor: Color(0x99000000),
                ),
              ),
            ),
          ),
          if (_opened && _error == null && _args.source.isTorrent)
            _StallStats(player: _player, torrent: _torrent),
          if (!_opened || _error != null) _overlay(),
        ],
      ),
    );
  }

  Widget _titleBlock() => ValueListenableBuilder(
    valueListenable: _torrent,
    builder: (_, status, _) => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _args.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        Text(
          [
            ?_args.episodeLabel,
            if (status != null)
              '↓ ${formatBytes(status.downloadRate)}/s · ${status.peers} peers',
          ].join('   '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5, color: Colors.white70),
        ),
      ],
    ),
  );

  Widget _overlay() {
    final status = _torrent.value;
    final waited = DateTime.now().difference(_started);
    final String title;
    final String? detail;
    if (_error != null) {
      title = 'Playback failed';
      detail = _error;
    } else if (status == null || status.state == 'metadata') {
      title = 'Connecting to peers…';
      detail = waited > const Duration(seconds: 40)
          ? 'This is slow — the source may have few seeders. '
                'Try another one with more 👤.'
          : status == null
          ? null
          : '${status.peers} peers';
    } else {
      title = 'Buffering ${(status.buffer * 100).round()}%';
      detail =
          '↓ ${formatBytes(status.downloadRate)}/s · ${status.peers} peers'
          '${status.fileSize > 0 ? ' · ${formatBytes(status.fileSize)}' : ''}';
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: 0.35,
          child: NetImage(_args.background ?? _args.poster),
        ),
        const ColoredBox(color: Color(0x88000000)),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _args.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_args.episodeLabel != null)
                  Text(
                    _args.episodeLabel!,
                    style: const TextStyle(color: Colors.white70),
                  ),
                const SizedBox(height: 20),
                if (_error == null)
                  SizedBox(
                    width: 240,
                    child: LinearProgressIndicator(
                      value: status != null && status.state == 'buffering'
                          ? status.buffer
                          : null,
                      color: moviesAccent,
                      backgroundColor: Colors.white24,
                    ),
                  )
                else
                  const Icon(Icons.error_outline, size: 36),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (detail != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      detail,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ),
                if (_error != null && (_url ?? status?.url) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: OutlinedButton.icon(
                      onPressed: _openExternally,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open in another player'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Track sheets
  // -------------------------------------------------------------------------

  Future<void> _showSubtitles() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xF0141418),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          final lang = ref.read(subtitleLanguageProvider);
          final current = _player.state.track.subtitle;
          final embedded = _player.state.tracks.subtitle
              .where(
                (t) =>
                    t.id != 'auto' &&
                    t.id != 'no' &&
                    !t.uri &&
                    !_loadedSubtitleTitles.contains(t.title),
              )
              .toList();
          final langs =
              {
                for (final s in _subtitles) languageCode(s.lang),
              }.toList()..sort((a, b) {
                if (a == lang) return -1;
                if (b == lang) return 1;
                return (languageNames[a] ?? a).compareTo(languageNames[b] ?? b);
              });
          final external = _subtitles
              .where((s) => languageCode(s.lang) == lang)
              .toList();

          Widget tile(String title, bool selected, VoidCallback onTap) =>
              ListTile(
                dense: true,
                title: Text(title),
                trailing: selected
                    ? const Icon(Icons.check, color: moviesAccent)
                    : null,
                onTap: () {
                  onTap();
                  setSheet(() {});
                },
              );

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            ),
            child: SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  ListTile(
                    title: const Text(
                      'Subtitles',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Earlier',
                          icon: const Icon(Icons.remove),
                          onPressed: () => setSheet(() => _setDelay(-0.25)),
                        ),
                        Text('${_subDelay.toStringAsFixed(2)} s'),
                        IconButton(
                          tooltip: 'Later',
                          icon: const Icon(Icons.add),
                          onPressed: () => setSheet(() => _setDelay(0.25)),
                        ),
                      ],
                    ),
                  ),
                  tile(
                    'Off',
                    current.id == 'no',
                    () => _player.setSubtitleTrack(SubtitleTrack.no()),
                  ),
                  if (embedded.isNotEmpty) ...[
                    const _SheetLabel('In the video'),
                    for (final t in embedded)
                      tile(
                        [
                              t.title,
                              if (t.language != null)
                                languageNames[t.language] ?? t.language,
                            ]
                            .whereType<String>()
                            .join(' · ')
                            .ifEmpty('Track ${t.id}'),
                        current.id == t.id,
                        () => _player.setSubtitleTrack(t),
                      ),
                  ],
                  if (langs.isNotEmpty) ...[
                    _SheetLabel('Online (${_subtitles.first.addonName})'),
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          for (final l in langs)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(languageNames[l] ?? l),
                                selected: l == lang,
                                selectedColor: moviesAccent.withValues(
                                  alpha: 0.35,
                                ),
                                onSelected: (_) {
                                  ref
                                      .read(subtitleLanguageProvider.notifier)
                                      .set(l);
                                  setSheet(() {});
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    for (final (i, s) in external.indexed)
                      tile(
                        _subLabel(s, i + 1),
                        current.id == s.url ||
                            current.title == _subLabel(s, i + 1),
                        () => _selectExternal(s, i + 1),
                      ),
                  ] else
                    const ListTile(
                      dense: true,
                      title: Text(
                        'No online subtitles found',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _setDelay(double change) {
    _subDelay = double.parse((_subDelay + change).toStringAsFixed(2));
    final platform = _player.platform;
    if (platform is NativePlayer) {
      platform.setProperty('sub-delay', '$_subDelay');
    }
  }

  Future<void> _showAudio() async {
    final tracks = _player.state.tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    final current = _player.state.track.audio;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xF0141418),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const ListTile(
              title: Text(
                'Audio',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (tracks.isEmpty && _args.audioTracks.isEmpty)
              const ListTile(dense: true, title: Text('No audio tracks yet')),
            for (final a in _args.audioTracks)
              if (!tracks.any((t) => t.id == a.url))
                ListTile(
                  dense: true,
                  title: Text(a.lang.isEmpty ? 'Extra audio' : a.lang),
                  onTap: () {
                    _player.setAudioTrack(
                      AudioTrack.uri(a.url, title: a.lang, language: a.lang),
                    );
                    Navigator.pop(context);
                  },
                ),
            for (final t in tracks)
              ListTile(
                dense: true,
                title: Text(
                  [
                    t.title,
                    if (t.language != null)
                      languageNames[t.language] ?? t.language,
                  ].whereType<String>().join(' · ').ifEmpty('Track ${t.id}'),
                ),
                trailing: t.id == current.id
                    ? const Icon(Icons.check, color: moviesAccent)
                    : null,
                onTap: () {
                  _player.setAudioTrack(t);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: Colors.white54),
    ),
  );
}

/// While the player waits for data, shows how the torrent is doing.
class _StallStats extends StatelessWidget {
  const _StallStats({required this.player, required this.torrent});

  final Player player;
  final ValueListenable<TorrentStreamStatus?> torrent;

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: player.stream.buffering,
    initialData: player.state.buffering,
    builder: (_, buffering) => buffering.data != true
        ? const SizedBox.shrink()
        : IgnorePointer(
            child: Align(
              alignment: const Alignment(0, 0.35),
              child: ValueListenableBuilder(
                valueListenable: torrent,
                builder: (_, status, _) => status == null
                    ? const SizedBox.shrink()
                    : Text(
                        '↓ ${formatBytes(status.downloadRate)}/s · '
                        '${status.peers} peers',
                        style: const TextStyle(
                          color: Colors.white70,
                          shadows: [Shadow(blurRadius: 6)],
                        ),
                      ),
              ),
            ),
          ),
  );
}
