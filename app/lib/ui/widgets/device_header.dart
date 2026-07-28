import 'package:flutter/material.dart';

import '../../data/models.dart';
import 'device_illustration.dart';

class DeviceHeader extends StatelessWidget {
  const DeviceHeader({
    super.key,
    required this.state,
    required this.devices,
    required this.onDeviceSelected,
    required this.onRescan,
  });

  final DeviceState state;
  final List<DeviceDescriptor> devices;
  final ValueChanged<String> onDeviceSelected;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connectionLabel = switch (state.connection) {
      ConnectionType.ble => 'Bluetooth',
      ConnectionType.bolt => 'Logi Bolt',
      ConnectionType.usb => 'USB',
      ConnectionType.receiver => 'USB receiver',
      ConnectionType.unknown => state.connected ? 'Connected' : 'Not connected',
    };

    return Material(
      elevation: 0,
      color: theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              _DeviceAvatar(
                connected: state.connected,
                artworkKey: state.artworkKey,
                modelId: state.modelId,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            state.deviceId == null ? 'No device' : state.name,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (devices.isNotEmpty)
                          PopupMenuButton<String>(
                            tooltip: 'Select device',
                            icon: const Icon(Icons.expand_more, size: 20),
                            onSelected: onDeviceSelected,
                            itemBuilder: (context) => [
                              for (final device in devices)
                                PopupMenuItem(
                                  value: device.id,
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 24,
                                        height: 30,
                                        child: Opacity(
                                          opacity: device.connected ? 1 : 0.45,
                                          child: DeviceIllustration(
                                            artworkKey: device.artworkKey,
                                            modelId: device.modelId,
                                            compact: true,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(child: Text(device.name)),
                                      if (device.id == state.deviceId)
                                        const Icon(Icons.check, size: 18),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                    if (state.deviceId != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            connectionLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _VerificationBadge(verified: state.verified),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              _BatteryChip(
                percent: state.batteryPercent,
                charging: state.charging,
              ),
              const SizedBox(width: 10),
              _StatusDot(
                ok: state.daemonOnline,
                label: state.daemonOnline ? 'Daemon' : 'No daemon',
              ),
              IconButton(
                tooltip: 'Rescan devices',
                onPressed: onRescan,
                icon: const Icon(Icons.refresh, size: 19),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceAvatar extends StatelessWidget {
  const _DeviceAvatar({
    required this.connected,
    required this.artworkKey,
    required this.modelId,
  });

  final bool connected;
  final String artworkKey;
  final String modelId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Portrait device art — use a taller tile + contain so the mouse is not cropped.
    return Container(
      width: 44,
      height: 52,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.65,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: connected
          ? DeviceIllustration(
              artworkKey: artworkKey,
              modelId: modelId,
              compact: true,
            )
          : Opacity(
              opacity: 0.45,
              child: DeviceIllustration(
                artworkKey: artworkKey,
                modelId: modelId,
                compact: true,
              ),
            ),
    );
  }
}

class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({required this.verified});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: verified
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        verified ? 'Verified' : 'Compatible—untested',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _BatteryChip extends StatelessWidget {
  const _BatteryChip({required this.percent, required this.charging});

  final int? percent;
  final bool charging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = percent == null ? '—%' : '$percent%';
    final low = percent != null && percent! <= 15;
    return Chip(
      avatar: Icon(
        charging
            ? Icons.battery_charging_full
            : low
            ? Icons.battery_alert
            : Icons.battery_std,
        size: 18,
        color: low ? theme.colorScheme.error : theme.colorScheme.primary,
      ),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.ok, required this.label});

  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ok ? Colors.green : Colors.orange,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
