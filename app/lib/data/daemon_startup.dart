import 'dart:async';

import 'models.dart';

/// Polls through the gap between RPC startup and HID device discovery.
class DaemonStartupWaiter {
  const DaemonStartupWaiter._();

  static Future<void> waitForDiscovery({
    required Future<void> Function() refresh,
    required DeviceState Function() readState,
    Duration interval = const Duration(milliseconds: 250),
    int maxAttempts = 16,
  }) async {
    assert(maxAttempts > 0);
    for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
      await refresh();
      final state = readState();
      if (state.connected) return;
      if (state.daemonOnline && !state.permissionsOk) return;
      if (attempt + 1 < maxAttempts && interval > Duration.zero) {
        await Future<void>.delayed(interval);
      }
    }
  }
}
