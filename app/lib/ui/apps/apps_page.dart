import 'package:flutter/material.dart';

import '../../data/models.dart';

class AppsPage extends StatelessWidget {
  const AppsPage({super.key, required this.state});

  final DeviceState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final apps = [
      (name: 'Global', id: 'global', subtitle: 'Default for all apps'),
      (name: 'Safari', id: 'com.apple.Safari', subtitle: 'Uses global until customized'),
      (name: 'Google Chrome', id: 'com.google.Chrome', subtitle: 'Uses global until customized'),
      (name: 'Terminal', id: 'com.apple.Terminal', subtitle: 'Uses global until customized'),
    ];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Application profiles', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'When an app is frontmost, its profile overrides button actions. '
          'DPI and SmartShift stay global unless you add per-app overrides later.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        for (final app in apps)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                child: Text(app.name.characters.first),
              ),
              title: Text(app.name),
              subtitle: Text(app.subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Profile editor for ${app.name} — Phase 2/3'),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('App picker will scan /Applications')),
            );
          },
          icon: const Icon(Icons.add),
          label: const Text('Add application'),
        ),
      ],
    );
  }
}
