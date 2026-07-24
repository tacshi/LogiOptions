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
      padding: const EdgeInsets.all(24),
      children: [
        Text('Daemon', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          online ? 'Status: running' : 'Status: stopped',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: online
                ? theme.colorScheme.primary
                : theme.colorScheme.error,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Start daemon at login'),
                subtitle: const Text(
                  'Keeps remaps and scroll working after you close the app '
                  '(LaunchAgent, no Dock icon).',
                ),
                value: state.loginAtStartup,
                onChanged: onLoginAtStartup,
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.play_circle_outline,
                  color: online
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.35)
                      : theme.colorScheme.primary,
                ),
                title: const Text('Start background daemon'),
                subtitle: Text(
                  online
                      ? 'Already running.'
                      : 'Starts remaps, gestures, and host scroll.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: FilledButton(
                  onPressed: online ? null : onStartDaemon,
                  child: const Text('Start'),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.stop_circle_outlined,
                  color: online
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurface.withValues(alpha: 0.35),
                ),
                title: const Text('Stop background daemon'),
                subtitle: Text(
                  online
                      ? 'Restores native scroll; remaps stop until you Start again.'
                      : 'Daemon is not running.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
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
        const SizedBox(height: 16),
        Text(
          'Closing the main window quits the UI (Dock icon goes away) but leaves '
          'the daemon running so scroll and remaps keep working. Use Stop only when '
          'you want native OS scroll and no remaps.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
