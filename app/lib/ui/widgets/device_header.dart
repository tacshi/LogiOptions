import 'package:flutter/material.dart';

import '../../data/models.dart';

class DeviceHeader extends StatelessWidget {
  const DeviceHeader({super.key, required this.state});

  final DeviceState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connectionLabel = switch (state.connection) {
      ConnectionType.ble => 'Bluetooth',
      ConnectionType.bolt => 'Logi Bolt',
      ConnectionType.unknown => state.connected ? 'Connected' : 'Not connected',
    };

    final title = state.connected
        ? (state.name == 'USB Receiver' ? 'MX Master 3S' : state.name)
        : 'No device';

    return Material(
      elevation: 0,
      color: theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Row(
            children: [
              _DeviceAvatar(connected: state.connected),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      state.connected
                          ? connectionLabel
                          : 'Connect a supported Logitech mouse (BLE or Bolt)',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _BatteryChip(
                percent: state.batteryPercent,
                charging: state.charging,
              ),
              const SizedBox(width: 12),
              _StatusDot(
                ok: state.daemonOnline,
                label: state.daemonOnline ? 'Daemon' : 'No daemon',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceAvatar extends StatelessWidget {
  const _DeviceAvatar({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Portrait device art — use a taller tile + contain so the mouse is not cropped.
    return Container(
      width: 52,
      height: 64,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Image.asset(
        connected
            // Full-body product render (not crop-heavy side art).
            ? 'assets/devices/mx_master_3s/front_core.png'
            : 'assets/brand/logi_logo.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/brand/logi_logo.png',
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(
            Icons.mouse,
            color: theme.colorScheme.onPrimaryContainer,
            size: 30,
          ),
        ),
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
