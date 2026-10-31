import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../i18n/i18n.dart';
import '../storage/shared_preferences_provider.dart';

class AiException implements Exception {
  const AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One turn of a conversation.
typedef AiMessage = ({bool fromUser, String text});

/// A web page Gemini used when it searched (Google Search grounding).
class AiSource {
  const AiSource({required this.title, required this.url});

  final String title;
  final String url;
}

/// An answer: its text (so far, while streaming) and the pages it used.
class AiReply {
  const AiReply(this.text, [this.sources = const []]);

  final String text;
  final List<AiSource> sources;
}

/// Google Gemini (generateContent REST API).
///
/// Uses the regular Flash-Lite model, which has the largest free-tier quota,
/// and falls back to Flash when it is busy or retired. With `webSearch`,
/// Gemini may look things up with Google Search; if a model refuses the tool
/// the request is repeated without it.
class GeminiClient {
  GeminiClient(this._client, this._apiKey);

  final http.Client _client;
  final String? _apiKey;

  /// Tried in order; reliability over power (all three are on the free
  /// tier, and the last is an alias Google keeps pointing at a live model).
  static const models = [
    'gemini-3.5-flash-lite',
    'gemini-3.5-flash',
    'gemini-flash-latest',
  ];

  /// Free plans may have no Google Search quota (every search is a 429).
  /// After one refusal, skip search for a while instead of failing.
  static DateTime? _searchBlockedUntil;
  static const _searchBlockFor = Duration(hours: 6);

  static bool get searchAvailable {
    final until = _searchBlockedUntil;
    return until == null || DateTime.now().isAfter(until);
  }

  static const _timeout = Duration(seconds: 90);

  bool get isConfigured => _apiKey?.isNotEmpty ?? false;

  Future<String> generate({
    String? system,
    required List<AiMessage> messages,
    double temperature = 0.4,
  }) async => (await reply(
    system: system,
    messages: messages,
    temperature: temperature,
  )).text;

  /// The whole answer at once.
  Future<AiReply> reply({
    String? system,
    required List<AiMessage> messages,
    double temperature = 0.4,
    bool webSearch = false,
  }) async {
    final key = _key();
    return _withFallback(webSearch, (model, search) async {
      final http.Response res;
      try {
        res = await _client
            .post(
              _uri(model, 'generateContent'),
              headers: _headers(key),
              body: _body(system, messages, temperature, search),
            )
            .timeout(_timeout);
      } catch (_) {
        throw AiException(tr('Could not reach Gemini. Check your connection.'));
      }
      final json = _decode(res.body);
      if (res.statusCode != 200) throw _HttpFailure(res.statusCode, json);
      final out = _Accumulator()..add(json);
      return out.finish();
    });
  }

  /// The answer as it's written: each event is the reply so far.
  Stream<AiReply> streamReply({
    String? system,
    required List<AiMessage> messages,
    double temperature = 0.4,
    bool webSearch = false,
  }) {
    final String key;
    try {
      key = _key();
    } on AiException catch (e) {
      return Stream.error(e);
    }
    final controller = StreamController<AiReply>();
    _withFallback(webSearch, (model, search) async {
      final request =
          http.Request('POST', _uri(model, 'streamGenerateContent', sse: true))
            ..headers.addAll(_headers(key))
            ..body = _body(system, messages, temperature, search);
      final http.StreamedResponse res;
      try {
        res = await _client.send(request).timeout(_timeout);
      } catch (_) {
        throw AiException(tr('Could not reach Gemini. Check your connection.'));
      }
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString();
        throw _HttpFailure(res.statusCode, _decode(body));
      }
      final out = _Accumulator();
      try {
        await for (final line
            in res.stream
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .timeout(_timeout)) {
          if (!line.startsWith('data:')) continue;
          out.add(_decode(line.substring(5).trim()));
          if (out.text.isNotEmpty) controller.add(out.current);
        }
      } on AiException {
        rethrow;
      } catch (_) {
        throw AiException(tr('The connection dropped. Try again.'));
      }
      return out.finish();
    }).then(
      (done) {
        controller.add(done);
        controller.close();
      },
      onError: (Object e) {
        controller.addError(e);
        controller.close();
      },
    );
    return controller.stream;
  }

  String _key() {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      throw AiException(tr('Add a Gemini API key first.'));
    }
    return key;
  }

  /// Tries each model; on a 400 with web search, retries without it.
  Future<AiReply> _withFallback(
    bool webSearch,
    Future<AiReply> Function(String model, bool search) attempt,
  ) async {
    AiException? last;
    for (final model in models) {
      var search = webSearch && searchAvailable;
      while (true) {
        try {
          return await attempt(model, search);
        } on _HttpFailure catch (f) {
          final message =
              (f.json['error'] as Map?)?['message'] as String? ?? '';
          switch (f.status) {
            // The model (or plan) may not support search: ask without it.
            case 400 when search && !message.toLowerCase().contains('key'):
              search = false;
              continue;
            // Out of search quota (common on free plans): answer without it.
            case 429 when search:
              _searchBlockedUntil = DateTime.now().add(_searchBlockFor);
              search = false;
              continue;
            // Busy, retired or out of quota for this model: try the next.
            case 503 || 404 || 429 || 500:
              last = AiException(
                f.status == 429
                    ? 'Free quota used up for now. Try again in a minute.'
                    : 'Gemini is busy right now. Try again shortly.',
              );
            case 400 || 401 || 403:
              throw AiException(
                message.toLowerCase().contains('key')
                    ? 'The Gemini API key was rejected.'
                    : 'Gemini refused the request: $message',
              );
            default:
              throw AiException(
                tr('Gemini error {status}: {message}', {
                  'status': f.status,
                  'message': message,
                }),
              );
          }
          break;
        }
      }
    }
    throw last ?? AiException(tr('Gemini is unavailable.'));
  }

  static Uri _uri(String model, String method, {bool sse = false}) => Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/'
    '$model:$method${sse ? '?alt=sse' : ''}',
  );

  static Map<String, String> _headers(String key) => {
    'Content-Type': 'application/json',
    'x-goog-api-key': key,
  };

  static String _body(
    String? system,
    List<AiMessage> messages,
    double temperature,
    bool search,
  ) => jsonEncode({
    if (system != null)
      'systemInstruction': {
        'parts': [
          {'text': system},
        ],
      },
    'contents': [
      for (final m in messages)
        {
          'role': m.fromUser ? 'user' : 'model',
          'parts': [
            {'text': m.text},
          ],
        },
    ],
    if (search)
      'tools': [
        {'google_search': <String, Object>{}},
      ],
    'generationConfig': {'temperature': temperature},
  });

  static Map<String, dynamic> _decode(String body) {
    try {
      final v = jsonDecode(body);
      return v is Map<String, dynamic> ? v : const {};
    } catch (_) {
      return const {};
    }
  }
}

class _HttpFailure implements Exception {
  const _HttpFailure(this.status, this.json);

  final int status;
  final Map<String, dynamic> json;
}

/// Collects text (minus "thought" parts) and grounding sources from one
/// response or a stream of chunks.
class _Accumulator {
  final _text = StringBuffer();
  final _sources = <String, AiSource>{};
  Object? _blockReason;
  Object? _finishReason;

  String get text => _text.toString().trim();
  AiReply get current => AiReply(text, _sources.values.toList());

  void add(Map<String, dynamic> json) {
    _blockReason ??= (json['promptFeedback'] as Map?)?['blockReason'];
    final candidates = json['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return;
    final c = candidates.first as Map<String, dynamic>;
    _finishReason = c['finishReason'] ?? _finishReason;
    final parts = ((c['content'] as Map?)?['parts'] as List?) ?? const [];
    for (final p in parts.cast<Map<String, dynamic>>()) {
      if (p['thought'] != true && p['text'] is String) {
        _text.write(p['text'] as String);
      }
    }
    final chunks =
        ((c['groundingMetadata'] as Map?)?['groundingChunks'] as List?) ??
        const [];
    for (final chunk in chunks) {
      final web = (chunk as Map)['web'] as Map?;
      final url = web?['uri'] as String?;
      if (url == null) continue;
      _sources[url] = AiSource(
        title: (web!['title'] as String?) ?? Uri.tryParse(url)?.host ?? url,
        url: url,
      );
    }
  }

  AiReply finish() {
    if (text.isNotEmpty) return current;
    if (_blockReason != null) {
      throw AiException(
        tr('Gemini declined this ({_blockReason}).', {
          '_blockReason': _blockReason,
        }),
      );
    }
    throw AiException(
      _finishReason != null ? 'No answer ($_finishReason).' : 'No answer.',
    );
  }
}

/// The key: set in the app (stored on the device) or built in with
/// `--dart-define-from-file=config/ai.local.json` (git-ignored).
final geminiApiKeyProvider = NotifierProvider<GeminiApiKeyNotifier, String?>(
  GeminiApiKeyNotifier.new,
);

class GeminiApiKeyNotifier extends Notifier<String?> {
  static const _prefsKey = 'ai.gemini.apiKey';
  static const _builtIn = String.fromEnvironment('GEMINI_API_KEY');

  @override
  String? build() {
    final saved = ref.read(sharedPreferencesProvider).getString(_prefsKey);
    if (saved != null && saved.isNotEmpty) return saved;
    return _builtIn.isEmpty ? null : _builtIn;
  }

  Future<void> set(String? key) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final trimmed = key?.trim() ?? '';
    trimmed.isEmpty
        ? await prefs.remove(_prefsKey)
        : await prefs.setString(_prefsKey, trimmed);
    state = trimmed.isEmpty ? (_builtIn.isEmpty ? null : _builtIn) : trimmed;
  }
}

final geminiClientProvider = Provider<GeminiClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return GeminiClient(client, ref.watch(geminiApiKeyProvider));
});
