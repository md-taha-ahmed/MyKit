import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../../core/i18n/i18n.dart';
import '../../domain/entities/manga_entities.dart';
import '../../domain/repositories/manga_repository.dart';
import '../parsers/extension_index_parser.dart';

/// Resolves Mihon extension repositories the same way Mihon 0.20+ does:
/// legacy `index.min.json` → `repo.json` → `index_v2` (protobuf) → list.
class ExtensionRepoRemoteDataSource {
  ExtensionRepoRemoteDataSource(this._client);

  final http.Client _client;

  Future<({ExtensionRepo repo, List<AvailableExtension> extensions})> fetch(
    String inputUrl,
  ) async {
    final url = inputUrl.trim();
    final bytes = await _get(url);
    if (bytes.isEmpty) throw MangaException(tr('Repository is empty.'));

    switch (bytes.first) {
      case 0x5B: // '[' legacy index.min.json
        if (!url.endsWith('/index.min.json')) {
          throw MangaException(
            tr('Legacy repositories must end with /index.min.json'),
          );
        }
        final repoJsonUrl = url.replaceFirst(
          RegExp(r'/index\.min\.json$'),
          '/repo.json',
        );
        final repoJson =
            jsonDecode(utf8.decode(await _get(repoJsonUrl)))
                as Map<String, dynamic>;
        final parsed = ExtensionIndexParser.parseRepoJson(url, repoJson);
        if (parsed.indexV2 != null) {
          return _fromStore(url, parsed.indexV2!);
        }
        final legacy = jsonDecode(utf8.decode(bytes)) as List<dynamic>;
        return (
          repo: parsed.repo,
          extensions: ExtensionIndexParser.parseLegacyIndex(
            legacy,
            parsed.repo,
            url.replaceFirst(RegExp(r'/index\.min\.json$'), ''),
          ),
        );
      case 0x7B: // '{' repo.json
        final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        if (json.containsKey('meta')) {
          final parsed = ExtensionIndexParser.parseRepoJson(url, json);
          if (parsed.indexV2 == null) {
            throw MangaException(tr('repo.json has no extension index.'));
          }
          return _fromStore(url, parsed.indexV2!);
        }
        throw MangaException(tr('Unsupported repository format.'));
      default: // protobuf store
        return _storeFromBytes(url, bytes);
    }
  }

  Future<({ExtensionRepo repo, List<AvailableExtension> extensions})>
  _fromStore(String repoUrl, String storeUrl) async =>
      _storeFromBytes(repoUrl, await _get(storeUrl));

  Future<({ExtensionRepo repo, List<AvailableExtension> extensions})>
  _storeFromBytes(String repoUrl, Uint8List bytes) async {
    final store = ExtensionIndexParser.parseStore(repoUrl, bytes);
    if (store.repo.signingKey.isEmpty) {
      throw MangaException(tr('Repository has no signing key.'));
    }
    final list =
        store.list ??
        (store.listUrl != null ? await _get(store.listUrl!) : null);
    if (list == null) {
      throw MangaException(tr('Repository has no extensions.'));
    }
    return (
      repo: store.repo,
      extensions: ExtensionIndexParser.parseExtensionList(list, store.repo),
    );
  }

  Future<Uint8List> _get(String url) async {
    final http.Response res;
    try {
      res = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw MangaException(tr('Could not reach {url}', {'url': url}));
    }
    if (res.statusCode >= 400) {
      throw MangaException(
        tr('Repository returned {statusCode}.', {'statusCode': res.statusCode}),
      );
    }
    return ExtensionIndexParser.maybeGunzip(res.bodyBytes);
  }
}
