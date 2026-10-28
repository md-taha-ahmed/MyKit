import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens links in specific installed apps (see `ExternalAppsChannel.kt`).
abstract final class ExternalApps {
  static const _channel = MethodChannel('com.mdtaha.mykit/external_apps');

  /// Opens a YouTube link in ReVanced / ReVanced Extended / YouTube, in that
  /// order, falling back to whatever handles the link (usually the browser).
  static Future<void> openYoutube(String url) async {
    String? opened;
    try {
      opened = await _channel.invokeMethod<String>('openYoutube', {'url': url});
    } on PlatformException {
      opened = null;
    }
    if (opened == null) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}
