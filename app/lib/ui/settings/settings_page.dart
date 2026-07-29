import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';

/// App / daemon lifecycle settings (not device pointer/scroll).
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.state,
    required this.onLoginAtStartup,
    required this.onStopDaemon,
    required this.onStartDaemon,
    this.detectingDevice = false,
  });

  final DeviceState state;
  final ValueChanged<bool> onLoginAtStartup;
  final VoidCallback onStopDaemon;
  final VoidCallback onStartDaemon;
  final bool detectingDevice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = state.daemonOnline;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Daemon', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          detectingDevice
              ? 'Starting · detecting device…'
              : online
              ? 'Running'
              : 'Stopped',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: online || detectingDevice
                ? theme.colorScheme.primary
                : theme.colorScheme.error,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          child: Column(
            children: [
              SwitchListTile(
                dense: true,
                title: const Text('Start at login'),
                value: state.loginAtStartup,
                onChanged: onLoginAtStartup,
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: Icon(
                  Icons.play_circle_outline,
                  color: online
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.35)
                      : theme.colorScheme.primary,
                ),
                title: const Text('Start daemon'),
                trailing: FilledButton(
                  onPressed: online || detectingDevice ? null : onStartDaemon,
                  child: const Text('Start'),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: Icon(
                  Icons.stop_circle_outlined,
                  color: online
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurface.withValues(alpha: 0.35),
                ),
                title: const Text('Stop daemon'),
                trailing: FilledButton.tonal(
                  onPressed: online && !detectingDevice ? onStopDaemon : null,
                  style: FilledButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: const Text('Stop'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Support diagnostics', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          child: Column(
            children: [
              ListTile(
                dense: true,
                title: const Text('Selected device'),
                subtitle: Text(
                  detectingDevice
                      ? 'Detecting device…\n'
                            'Scanning Bluetooth and USB HID interfaces'
                      : '${state.name}\n'
                            'Model ${state.modelId} · ${_transportLabel(state.connection)}',
                ),
                isThreeLine: true,
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                title: const Text('Runtime features'),
                subtitle: Text(
                  detectingDevice
                      ? 'Waiting for device capabilities'
                      : _capabilitySummary(state.capabilities),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                title: const Text('Programmable controls'),
                subtitle: Text(
                  detectingDevice
                      ? 'Waiting for device controls'
                      : state.controls.isEmpty
                      ? 'None reported'
                      : state.controls
                            .map(
                              (control) =>
                                  '${control.label} (${control.cidHex})',
                            )
                            .join(', '),
                ),
                trailing: TextButton.icon(
                  onPressed: detectingDevice
                      ? null
                      : () {
                          Clipboard.setData(
                            ClipboardData(text: _diagnosticsText(state)),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Diagnostics copied.'),
                            ),
                          );
                        },
                  icon: const Icon(Icons.copy, size: 17),
                  label: const Text('Copy'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _transportLabel(ConnectionType connection) =>
      switch (connection) {
        ConnectionType.ble => 'Bluetooth',
        ConnectionType.bolt => 'Logi Bolt',
        ConnectionType.usb => 'USB',
        ConnectionType.receiver => 'USB receiver',
        ConnectionType.unknown => 'Unknown transport',
      };

  static String _capabilitySummary(DeviceCapabilities capabilities) {
    final values = <String>[
      if (capabilities.battery) 'battery',
      if (capabilities.dpi != null)
        'DPI ${capabilities.dpi!.minimum}–${capabilities.dpi!.maximum}',
      if (capabilities.hiResWheel) 'high-resolution wheel',
      if (capabilities.smartShift) 'SmartShift',
      if (capabilities.thumbWheel) 'thumb wheel',
      if (capabilities.haptics) 'haptics',
      if (capabilities.forceSensing) 'force sensing',
    ];
    return values.isEmpty
        ? 'No adjustable features reported'
        : values.join(', ');
  }

  static String _diagnosticsText(DeviceState state) => [
    'LogiOptions diagnostics',
    'daemon=${state.daemonOnline ? "running" : "stopped"}',
    'connected=${state.connected}',
    'device=${state.name}',
    'deviceId=${state.deviceId ?? "none"}',
    'model=${state.modelId}',
    'transport=${_transportLabel(state.connection)}',
    'verification=${state.verified ? "verified" : "compatible-untested"}',
    'features=${_capabilitySummary(state.capabilities)}',
    'controls=${state.controls.map((item) => '${item.cidHex}:${item.label}').join(",")}',
    'accessibility=${state.accessibilityTrusted}',
  ].join('\n');
}
