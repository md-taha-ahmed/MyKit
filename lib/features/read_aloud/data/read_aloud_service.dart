import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class ReadAloudException implements Exception {
  const ReadAloudException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What it's doing while you wait.
enum ReadAloudStage { vowels, voice }

/// What to play and what to show.
class ReadAloudResult {
  const ReadAloudResult({
    required this.audio,
    required this.text,
    required this.vowelled,
    required this.fromCache,
  });

  final File audio;

  /// The text being read, with its vowels if they were added.
  final String text;

  /// False when the original had to be read without added vowels.
  final bool vowelled;
  final bool fromCache;
}

const readAloudMaxChars = 3000;

/// Above this, the data it costs is worth asking about first.
const readAloudAskAboveChars = 400;

/// From a real test: about 6 MB (with the API's encoding) for 8 verses.
double readAloudMegabytes(int chars) => chars * 0.015;

bool hasArabic(String text) => RegExp('[ء-ي]').hasMatch(text);

final _marks = RegExp('[ً-ْٰ]');

/// Enough vowels already that adding them would only risk mistakes.
bool isVowelled(String text) {
  final letters = RegExp('[ء-ي]').allMatches(text).length;
  if (letters == 0) return false;
  return _marks.allMatches(text).length / letters > 0.25;
}

/// The Arabic letters alone, to check vowelling changed nothing else.
String arabicLetters(String text) => text.replaceAll(RegExp('[^ء-ي]'), '');

/// Wraps raw 16-bit mono audio in a WAV header.
Uint8List pcmToWav(Uint8List pcm, int rate) {
  final header = ByteData(44);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVEfmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, rate, Endian.little);
  header.setUint32(28, rate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...pcm]);
}

/// A file name for a selection (FNV-1a over its UTF-8 bytes).
String readAloudCacheName(String text) {
  final bytes = utf8.encode(text);
  var hash = 0xcbf29ce484222325;
  for (final b in bytes) {
    hash = (hash ^ b) * 0x100000001b3;
  }
  // The version changes with the voice, so older audio is never replayed.
  return 'v3_${hash.toUnsigned(64).toRadixString(16)}_${bytes.length}';
}

/// Adds the vowels, gets the voice from Gemini, and keeps both, so the same
/// selection never costs data twice.
class ReadAloudService {
  ReadAloudService(
    this._client,
    this._apiKey,
    this._cacheDir, {
    this.vowelBudget = const Duration(seconds: 20),
    this.voiceTimeout = const Duration(seconds: 40),
  });

  final http.Client _client;
  final String? _apiKey;
  final Directory _cacheDir;

  /// Vowels are a nicety: past this, read the text without them. Measured on
  /// one short line they took 10 to 25 seconds, and one model hung for 70.
  final Duration vowelBudget;

  /// For one voice model, before trying the next. Longer text gets longer.
  final Duration voiceTimeout;

  /// By measured speed; the newest are often busy.
  static const vowelModels = [
    'gemini-3.6-flash',
    'gemini-3.5-flash',
    'gemini-3.8-flash',
    'gemini-flash-lite-latest',
  ];

  /// The section's one voice: the deepest of those compared (about 110 Hz).
  static const voiceName = 'Iapetus';

  /// The first is the model the voice was chosen on, so it sounds the same;
  /// the rest only step in when that one is busy or refuses the text.
  static const voiceModels = [
    'gemini-3.1-flash-tts-preview',
    'gemini-3.8-flash-lite-tts',
    'gemini-3.8-flash-tts',
    'gemini-2.5-flash-preview-tts',
  ];

  static const _maxCacheBytes = 100 * 1024 * 1024;

  static const _vowelSystem =
      'أنت محقق للنصوص العربية القديمة والشعر. شكّل كل كلمة تشكيلاً تاماً وفق '
      'النحو والعروض وما اشتهرت به الرواية. لا تغيّر أي حرف ولا كلمة ولا تزد '
      'ولا تنقص، حتى لو ظننت أن في النص خطأ، واحتفظ بالأسطر والترقيم كما هي. '
      'أخرج النص المشكول فقط.';

  bool get isConfigured => _apiKey?.isNotEmpty ?? false;

  Future<bool> isCached(String text) async {
    final name = readAloudCacheName(text);
    return await File('${_cacheDir.path}/$name.wav').exists() &&
        await File('${_cacheDir.path}/$name.txt').exists();
  }

  Future<ReadAloudResult> prepare(
    String text, {
    void Function(ReadAloudStage stage)? onStage,
  }) async {
    final name = readAloudCacheName(text);
    await _cacheDir.create(recursive: true);
    final audio = File('${_cacheDir.path}/$name.wav');
    final shown = File('${_cacheDir.path}/$name.txt');
    if (await audio.exists() && await shown.exists()) {
      final saved = await shown.readAsString();
      return ReadAloudResult(
        audio: audio,
        text: saved,
        vowelled: saved != text,
        fromCache: true,
      );
    }
    if (!isConfigured) {
      throw const ReadAloudException(
        'أضف مفتاح Gemini من إعدادات MyKit أولاً.',
      );
    }

    if (hasArabic(text) && !isVowelled(text)) {
      onStage?.call(ReadAloudStage.vowels);
    }
    final spoken = await _vowelled(text);
    onStage?.call(ReadAloudStage.voice);
    final bytes = await _voice(spoken);
    await audio.writeAsBytes(bytes, flush: true);
    await shown.writeAsString(spoken, flush: true);
    await _trimCache();
    return ReadAloudResult(
      audio: audio,
      text: spoken,
      vowelled: spoken != text,
      fromCache: false,
    );
  }

  /// The original comes back if vowelling is slow, fails or changes any letter:
  /// a plain reading beats waiting, or words the author didn't write.
  Future<String> _vowelled(String text) async {
    if (!hasArabic(text) || isVowelled(text)) return text;
    final extra = Duration(milliseconds: text.length * 25);
    final deadline = DateTime.now().add(vowelBudget + extra);
    for (final model in vowelModels) {
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) break;
      try {
        final json = await _post(model, {
          'systemInstruction': {
            'parts': [
              {'text': _vowelSystem},
            ],
          },
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': text},
              ],
            },
          ],
          'generationConfig': {'temperature': 0},
        }, left);
        final output = _parts(
          json,
        ).map((p) => p['text']).whereType<String>().join().trim();
        if (output.isEmpty) continue;
        return arabicLetters(output) == arabicLetters(text) ? output : text;
      } on _Retry {
        continue;
      } on ReadAloudException {
        // No connection or a bad key: the voice step says so.
        return text;
      }
    }
    return text;
  }

  Future<Uint8List> _voice(String text) async {
    ReadAloudException? last;
    for (final model in voiceModels) {
      try {
        final json = await _post(model, {
          'contents': [
            {
              'parts': [
                // Only the text: this voice speaks any instructions sent with it.
                {'text': text},
              ],
            },
          ],
          'generationConfig': {
            'responseModalities': ['AUDIO'],
            'speechConfig': {
              'voiceConfig': {
                'prebuiltVoiceConfig': {'voiceName': voiceName},
              },
            },
          },
        }, voiceTimeout + Duration(milliseconds: text.length * 40));
        for (final part in _parts(json)) {
          final inline = part['inlineData'];
          if (inline is! Map) continue;
          final data = base64.decode(inline['data'] as String);
          final mime = (inline['mimeType'] as String? ?? '').toLowerCase();
          if (mime.contains('wav')) return data;
          final rate = RegExp(r'rate=(\d+)').firstMatch(mime)?.group(1);
          return pcmToWav(data, int.tryParse(rate ?? '') ?? 24000);
        }
        // No audio (some models refuse some text at random): try the next.
        last = const ReadAloudException('تعذّر إنشاء الصوت، حاول مرة أخرى.');
      } on _Retry catch (r) {
        last = r.failure;
      }
    }
    throw last ?? const ReadAloudException('تعذّر إنشاء الصوت، حاول مرة أخرى.');
  }

  Iterable<Map<dynamic, dynamic>> _parts(Map<String, dynamic> json) {
    final candidates = json['candidates'];
    if (candidates is! List || candidates.isEmpty) return const [];
    final content = (candidates.first as Map)['content'];
    if (content is! Map) return const [];
    final parts = content['parts'];
    return parts is List ? parts.whereType<Map>() : const [];
  }

  Future<Map<String, dynamic>> _post(
    String model,
    Map<String, dynamic> body,
    Duration timeout,
  ) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/'
              '$model:generateContent',
            ),
            headers: {
              'x-goog-api-key': _apiKey ?? '',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const _Retry(
        ReadAloudException('استغرقت الخدمة وقتاً طويلاً، حاول مرة أخرى.'),
      );
    } catch (_) {
      throw const ReadAloudException('لا يوجد اتصال بالإنترنت.');
    }
    switch (res.statusCode) {
      case 200:
        return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      case 429:
        throw const _Retry(
          ReadAloudException('انتهت الحصة المجانية الآن، حاول بعد قليل.'),
        );
      case 401 || 403:
        throw const ReadAloudException(
          'رفض Gemini المفتاح، تحقق منه في الإعدادات.',
        );
      default:
        throw const _Retry(
          ReadAloudException('خدمة Gemini مشغولة الآن، حاول بعد قليل.'),
        );
    }
  }

  /// Keeps the newest audio within [_maxCacheBytes].
  Future<void> _trimCache() async {
    final files = (await _cacheDir.list().toList()).whereType<File>().toList();
    for (final old in files.where(
      (f) => !f.uri.pathSegments.last.startsWith('v3_'),
    )) {
      await old.delete();
    }
    files.removeWhere((f) => !f.uri.pathSegments.last.startsWith('v3_'));
    final sized = [for (final f in files) (file: f, stat: await f.stat())]
      ..sort((a, b) => b.stat.modified.compareTo(a.stat.modified));
    var total = 0;
    for (final e in sized) {
      total += e.stat.size;
      if (total > _maxCacheBytes) await e.file.delete();
    }
  }
}

/// This model can't help right now; another might.
class _Retry implements Exception {
  const _Retry(this.failure);

  final ReadAloudException failure;
}
