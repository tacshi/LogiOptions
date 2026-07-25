import 'package:flutter/material.dart';

import '../../data/models.dart';

class AppsPage extends StatelessWidget {
  const AppsPage({super.key, required this.state});

  final DeviceState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final apps = [
      (name: 'Global', id: 'global'),
      (name: 'Safari', id: 'com.apple.Safari'),
      (name: 'Google Chrome', id: 'com.google.Chrome'),
      (name: 'Terminal', id: 'com.apple.Terminal'),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Application profiles', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        for (final app in apps)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 16,
                child: Text(app.name.characters.first),
              ),
              title: Text(app.name),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Profile editor for ${app.name} — Phase 2/3'),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('App picker will scan /Applications')),
            );
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add application'),
        ),
      ],
    );
  }
}
