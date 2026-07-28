import 'package:flutter/material.dart';

import '../../data/profile_controller.dart';

class ProfileSelector extends StatelessWidget {
  const ProfileSelector({super.key, required this.controller});

  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    final configuration = controller.deviceConfiguration;
    final entries = controller.profileIds;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            const Icon(Icons.tune, size: 18),
            const SizedBox(width: 8),
            Text('Profile', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: controller.selectedBundleId ?? '__global__',
                isDense: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                ),
                items: [
                  const DropdownMenuItem(
                    value: '__global__',
                    child: Text('Global'),
                  ),
                  for (final id in entries.whereType<String>())
                    DropdownMenuItem(
                      value: id,
                      child: Text(
                        configuration?.applicationMetadata[id]?.displayName ??
                            id,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => controller.selectProfile(
                  value == '__global__' ? null : value,
                ),
              ),
            ),
            if (controller.selectedBundleId != null) ...[
              const SizedBox(width: 10),
              const Icon(Icons.account_tree_outlined, size: 17),
              const SizedBox(width: 5),
              Text(
                'Inherits Global',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (controller.writing) ...[
              const SizedBox(width: 12),
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
