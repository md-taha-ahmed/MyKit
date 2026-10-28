import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/stremio_entities.dart';
import '../../domain/repositories/movies_repository.dart';

/// HTTP client for Stremio add-ons: `GET {transportUrl}/{resource}/{type}/{id}[/{extra}].json`.
class StremioAddonClient {
  StremioAddonClient(this._client);

  final http.Client _client;

  static const _timeout = Duration(seconds: 25);

  /// Accepts `https://…/manifest.json`, the bare base URL, or a
  /// `stremio://…` install link; returns the manifest URL.
  static String normalizeManifestUrl(String input) {
    var url = input.trim();
    if (url.startsWith('stremio://')) {
      url = 'https://${url.substring('stremio://'.length)}';
    }
    if (!url.startsWith('http')) url = 'https://$url';
    url = url.replaceAll(RegExp(r'/+$'), '');
    if (!url.endsWith('/manifest.json')) url = '$url/manifest.json';
    return url;
  }

  Future<AddonManifest> manifest(String manifestUrl) async {
    final json = await _get(Uri.parse(manifestUrl));
    final base = manifestUrl.substring(
      0,
      manifestUrl.length - '/manifest.json'.length,
    );
    return AddonManifest.fromJson(base, json);
  }

  Future<List<MetaPreview>> catalog(
    String transportUrl,
    String type,
    String id, {
    Map<String, String> extra = const {},
  }) async {
    final json = await _get(
      _resourceUri(transportUrl, 'catalog', type, id, extra),
    );
    return [
      for (final m in (json['metas'] as List? ?? const []).whereType<Map>())
        MetaPreview.fromJson(m.cast<String, dynamic>()),
    ];
  }

  Future<MetaDetail?> meta(String transportUrl, String type, String id) async {
    final json = await _get(_resourceUri(transportUrl, 'meta', type, id));
    final meta = json['meta'];
    return meta is Map
        ? MetaDetail.fromJson(meta.cast<String, dynamic>())
        : null;
  }

  Future<List<StreamSource>> streams(
    AddonManifest addon,
    String type,
    String id,
  ) async {
    final json = await _get(
      _resourceUri(addon.transportUrl, 'stream', type, id),
    );
    return [
      for (final s in (json['streams'] as List? ?? const []).whereType<Map>())
        StreamSource.fromJson(addon.name, s.cast<String, dynamic>()),
    ];
  }

  Future<List<SubtitleInfo>> subtitles(
    AddonManifest addon,
    String type,
    String id,
  ) async {
    final json = await _get(
      _resourceUri(addon.transportUrl, 'subtitles', type, id),
    );
    return [
      for (final s in (json['subtitles'] as List? ?? const []).whereType<Map>())
        SubtitleInfo.fromJson(addon.name, s.cast<String, dynamic>()),
    ];
  }

  Uri _resourceUri(
    String base,
    String resource,
    String type,
    String id, [
    Map<String, String> extra = const {},
  ]) {
    final enc = Uri.encodeComponent;
    final extraPath = extra.isEmpty
        ? ''
        : '/${extra.entries.map((e) => '${enc(e.key)}=${enc(e.value)}').join('&')}';
    return Uri.parse('$base/$resource/${enc(type)}/${enc(id)}$extraPath.json');
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final http.Response res;
    try {
      res = await _client.get(uri).timeout(_timeout);
    } catch (e) {
      throw MoviesException('Could not reach ${uri.host}.');
    }
    if (res.statusCode != 200) {
      throw MoviesException('${uri.host} answered ${res.statusCode}.');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map<String, dynamic>) {
      throw MoviesException('${uri.host} sent an unexpected response.');
    }
    return body;
  }
}
