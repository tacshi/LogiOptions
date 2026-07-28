import 'package:flutter/services.dart';

/// Native helpers for daemon process lifecycle when the RPC socket is down.
class DaemonLifecycle {
  static const _channel = MethodChannel('com.logioptions/daemon');

  /// Launch the embedded LogiOptionsDaemon (Settings → Start after Stop).
  Future<bool> start({bool requestAccessibility = false}) async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('start', {
        'requestAccessibility': requestAccessibility,
      });
      return m?['ok'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }
}
