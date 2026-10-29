import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../storage/shared_preferences_provider.dart';

class AiException implements Exception {
  const AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One turn of a conversation.
typedef AiMessage = ({bool fromUser, String text});

/// Google Gemini (generateContent REST API).
///
/// Uses the regular Flash-Lite model, which has the largest free-tier quota,
/// and falls back to Flash when it is busy or retired.
class GeminiClient {
  GeminiClient(this._client, this._apiKey);

  final http.Client _client;
  final String? _apiKey;

  static const models = ['gemini-3.5-flash-lite', 'gemini-3.5-flash'];

  bool get isConfigured => _apiKey?.isNotEmpty ?? false;

  Future<String> generate({
    String? system,
    required List<AiMessage> messages,
    double temperature = 0.4,
  }) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      throw const AiException('Add a Gemini API key first.');
    }
    final body = jsonEncode({
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
      'generationConfig': {'temperature': temperature},
    });

    AiException? last;
    for (final model in models) {
      final http.Response res;
      try {
        res = await _client
            .post(
              Uri.parse(
                'https://generativelanguage.googleapis.com/v1beta/models/'
                '$model:generateContent',
              ),
              headers: {
                'Content-Type': 'application/json',
                'x-goog-api-key': key,
              },
              body: body,
            )
            .timeout(const Duration(seconds: 60));
      } catch (_) {
        throw const AiException(
          'Could not reach Gemini. Check your connection.',
        );
      }

      final json = _decode(res.body);
      if (res.statusCode == 200) return _text(json);

      final message = (json['error'] as Map?)?['message'] as String? ?? '';
      switch (res.statusCode) {
        // Busy, retired or out of quota for this model: try the next one.
        case 503 || 404 || 429 || 500:
          last = AiException(
            res.statusCode == 429
                ? 'Free quota used up for now. Try again in a minute.'
                : 'Gemini is busy right now. Try again shortly.',
          );
          continue;
        case 400 || 401 || 403:
          throw AiException(
            message.toLowerCase().contains('key')
                ? 'The Gemini API key was rejected.'
                : 'Gemini refused the request: $message',
          );
        default:
          throw AiException('Gemini error ${res.statusCode}: $message');
      }
    }
    throw last ?? const AiException('Gemini is unavailable.');
  }

  static Map<String, dynamic> _decode(String body) {
    try {
      final v = jsonDecode(body);
      return v is Map<String, dynamic> ? v : const {};
    } catch (_) {
      return const {};
    }
  }

  static String _text(Map<String, dynamic> json) {
    final candidates = json['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      final reason = (json['promptFeedback'] as Map?)?['blockReason'];
      throw AiException(
        reason != null ? 'Gemini declined this ($reason).' : 'No answer.',
      );
    }
    final c = candidates.first as Map<String, dynamic>;
    final parts = ((c['content'] as Map?)?['parts'] as List?) ?? const [];
    final text = [
      for (final p in parts.cast<Map<String, dynamic>>())
        if (p['thought'] != true && p['text'] is String) p['text'] as String,
    ].join().trim();
    if (text.isEmpty) {
      throw AiException('No answer (${c['finishReason'] ?? 'empty'}).');
    }
    return text;
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
