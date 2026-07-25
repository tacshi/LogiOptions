import 'package:flutter/material.dart';

import '../../data/models.dart';

/// App / daemon lifecycle settings (not device pointer/scroll).
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.state,
    required this.onLoginAtStartup,
    required this.onStopDaemon,
    required this.onStartDaemon,
  });

  final DeviceState state;
  final ValueChanged<bool> onLoginAtStartup;
  final VoidCallback onStopDaemon;
  final VoidCallback onStartDaemon;

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
          online ? 'Running' : 'Stopped',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: online
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
                  onPressed: online ? null : onStartDaemon,
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
                  onPressed: online ? onStopDaemon : null,
                  style: FilledButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: const Text('Stop'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
