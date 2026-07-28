import 'package:flutter/material.dart';

import '../../data/application_catalog.dart';
import '../../data/models.dart';
import '../../data/profile_controller.dart';
import '../widgets/device_canvas.dart';
import '../widgets/key_capture_dialog.dart';
import '../widgets/profile_selector.dart';

class ButtonsPage extends StatefulWidget {
  const ButtonsPage({super.key, required this.controller});

  final ProfileController controller;

  @override
  State<ButtonsPage> createState() => _ButtonsPageState();
}

class _ButtonsPageState extends State<ButtonsPage> {
  final _applicationCatalog = const ApplicationCatalog();
  DeviceControl? _selected;

  static const _dirOrder = <(String key, String title)>[
    ('click', 'Click'),
    ('up', 'Up'),
    ('down', 'Down'),
    ('left', 'Left'),
    ('right', 'Right'),
  ];

  DeviceControl? get selected {
    final controls = widget.controller.state.controls;
    if (_selected != null &&
        controls.any((control) => control.cid == _selected!.cid)) {
      return controls.firstWhere((control) => control.cid == _selected!.cid);
    }
    if (controls.isEmpty) return null;
    return controls.firstWhere(
      (control) => control.cid == 0xC3,
      orElse: () => controls.first,
    );
  }

  Map<String, dynamic>? _resolvedAction(DeviceControl control) =>
      widget.controller.resolvedProfile.buttons[control.cidHex];

  bool _inherits(DeviceControl control) =>
      widget.controller.selectedBundleId != null &&
      !_containsCid(widget.controller.editableProfile.buttons, control.cid);

  bool _containsCid(Map<String, Map<String, dynamic>> buttons, int cid) =>
      buttons.keys.any((key) {
        final normalized = key.toLowerCase().replaceFirst('0x', '');
        return int.tryParse(normalized, radix: 16) == cid;
      });

  void _assign(DeviceControl control, Map<String, dynamic> action) {
    widget.controller.updateButton(control, action);
  }

  void _setInherit(DeviceControl control, bool inherit) {
    final buttons = Map<String, Map<String, dynamic>>.from(
      widget.controller.editableProfile.buttons,
    );
    buttons.removeWhere((key, _) {
      final normalized = key.toLowerCase().replaceFirst('0x', '');
      return int.tryParse(normalized, radix: 16) == control.cid;
    });
    if (!inherit) {
      buttons[control.cidHex] = Map<String, dynamic>.from(
        _resolvedAction(control) ?? const {'type': 'none'},
      );
    }
    widget.controller.updateProfile(
      widget.controller.editableProfile.copyWith(buttons: buttons),
    );
  }

  Map<String, String> _gestureDirections(Map<String, dynamic>? action) {
    const defaults = {
      'click': 'Mission Control',
      'up': 'Mission Control',
      'down': 'App Exposé',
      'left': 'Previous Desktop',
      'right': 'Next Desktop',
    };
    if (action?['type'] != 'gesture') return defaults;
    return {
      for (final key in defaults.keys)
        key: actionStorageKeyFromJson(
          action?[key] is Map
              ? Map<String, dynamic>.from(action![key] as Map)
              : null,
        ),
    };
  }

  Future<void> _pickCustomForControl(DeviceControl control) async {
    final storage = actionStorageKeyFromJson(_resolvedAction(control));
    final existing = ActionBinding.fromStorage(storage);
    final keys = await showKeyCaptureDialog(
      context,
      initial: existing.customKeys,
    );
    if (keys == null || keys.isEmpty || !mounted) return;
    _assign(control, ActionBinding.custom(keys).toJson());
  }

  Future<void> _pickCustomForDirection(
    DeviceControl control,
    String key,
    Map<String, String> directions,
  ) async {
    final existing = ActionBinding.fromStorage(directions[key] ?? '');
    final keys = await showKeyCaptureDialog(
      context,
      initial: existing.customKeys,
    );
    if (keys == null || keys.isEmpty || !mounted) return;
    directions[key] = ActionBinding.custom(keys).storageKey;
    _assign(
      control,
      actionJsonForLabel('Gesture (4-way)', gestureDirections: directions),
    );
  }

  Future<void> _pickOpenTarget(DeviceControl control, String action) async {
    switch (action) {
      case 'Open application…':
        final application = await _applicationCatalog.browse();
        if (application == null || !mounted) return;
        _assign(control, {
          'type': 'open',
          'kind': 'app',
          'value': application.path,
        });
        return;
      case 'Open file…':
        final path = await _applicationCatalog.browseFile();
        if (path == null || path.isEmpty || !mounted) return;
        _assign(control, {'type': 'open', 'kind': 'file', 'value': path});
        return;
      case 'Open URL…':
        final current = _resolvedAction(control);
        final initial = current?['type'] == 'open' && current?['kind'] == 'url'
            ? (current?['value']?.toString() ?? '')
            : '';
        final value = await _showUrlDialog(initial);
        if (value == null || !mounted) return;
        _assign(control, {'type': 'open', 'kind': 'url', 'value': value});
        return;
    }
  }

  Future<String?> _showUrlDialog(String initial) async {
    final text = TextEditingController(text: initial);
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Open URL'),
          content: TextField(
            controller: text,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Web address',
              hintText: 'https://example.com',
              errorText: error,
            ),
            keyboardType: TextInputType.url,
            onSubmitted: (_) {
              final normalized = _normalizedUrl(text.text);
              if (normalized == null) {
                setDialogState(() => error = 'Enter a valid web address.');
              } else {
                Navigator.pop(context, normalized);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final normalized = _normalizedUrl(text.text);
                if (normalized == null) {
                  setDialogState(() => error = 'Enter a valid web address.');
                } else {
                  Navigator.pop(context, normalized);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    text.dispose();
    return result;
  }

  String? _normalizedUrl(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;
    final candidate = value.contains('://') ? value : 'https://$value';
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return null;
    }
    return uri.toString();
  }

  List<String> _options(String current, {required bool topLevel}) {
    final options = List<String>.from(
      topLevel ? kButtonActionLabels : kSimpleActionLabels,
    );
    if (!widget.controller.state.capabilities.smartShift) {
      options.remove('SmartShift toggle');
    }
    if (current.startsWith('custom:') && !options.contains(current)) {
      options.insert(options.length - 1, current);
    }
    return options;
  }

  String _entryLabel(String storage) => storage.startsWith('custom:')
      ? ActionBinding.fromStorage(storage).displayLabel
      : storage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.controller.state;
    final selected = this.selected;
    final action = selected == null ? null : _resolvedAction(selected);
    final storage = actionStorageKeyFromJson(action);
    final directions = _gestureDirections(action);

    return Column(
      children: [
        ProfileSelector(controller: widget.controller),
        if (widget.controller.error != null)
          _ErrorStrip(message: widget.controller.error!),
        Expanded(
          child: state.controls.isEmpty
              ? const Center(
                  child: Text(
                    'This device does not expose programmable controls.',
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: DeviceCanvas(
                          state: state,
                          selected: selected,
                          onSelect: (control) =>
                              setState(() => _selected = control),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                        child: Card(
                          elevation: 0,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: selected == null
                                ? const Center(
                                    child: Text(
                                      'Select a control on the device',
                                    ),
                                  )
                                : SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          selected.label,
                                          style: theme.textTheme.titleLarge,
                                        ),
                                        if (widget
                                                .controller
                                                .selectedBundleId !=
                                            null)
                                          SwitchListTile(
                                            contentPadding: EdgeInsets.zero,
                                            dense: true,
                                            title: const Text('Use Global'),
                                            subtitle: _inherits(selected)
                                                ? Text(
                                                    'Resolved: ${_entryLabel(storage)}',
                                                  )
                                                : null,
                                            value: _inherits(selected),
                                            onChanged: (value) =>
                                                _setInherit(selected, value),
                                          ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Action',
                                          style: theme.textTheme.titleSmall,
                                        ),
                                        const SizedBox(height: 6),
                                        _ActionDropdown(
                                          key: ValueKey(
                                            'main-${selected.cid}-$storage',
                                          ),
                                          value: storage,
                                          options: _options(
                                            storage,
                                            topLevel: true,
                                          ),
                                          labelFor: _entryLabel,
                                          enabled: !_inherits(selected),
                                          onSelected: (value) async {
                                            if (value == 'Custom shortcut…') {
                                              await _pickCustomForControl(
                                                selected,
                                              );
                                              return;
                                            }
                                            if (value == 'Open application…' ||
                                                value == 'Open file…' ||
                                                value == 'Open URL…') {
                                              await _pickOpenTarget(
                                                selected,
                                                value,
                                              );
                                              return;
                                            }
                                            _assign(
                                              selected,
                                              actionJsonForLabel(
                                                value,
                                                gestureDirections: directions,
                                              ),
                                            );
                                          },
                                        ),
                                        if (action?['type'] == 'open' &&
                                            (action?['value']?.toString() ?? '')
                                                .isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                            ),
                                            child: Text(
                                              action!['value'].toString(),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ),
                                        if (storage.startsWith('custom:'))
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: TextButton.icon(
                                              onPressed: _inherits(selected)
                                                  ? null
                                                  : () => _pickCustomForControl(
                                                      selected,
                                                    ),
                                              icon: const Icon(
                                                Icons.keyboard,
                                                size: 18,
                                              ),
                                              label: Text(
                                                'Edit ${_entryLabel(storage)}',
                                              ),
                                            ),
                                          ),
                                        if (storage == 'Gesture (4-way)' &&
                                            !_inherits(selected)) ...[
                                          const SizedBox(height: 16),
                                          Text(
                                            'Directions',
                                            style: theme.textTheme.titleSmall,
                                          ),
                                          const SizedBox(height: 8),
                                          for (final entry in _dirOrder) ...[
                                            Text(
                                              entry.$2,
                                              style: theme.textTheme.labelLarge,
                                            ),
                                            const SizedBox(height: 4),
                                            _ActionDropdown(
                                              key: ValueKey(
                                                'dir-${entry.$1}-${directions[entry.$1]}',
                                              ),
                                              value: directions[entry.$1]!,
                                              options: _options(
                                                directions[entry.$1]!,
                                                topLevel: false,
                                              ),
                                              labelFor: _entryLabel,
                                              onSelected: (value) async {
                                                if (value ==
                                                    'Custom shortcut…') {
                                                  await _pickCustomForDirection(
                                                    selected,
                                                    entry.$1,
                                                    directions,
                                                  );
                                                  return;
                                                }
                                                directions[entry.$1] = value;
                                                _assign(
                                                  selected,
                                                  actionJsonForLabel(
                                                    'Gesture (4-way)',
                                                    gestureDirections:
                                                        directions,
                                                  ),
                                                );
                                              },
                                            ),
                                            const SizedBox(height: 8),
                                          ],
                                        ],
                                        if (!state.daemonOnline)
                                          Text(
                                            'Start the daemon to apply remaps.',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color:
                                                      theme.colorScheme.error,
                                                ),
                                          ),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ActionDropdown extends StatelessWidget {
  const _ActionDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.labelFor,
    required this.onSelected,
    this.enabled = true,
  });

  final String value;
  final List<String> options;
  final String Function(String) labelFor;
  final ValueChanged<String> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<String>(
      initialSelection: value,
      enabled: enabled,
      expandedInsets: EdgeInsets.zero,
      dropdownMenuEntries: [
        for (final option in options)
          DropdownMenuEntry(value: option, label: labelFor(option)),
      ],
      onSelected: (value) {
        if (value != null) onSelected(value);
      },
    );
  }
}

class _ErrorStrip extends StatelessWidget {
  const _ErrorStrip({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    ),
  );
}
