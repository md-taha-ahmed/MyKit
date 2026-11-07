import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/ai/gemini_client.dart';
import '../data/read_aloud_service.dart';

const _accent = Color(0xFF8D6E63);

/// A small card over whatever app the text was selected in.
class ReadAloudApp extends ConsumerWidget {
  const ReadAloudApp({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.dark,
        ),
      ),
      color: Colors.transparent,
      home: ReadAloudPopup(
        text: text,
        service: () async {
          final dir = await getApplicationSupportDirectory();
          return ReadAloudService(
            http.Client(),
            ref.read(geminiApiKeyProvider),
            Directory('${dir.path}/read_aloud'),
          );
        },
      ),
    );
  }
}

class ReadAloudPopup extends StatefulWidget {
  const ReadAloudPopup({
    super.key,
    required this.text,
    required this.service,
    this.onClose = SystemNavigator.pop,
  });

  final String text;
  final Future<ReadAloudService> Function() service;
  final Future<void> Function() onClose;

  @override
  State<ReadAloudPopup> createState() => _ReadAloudPopupState();
}

enum _Stage { asking, preparing, ready, failed }

class _ReadAloudPopupState extends State<ReadAloudPopup> {
  late final String _text = widget.text.trim();
  var _stage = _Stage.preparing;
  String? _error;
  ReadAloudResult? _result;
  AudioPlayer? _player;
  var _waiting = 'جارٍ التحضير…';

  @override
  void initState() {
    super.initState();
    if (_text.isEmpty) {
      _fail('لم يصل أي نص. حدّد نصاً ثم حاول مرة أخرى.');
    } else if (_text.length > readAloudMaxChars) {
      _fail('النص طويل جداً. حدّد جزءاً أقصر (حتى $readAloudMaxChars حرف).');
    } else {
      _start();
    }
  }

  void _fail(String message) {
    _stage = _Stage.failed;
    _error = message;
  }

  /// Saved audio costs nothing, so only a new long selection asks first.
  Future<void> _start() async {
    final service = await widget.service();
    if (!mounted) return;
    if (_text.length > readAloudAskAboveChars &&
        !await service.isCached(_text)) {
      if (mounted) setState(() => _stage = _Stage.asking);
      return;
    }
    await _prepare(service);
  }

  Future<void> _prepare([ReadAloudService? known]) async {
    setState(() => _stage = _Stage.preparing);
    try {
      final service = known ?? await widget.service();
      final result = await service.prepare(
        _text,
        onStage: (stage) {
          if (!mounted) return;
          setState(
            () => _waiting = switch (stage) {
              ReadAloudStage.vowels => 'جارٍ إضافة التشكيل…',
              ReadAloudStage.voice => 'جارٍ إنشاء الصوت…',
            },
          );
        },
      );
      if (!mounted) return;
      final player = _player ??= AudioPlayer();
      await player.setFilePath(result.audio.path);
      if (!mounted) return;
      setState(() {
        _result = result;
        _stage = _Stage.ready;
      });
      unawaited(player.play());
    } on ReadAloudException catch (e) {
      if (mounted) setState(() => _fail(e.message));
    } catch (_) {
      if (mounted) setState(() => _fail('تعذّر تشغيل الصوت، حاول مرة أخرى.'));
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  void _close() {
    _player?.stop();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black26,
        body: Stack(
          children: [
            Positioned.fill(child: GestureDetector(onTap: _close)),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Material(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.volume_up, color: _accent),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'قراءة النص',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              IconButton(
                                tooltip: 'إغلاق',
                                onPressed: _close,
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: _body(theme),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    return switch (_stage) {
      _Stage.asking => _asking(),
      _Stage.preparing => _Preparing(message: _waiting),
      _Stage.failed => _failed(theme),
      _Stage.ready => _ready(theme),
    };
  }

  Widget _asking() {
    final mb = readAloudMegabytes(_text.length).ceil();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'نص طويل: سيستهلك نحو $mb ميجابايت من بياناتك، وقد يستغرق دقائق. '
          'بعدها يبقى محفوظاً ويعمل بلا إنترنت.',
          style: const TextStyle(height: 1.7),
        ),
        const SizedBox(height: 10),
        FilledButton(onPressed: () => _prepare(), child: const Text('متابعة')),
      ],
    );
  }

  Widget _failed(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_error ?? '', style: const TextStyle(height: 1.7)),
        if (_text.isNotEmpty && _text.length <= readAloudMaxChars) ...[
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => _prepare(),
            child: const Text('حاول مرة أخرى'),
          ),
        ],
      ],
    );
  }

  Widget _ready(ThemeData theme) {
    final result = _result!;
    final player = _player!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: SingleChildScrollView(
            child: SelectableText(
              result.text,
              textDirection: hasArabic(result.text)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              style: const TextStyle(fontSize: 17, height: 1.9),
            ),
          ),
        ),
        const SizedBox(height: 6),
        StreamBuilder<PlayerState>(
          stream: player.playerStateStream,
          builder: (context, snapshot) {
            final state = snapshot.data;
            final ended = state?.processingState == ProcessingState.completed;
            final playing = (state?.playing ?? false) && !ended;
            return Row(
              children: [
                IconButton.filled(
                  tooltip: playing ? 'إيقاف مؤقت' : 'تشغيل',
                  onPressed: () async {
                    if (playing) return player.pause();
                    if (ended) await player.seek(Duration.zero);
                    await player.play();
                  },
                  icon: Icon(
                    playing
                        ? Icons.pause
                        : ended
                        ? Icons.replay
                        : Icons.play_arrow,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    result.vowelled
                        ? 'التشكيل والصوت بالذكاء الاصطناعي، وقد يخطئان.'
                        : 'الصوت بالذكاء الاصطناعي، وقد يخطئ.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Preparing extends StatelessWidget {
  const _Preparing({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: _accent),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
