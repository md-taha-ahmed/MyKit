import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// Bridge to the native Android countdown home-screen widget.
///
/// The widget lives in
/// `android/app/src/main/kotlin/com/mdtaha/mykit/widgets/` and renders the
/// ring natively, so it stays up to date even when the app is closed.
class CountdownHomeWidgetService {
  static const _androidProvider =
      'com.mdtaha.mykit.widgets.CountdownWidgetProvider';
  static const _countdownsKey = 'countdowns';
  static const _pendingPinKey = 'pending_pin_countdown_id';

  static const uriScheme = 'mykit';
  static const uriHost = 'countdown';

  Future<void> sync(List<Map<String, dynamic>> countdownsJson) async {
    try {
      await HomeWidget.saveWidgetData<String>(
        _countdownsKey,
        jsonEncode(countdownsJson),
      );
      await HomeWidget.updateWidget(qualifiedAndroidName: _androidProvider);
    } catch (e) {
      debugPrint('Countdown widget sync failed: $e');
    }
  }

  Future<bool> canPinWidget() async =>
      await HomeWidget.isRequestPinWidgetSupported() ?? false;

  /// Asks the launcher to add a widget showing [countdownId].
  Future<void> pinWidget(String countdownId) async {
    // The native provider binds the next unconfigured widget to this id.
    await HomeWidget.saveWidgetData<String>(_pendingPinKey, countdownId);
    await HomeWidget.requestPinWidget(qualifiedAndroidName: _androidProvider);
  }

  Future<Uri?> initialLaunchUri() =>
      HomeWidget.initiallyLaunchedFromHomeWidget();

  Stream<Uri?> launchUris() => HomeWidget.widgetClicked;

  /// Maps a widget launch uri (`mykit://countdown/<id>` or
  /// `mykit://countdown/new`) to an in-app location.
  String? locationForLaunchUri(Uri? uri) {
    if (uri == null || uri.scheme != uriScheme || uri.host != uriHost) {
      return null;
    }
    final segments = uri.pathSegments;
    if (segments.isEmpty) return '/countdown';
    return '/countdown/${segments.first}';
  }
}
