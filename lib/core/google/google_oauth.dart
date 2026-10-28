import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../storage/shared_preferences_provider.dart';

class GoogleOAuthException implements Exception {
  const GoogleOAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Google OAuth 2.0 for installed apps, done in the system browser with PKCE
/// and a loopback redirect (`http://127.0.0.1:PORT`).
///
/// Needs no Google Play services, so it works on microG and de-Googled
/// phones. Uses a Google Cloud OAuth client of type "Desktop app"; its id and
/// secret are entered once in the app (or passed with
/// `--dart-define=GOOGLE_OAUTH_CLIENT_ID=… --dart-define=GOOGLE_OAUTH_CLIENT_SECRET=…`).
/// For installed apps the "secret" isn't confidential (Google's own docs).
class GoogleOAuth {
  GoogleOAuth(this._prefs, this._client);

  final SharedPreferences _prefs;
  final http.Client _client;

  static const _idKey = 'google.oauth.clientId';
  static const _secretKey = 'google.oauth.clientSecret';
  static const _refreshKey = 'google.oauth.refreshToken';
  static const _defaultId = String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');
  static const _defaultSecret = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_SECRET',
  );

  /// Deep link the "Return to MyKit" button on the success page opens.
  static const returnUri = 'mykit://oauth/done';

  String? _accessToken;
  DateTime? _expiresAt;

  String get _clientId => _prefs.getString(_idKey) ?? _defaultId;
  String get _clientSecret => _prefs.getString(_secretKey) ?? _defaultSecret;

  bool get isConfigured => _clientId.isNotEmpty && _clientSecret.isNotEmpty;
  bool get isSignedIn => _prefs.getString(_refreshKey) != null;

  Future<void> saveClient(String clientId, String clientSecret) async {
    await _prefs.setString(_idKey, clientId.trim());
    await _prefs.setString(_secretKey, clientSecret.trim());
    await _forget();
  }

  /// A valid access token for [scopes]: cached, refreshed silently, or — if
  /// [interactive] — obtained by signing in through the browser.
  Future<String> accessToken(
    List<String> scopes, {
    bool interactive = true,
  }) async {
    if (!isConfigured) {
      throw const GoogleOAuthException('Google API client is not set up.');
    }
    final cached = _accessToken;
    if (cached != null && DateTime.now().isBefore(_expiresAt!)) return cached;

    final refresh = _prefs.getString(_refreshKey);
    if (refresh != null) {
      try {
        return await _token({
          'grant_type': 'refresh_token',
          'refresh_token': refresh,
        });
      } on GoogleOAuthException {
        await _forget(); // revoked or expired: sign in again
      }
    }
    if (!interactive) {
      throw const GoogleOAuthException('Sign in with Google first.');
    }
    return _signIn(scopes);
  }

  /// Drops the cached access token (e.g. after the API answered 401).
  void invalidateAccessToken() => _accessToken = null;

  /// Revokes MyKit's access and forgets the tokens.
  Future<void> signOut() async {
    final refresh = _prefs.getString(_refreshKey);
    if (refresh != null) {
      try {
        await _client.post(
          Uri.https('oauth2.googleapis.com', '/revoke', {'token': refresh}),
        );
      } catch (_) {
        // Best effort; tokens are forgotten locally anyway.
      }
    }
    await _forget();
  }

  Future<String> _signIn(List<String> scopes) async {
    final verifier = _random(64);
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    final state = _random(24);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUri = 'http://127.0.0.1:${server.port}';
    try {
      final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': _clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': scopes.join(' '),
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        'access_type': 'offline',
        'prompt': 'consent',
      });
      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        throw const GoogleOAuthException('Could not open the browser.');
      }

      final request = await server.first.timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw const GoogleOAuthException(
          'Sign-in timed out. Please try again.',
        ),
      );
      final params = request.uri.queryParameters;
      final ok = params['state'] == state && params['code'] != null;
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(_resultPage(ok));
      await request.response.close();

      if (params['error'] == 'access_denied') {
        throw const GoogleOAuthException('Access was not granted.');
      }
      if (!ok) throw const GoogleOAuthException('Sign-in failed.');

      return await _token({
        'grant_type': 'authorization_code',
        'code': params['code']!,
        'code_verifier': verifier,
        'redirect_uri': redirectUri,
      });
    } finally {
      await server.close(force: true);
    }
  }

  Future<String> _token(Map<String, String> fields) async {
    final res = await _client.post(
      Uri.https('oauth2.googleapis.com', '/token'),
      body: {'client_id': _clientId, 'client_secret': _clientSecret, ...fields},
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw GoogleOAuthException(
        body['error_description'] as String? ??
            body['error'] as String? ??
            'Google sign-in failed (${res.statusCode}).',
      );
    }
    final refresh = body['refresh_token'] as String?;
    if (refresh != null) await _prefs.setString(_refreshKey, refresh);
    _accessToken = body['access_token'] as String;
    // Renew a minute early.
    _expiresAt = DateTime.now().add(
      Duration(seconds: ((body['expires_in'] as num?)?.toInt() ?? 3600) - 60),
    );
    return _accessToken!;
  }

  Future<void> _forget() async {
    _accessToken = null;
    _expiresAt = null;
    await _prefs.remove(_refreshKey);
  }

  static String _random(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rnd = Random.secure();
    return List.generate(
      length,
      (_) => chars[rnd.nextInt(chars.length)],
    ).join();
  }

  static String _resultPage(bool ok) =>
      '''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>MyKit</title><style>body{font-family:sans-serif;background:#1f1f21;color:#fff;text-align:center;padding:48px 24px}
a{display:inline-block;margin-top:24px;padding:14px 28px;background:#1a9cd8;color:#fff;border-radius:24px;text-decoration:none;font-weight:600}</style></head>
<body><h2>${ok ? 'Signed in ✓' : 'Sign-in failed'}</h2>
<p>${ok ? 'You can go back to MyKit now.' : 'Return to MyKit and try again.'}</p>
<a href="$returnUri">Return to MyKit</a>
<script>setTimeout(function(){location.href="$returnUri"},600)</script></body></html>''';
}

/// App-wide Google OAuth client (browser-based; works with microG).
final googleOAuthProvider = Provider<GoogleOAuth>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return GoogleOAuth(ref.watch(sharedPreferencesProvider), client);
});
