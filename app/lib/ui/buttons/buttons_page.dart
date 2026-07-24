import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../widgets/device_canvas.dart';
import '../widgets/key_capture_dialog.dart';

class ButtonsPage extends StatefulWidget {
  const ButtonsPage({
    super.key,
    required this.state,
    required this.onAssign,
  });

  final DeviceState state;

  /// Full action JSON for the control (simple or gesture).
  final void Function(ControlId control, Map<String, dynamic> action) onAssign;

  @override
  State<ButtonsPage> createState() => _ButtonsPageState();
}

class _ButtonsPageState extends State<ButtonsPage> {
  ControlId? _selected = ControlId.gesture;

  /// Top-level control → storage key (preset or custom:…).
  final Map<ControlId, String> _assignments = {
    ControlId.middle: 'Middle click',
    ControlId.back: 'Back',
    ControlId.forward: 'Forward',
    ControlId.gesture: 'Gesture (4-way)',
    ControlId.modeShift: 'SmartShift toggle',
  };

  /// Gesture directions → storage key (preset or custom:ctrl+left).
  final Map<String, String> _gestureDirs = {
    'click': 'Mission Control',
    'up': 'Mission Control',
    'down': 'App Exposé',
    'left': 'Previous Desktop',
    'right': 'Next Desktop',
  };

  static const _dirOrder = <(String key, String title)>[
    ('click', 'Click'),
    ('up', 'Up'),
    ('down', 'Down'),
    ('left', 'Left'),
    ('right', 'Right'),
  ];

  void _pushAssignment(ControlId control) {
    final label = _assignments[control] ?? 'Disabled';
    if (label == 'Custom shortcut…') return;
    final json = actionJsonForLabel(
      label,
      gestureDirections: control == ControlId.gesture ? _gestureDirs : null,
    );
    widget.onAssign(control, json);
  }

  Future<void> _pickCustomForControl(ControlId control) async {
    final existing = ActionBinding.fromStorage(_assignments[control] ?? '');
    final keys = await showKeyCaptureDialog(
      context,
      initial: existing.customKeys,
    );
    if (keys == null || keys.isEmpty || !mounted) return;
    final binding = ActionBinding.custom(keys);
    setState(() => _assignments[control] = binding.storageKey);
    widget.onAssign(control, binding.toJson());
  }

  Future<void> _pickCustomForDirection(String dirKey) async {
    final existing = ActionBinding.fromStorage(_gestureDirs[dirKey] ?? '');
    final keys = await showKeyCaptureDialog(
      context,
      initial: existing.customKeys,
    );
    if (keys == null || keys.isEmpty || !mounted) return;
    final binding = ActionBinding.custom(keys);
    setState(() => _gestureDirs[dirKey] = binding.storageKey);
    _pushAssignment(ControlId.gesture);
  }

  String _displayForStorage(String storage) {
    return ActionBinding.fromStorage(storage).displayLabel;
  }

  List<String> _dropdownOptionsFor(String currentStorage) {
    final opts = List<String>.from(kSimpleActionLabels);
    // Ensure current custom combo appears as a selectable value.
    if (currentStorage.startsWith('custom:') &&
        !opts.contains(currentStorage)) {
      opts.insert(opts.length - 1, currentStorage);
    }
    return opts;
  }

  List<String> _mainDropdownOptions(String currentStorage) {
    final opts = List<String>.from(kButtonActionLabels);
    if (currentStorage.startsWith('custom:') &&
        !opts.contains(currentStorage)) {
      opts.insert(opts.length - 1, currentStorage);
    }
    return opts;
  }

  String _entryLabel(String storage) {
    if (storage.startsWith('custom:')) {
      return ActionBinding.fromStorage(storage).displayLabel;
    }
    if (storage == 'Custom shortcut…') return storage;
    return storage;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected;
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: DeviceCanvas(
              selected: selected,
              onSelect: (c) => setState(() => _selected = c),
            ),
          ),
        ),
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 24, 24, 24),
            child: Card(
              elevation: 0,
              color: theme.colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: selected == null
                    ? Center(
                        child: Text(
                          'Select a control on the mouse',
                          style: theme.textTheme.bodyLarge,
                        ),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              selected.label,
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              selected.cidHex,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text('Action', style: theme.textTheme.titleSmall),
                            const SizedBox(height: 8),
                            _ActionDropdown(
                              key: ValueKey('main-$selected-${_assignments[selected]}'),
                              value: _assignments[selected]!,
                              options: _mainDropdownOptions(_assignments[selected]!),
                              labelFor: _entryLabel,
                              onSelected: (v) async {
                                if (v == 'Custom shortcut…') {
                                  await _pickCustomForControl(selected);
                                  return;
                                }
                                setState(() => _assignments[selected] = v);
                                _pushAssignment(selected);
                              },
                            ),
                            if (_assignments[selected]!.startsWith('custom:')) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () => _pickCustomForControl(selected),
                                  icon: const Icon(Icons.keyboard, size: 18),
                                  label: Text(
                                    'Edit ${_displayForStorage(_assignments[selected]!)}',
                                  ),
                                ),
                              ),
                            ],
                            if (selected == ControlId.gesture &&
                                _assignments[selected] == 'Gesture (4-way)') ...[
                              const SizedBox(height: 24),
                              Text(
                                'Gesture directions',
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Hold the gesture button and move, or click in place. '
                                'Use Previous/Next Desktop or a custom shortcut (e.g. ⌃← / ⌃→) to switch Spaces.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 12),
                              for (final entry in _dirOrder) ...[
                                Text(entry.$2, style: theme.textTheme.labelLarge),
                                const SizedBox(height: 4),
                                _ActionDropdown(
                                  key: ValueKey(
                                    'dir-${entry.$1}-${_gestureDirs[entry.$1]}',
                                  ),
                                  value: _gestureDirs[entry.$1]!,
                                  options: _dropdownOptionsFor(
                                    _gestureDirs[entry.$1]!,
                                  ),
                                  labelFor: _entryLabel,
                                  onSelected: (v) async {
                                    if (v == 'Custom shortcut…') {
                                      await _pickCustomForDirection(entry.$1);
                                      return;
                                    }
                                    setState(() => _gestureDirs[entry.$1] = v);
                                    _pushAssignment(selected);
                                  },
                                ),
                                if (_gestureDirs[entry.$1]!
                                    .startsWith('custom:')) ...[
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                      onPressed: () =>
                                          _pickCustomForDirection(entry.$1),
                                      child: Text(
                                        'Edit ${_displayForStorage(_gestureDirs[entry.$1]!)}',
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                              ],
                            ],
                            const SizedBox(height: 16),
                            Text(
                              widget.state.daemonOnline
                                  ? 'Changes are applied live to the daemon.'
                                  : 'Start the daemon to apply remaps.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
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
  });

  final String value;
  final List<String> options;
  final String Function(String) labelFor;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu<String>(
      initialSelection: value,
      expandedInsets: EdgeInsets.zero,
      dropdownMenuEntries: [
        for (final o in options)
          DropdownMenuEntry(value: o, label: labelFor(o)),
      ],
      onSelected: (v) {
        if (v != null) onSelected(v);
      },
    );
  }
}
