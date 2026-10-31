import 'package:flutter/services.dart';

/// Android side (`android/.../setup/SetupChannel.kt`).
class SetupNative {
  static const _channel = MethodChannel('com.mdtaha.mykit/setup');

  Future<({bool batteryUnrestricted, bool autofill})> status() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('status');
      return (
        batteryUnrestricted: m?['batteryUnrestricted'] == true,
        autofill: m?['autofill'] == true,
      );
    } catch (_) {
      return (batteryUnrestricted: false, autofill: false);
    }
  }

  /// The system "let MyKit run in the background?" dialog.
  Future<void> requestBattery() => _channel.invokeMethod('requestBattery');

  /// Android's "choose your autofill service" screen.
  Future<void> requestAutofill() => _channel.invokeMethod('requestAutofill');

  Future<void> openAppSettings() => _channel.invokeMethod('openAppSettings');
}
