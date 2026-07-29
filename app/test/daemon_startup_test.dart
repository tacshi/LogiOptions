import 'package:flutter_test/flutter_test.dart';
import 'package:logi_options/data/daemon_startup.dart';
import 'package:logi_options/data/models.dart';

void main() {
  test(
    'keeps polling after RPC is ready until device discovery completes',
    () async {
      var state = const DeviceState();
      var refreshes = 0;

      await DaemonStartupWaiter.waitForDiscovery(
        refresh: () async {
          refreshes += 1;
          state = switch (refreshes) {
            1 => const DeviceState(daemonOnline: true),
            _ => const DeviceState(
              daemonOnline: true,
              connected: true,
              name: 'MX Master 3S',
              deviceId: 'ble:mx-master-3s',
              connection: ConnectionType.ble,
            ),
          };
        },
        readState: () => state,
        interval: Duration.zero,
        maxAttempts: 3,
      );

      expect(refreshes, 2);
      expect(state.connected, isTrue);
      expect(state.name, 'MX Master 3S');
    },
  );
}
