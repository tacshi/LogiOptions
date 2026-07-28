import 'package:flutter/material.dart';

import '../../data/application_catalog.dart';
import '../../data/models.dart';
import '../../data/profile_controller.dart';

class AppsPage extends StatefulWidget {
  const AppsPage({
    super.key,
    required this.controller,
    required this.onEditProfile,
  });

  final ProfileController controller;
  final VoidCallback onEditProfile;

  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  final _catalog = const ApplicationCatalog();
  List<InstalledApplication> _installed = const [];
  bool _loadingApplications = false;

  @override
  void initState() {
    super.initState();
    _loadApplications();
  }

  Future<void> _loadApplications() async {
    if (_loadingApplications) return;
    setState(() => _loadingApplications = true);
    try {
      final applications = await _catalog.listInstalled();
      if (mounted) setState(() => _installed = applications);
    } catch (_) {
      // The app remains usable through Browse if discovery is unavailable.
    } finally {
      if (mounted) setState(() => _loadingApplications = false);
    }
  }

  InstalledApplication? _installedFor(String bundleId) {
    for (final application in _installed) {
      if (application.bundleId == bundleId) return application;
    }
    return null;
  }

  Future<void> _addApplication() async {
    if (_installed.isEmpty) await _loadApplications();
    if (!mounted) return;
    final selected = await showDialog<InstalledApplication>(
      context: context,
      builder: (context) => _ApplicationPickerDialog(
        applications: _installed,
        onBrowse: _catalog.browse,
      ),
    );
    if (selected == null) return;
    final existing =
        widget.controller.deviceConfiguration?.apps.containsKey(
          selected.bundleId,
        ) ??
        false;
    if (existing) {
      widget.controller.selectProfile(selected.bundleId);
      widget.onEditProfile();
      return;
    }
    await widget.controller.addApplication(
      bundleId: selected.bundleId,
      application: ApplicationIdentity(
        displayName: selected.name,
        path: selected.path,
      ),
      profile: _presetFor(selected.bundleId),
    );
    if (mounted) setState(() {});
  }

  ProfileSettings _presetFor(String bundleId) {
    const browsers = {
      'com.apple.Safari',
      'com.google.Chrome',
      'com.microsoft.edgemac',
      'org.mozilla.firefox',
    };
    if (browsers.contains(bundleId)) {
      return const ProfileSettings(
        thumbMode: 'actions',
        thumbLeftAction: {
          'type': 'keystroke',
          'keys': ['ctrl', 'shift', 'tab'],
        },
        thumbRightAction: {
          'type': 'keystroke',
          'keys': ['ctrl', 'tab'],
        },
      );
    }
    if (bundleId.contains('Photoshop') ||
        bundleId.contains('Premiere') ||
        bundleId.contains('FinalCut')) {
      return const ProfileSettings(
        thumbMode: 'actions',
        thumbLeftAction: {
          'type': 'keystroke',
          'keys': ['cmd', 'z'],
        },
        thumbRightAction: {
          'type': 'keystroke',
          'keys': ['cmd', 'shift', 'z'],
        },
      );
    }
    return const ProfileSettings();
  }

  Future<void> _delete(String bundleId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $name profile?'),
        content: const Text(
          'The application will return to the Global assignments and settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    widget.controller.selectProfile(bundleId);
    await widget.controller.deleteSelectedApplication();
    if (mounted) setState(() {});
  }

  Future<void> _duplicate(String bundleId) async {
    if (_installed.isEmpty) await _loadApplications();
    if (!mounted) return;
    final existingIds =
        widget.controller.deviceConfiguration?.apps.keys.toSet() ?? {};
    final selected = await showDialog<InstalledApplication>(
      context: context,
      builder: (context) => _ApplicationPickerDialog(
        applications: _installed
            .where((application) => !existingIds.contains(application.bundleId))
            .toList(),
        onBrowse: _catalog.browse,
      ),
    );
    if (selected == null) return;
    if (existingIds.contains(selected.bundleId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That application already has a profile.'),
        ),
      );
      return;
    }
    final source =
        widget.controller.deviceConfiguration?.apps[bundleId] ??
        const ProfileSettings();
    await widget.controller.addApplication(
      bundleId: selected.bundleId,
      application: ApplicationIdentity(
        displayName: selected.name,
        path: selected.path,
      ),
      profile: source,
    );
    if (mounted) setState(() {});
  }

  Future<void> _applyPreset(String bundleId, String name) async {
    final preset = await showDialog<ProfileSettings>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Preset for $name'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(
              context,
              const ProfileSettings(
                thumbMode: 'actions',
                thumbLeftAction: {
                  'type': 'keystroke',
                  'keys': ['ctrl', 'shift', 'tab'],
                },
                thumbRightAction: {
                  'type': 'keystroke',
                  'keys': ['ctrl', 'tab'],
                },
              ),
            ),
            child: const ListTile(
              leading: Icon(Icons.language),
              title: Text('Browser navigation'),
              subtitle: Text('Previous and next tab on the thumb wheel'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(
              context,
              const ProfileSettings(
                thumbMode: 'actions',
                thumbLeftAction: {
                  'type': 'keystroke',
                  'keys': ['cmd', 'z'],
                },
                thumbRightAction: {
                  'type': 'keystroke',
                  'keys': ['cmd', 'shift', 'z'],
                },
              ),
            ),
            child: const ListTile(
              leading: Icon(Icons.palette_outlined),
              title: Text('Creative editing'),
              subtitle: Text('Undo and redo on the thumb wheel'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(
              context,
              const ProfileSettings(
                thumbMode: 'actions',
                thumbLeftAction: {
                  'type': 'keystroke',
                  'keys': ['cmd', 'c'],
                },
                thumbRightAction: {
                  'type': 'keystroke',
                  'keys': ['cmd', 'v'],
                },
              ),
            ),
            child: const ListTile(
              leading: Icon(Icons.content_copy),
              title: Text('Productivity'),
              subtitle: Text('Copy and paste on the thumb wheel'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, const ProfileSettings()),
            child: const ListTile(
              leading: Icon(Icons.restart_alt),
              title: Text('Clear overrides'),
              subtitle: Text('Inherit every setting from Global'),
            ),
          ),
        ],
      ),
    );
    if (preset == null) return;
    widget.controller.selectProfile(bundleId);
    widget.controller.updateProfile(preset);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configuration = widget.controller.deviceConfiguration;
    final ids = configuration?.apps.keys.toList() ?? [];
    ids.sort((left, right) {
      final leftName =
          configuration?.applicationMetadata[left]?.displayName ?? left;
      final rightName =
          configuration?.applicationMetadata[right]?.displayName ?? right;
      return leftName.compareTo(rightName);
    });

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Application profiles',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Override any button, pointer, or wheel setting per app. '
                    'Unchanged values inherit from Global.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: widget.controller.state.deviceId == null
                  ? null
                  : _addApplication,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add application'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.public)),
            title: const Text('Global'),
            subtitle: const Text('Default for every application'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              widget.controller.selectProfile(null);
              widget.onEditProfile();
            },
          ),
        ),
        for (final id in ids)
          _ApplicationProfileTile(
            bundleId: id,
            identity:
                configuration?.applicationMetadata[id] ??
                ApplicationIdentity(displayName: id),
            installed: _installedFor(id),
            overrideCount: _overrideCount(configuration!.apps[id]!),
            onEdit: () {
              widget.controller.selectProfile(id);
              widget.onEditProfile();
            },
            onDelete: () => _delete(
              id,
              configuration.applicationMetadata[id]?.displayName ?? id,
            ),
            onDuplicate: () => _duplicate(id),
            onPreset: () => _applyPreset(
              id,
              configuration.applicationMetadata[id]?.displayName ?? id,
            ),
          ),
        if (ids.isEmpty)
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            child: const Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                children: [
                  Icon(Icons.apps, size: 38),
                  SizedBox(height: 10),
                  Text(
                    'No application profiles yet',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Add an installed application or browse to an app bundle.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        if (_loadingApplications)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  int _overrideCount(ProfileSettings profile) {
    var count = profile.buttons.length;
    count += [
      profile.dpi,
      profile.smartShiftEnabled,
      profile.smartShiftThreshold,
      profile.hiresWheel,
      profile.invertWheel,
      profile.scrollSpeed,
      profile.thumbMode,
      profile.thumbSpeed,
      profile.thumbInvert,
      profile.thumbLeftAction,
      profile.thumbRightAction,
    ].where((value) => value != null).length;
    return count;
  }
}

class _ApplicationProfileTile extends StatelessWidget {
  const _ApplicationProfileTile({
    required this.bundleId,
    required this.identity,
    required this.installed,
    required this.overrideCount,
    required this.onEdit,
    required this.onDelete,
    required this.onDuplicate,
    required this.onPreset,
  });

  final String bundleId;
  final ApplicationIdentity identity;
  final InstalledApplication? installed;
  final int overrideCount;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onPreset;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: ListTile(
      leading: CircleAvatar(
        backgroundImage: installed?.icon == null
            ? null
            : MemoryImage(installed!.icon!),
        child: installed?.icon == null
            ? Text(identity.displayName.characters.first)
            : null,
      ),
      title: Text(identity.displayName),
      subtitle: Text(
        '$overrideCount override${overrideCount == 1 ? '' : 's'} · $bundleId',
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Profile actions',
        onSelected: (value) {
          switch (value) {
            case 'duplicate':
              onDuplicate();
            case 'preset':
              onPreset();
            case 'delete':
              onDelete();
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'duplicate', child: Text('Duplicate…')),
          PopupMenuItem(value: 'preset', child: Text('Apply preset…')),
          PopupMenuDivider(),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: onEdit,
    ),
  );
}

class _ApplicationPickerDialog extends StatefulWidget {
  const _ApplicationPickerDialog({
    required this.applications,
    required this.onBrowse,
  });

  final List<InstalledApplication> applications;
  final Future<InstalledApplication?> Function() onBrowse;

  @override
  State<_ApplicationPickerDialog> createState() =>
      _ApplicationPickerDialogState();
}

class _ApplicationPickerDialogState extends State<_ApplicationPickerDialog> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final applications = widget.applications.where((application) {
      return normalized.isEmpty ||
          application.name.toLowerCase().contains(normalized) ||
          application.bundleId.toLowerCase().contains(normalized);
    }).toList();
    return AlertDialog(
      title: const Text('Add application'),
      content: SizedBox(
        width: 560,
        height: 480,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search installed applications',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: applications.isEmpty
                  ? const Center(child: Text('No matching applications'))
                  : ListView.builder(
                      itemCount: applications.length,
                      itemBuilder: (context, index) {
                        final application = applications[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: application.icon == null
                                ? null
                                : MemoryImage(application.icon!),
                            child: application.icon == null
                                ? Text(application.name.characters.first)
                                : null,
                          ),
                          title: Text(application.name),
                          subtitle: Text(application.bundleId),
                          onTap: () => Navigator.pop(context, application),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            final application = await widget.onBrowse();
            if (application != null && context.mounted) {
              Navigator.pop(context, application);
            }
          },
          icon: const Icon(Icons.folder_open),
          label: const Text('Browse…'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
