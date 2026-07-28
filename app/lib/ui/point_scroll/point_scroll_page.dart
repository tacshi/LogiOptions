import 'package:flutter/material.dart';

import '../../data/application_catalog.dart';
import '../../data/models.dart';
import '../../data/profile_controller.dart';
import '../widgets/key_capture_dialog.dart';
import '../widgets/profile_selector.dart';

class PointScrollPage extends StatelessWidget {
  const PointScrollPage({super.key, required this.controller});

  final ProfileController controller;

  bool get isApplicationProfile => controller.selectedBundleId != null;
  ProfileSettings get stored => controller.editableProfile;
  ProfileSettings get resolved => controller.resolvedProfile;

  void update(ProfileSettings profile, {bool debounce = false}) {
    controller.updateProfile(profile, debounce: debounce);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capabilities = controller.state.capabilities;
    final settings = controller.deviceSettings;

    return Column(
      children: [
        ProfileSelector(controller: controller),
        if (controller.error != null)
          Material(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(controller.error!),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (capabilities.dpi != null) ...[
                Text('Pointer', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                _DpiCard(
                  range: capabilities.dpi!,
                  value: resolved.dpi ?? controller.state.dpi,
                  inherited: isApplicationProfile && stored.dpi == null,
                  onInherit: isApplicationProfile
                      ? (inherit) => update(
                          stored.copyWith(
                            dpi: inherit ? null : resolved.dpi,
                            clearDpi: inherit,
                          ),
                        )
                      : null,
                  onChanged: (value) =>
                      update(stored.copyWith(dpi: value), debounce: true),
                ),
                const SizedBox(height: 16),
              ],
              if (capabilities.hiResWheel || capabilities.smartShift) ...[
                Text('Scroll wheel', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  child: Column(
                    children: [
                      if (capabilities.smartShift)
                        _InheritedSwitch(
                          title: 'SmartShift',
                          value: resolved.smartShiftEnabled ?? false,
                          inherited:
                              isApplicationProfile &&
                              stored.smartShiftEnabled == null,
                          onInherit: isApplicationProfile
                              ? (inherit) => update(
                                  stored.copyWith(
                                    smartShiftEnabled: inherit
                                        ? null
                                        : resolved.smartShiftEnabled,
                                    clearSmartShiftEnabled: inherit,
                                  ),
                                )
                              : null,
                          onChanged: (value) =>
                              update(stored.copyWith(smartShiftEnabled: value)),
                        ),
                      if (capabilities.smartShift &&
                          (resolved.smartShiftEnabled ?? false))
                        _InheritedSlider(
                          title: 'SmartShift sensitivity',
                          value: (resolved.smartShiftThreshold ?? 10)
                              .toDouble(),
                          display: '${resolved.smartShiftThreshold ?? 10}',
                          min: 1,
                          max: 50,
                          divisions: 49,
                          inherited:
                              isApplicationProfile &&
                              stored.smartShiftThreshold == null,
                          onInherit: isApplicationProfile
                              ? (inherit) => update(
                                  stored.copyWith(
                                    smartShiftThreshold: inherit
                                        ? null
                                        : resolved.smartShiftThreshold,
                                    clearSmartShiftThreshold: inherit,
                                  ),
                                )
                              : null,
                          onChanged: (value) => update(
                            stored.copyWith(smartShiftThreshold: value.round()),
                            debounce: true,
                          ),
                        ),
                      if (capabilities.hiResWheel)
                        _InheritedSwitch(
                          title: 'High-resolution scroll',
                          value: resolved.hiresWheel ?? false,
                          inherited:
                              isApplicationProfile && stored.hiresWheel == null,
                          onInherit: isApplicationProfile
                              ? (inherit) => update(
                                  stored.copyWith(
                                    hiresWheel: inherit
                                        ? null
                                        : resolved.hiresWheel,
                                    clearHiresWheel: inherit,
                                  ),
                                )
                              : null,
                          onChanged: (value) =>
                              update(stored.copyWith(hiresWheel: value)),
                        ),
                      if (capabilities.hiResWheel)
                        _InheritedSlider(
                          title: 'Scrolling speed',
                          value: resolved.scrollSpeed ?? 1,
                          display:
                              '${((resolved.scrollSpeed ?? 1) * 100).round()}%',
                          min: .05,
                          max: 2,
                          divisions: 39,
                          inherited:
                              isApplicationProfile &&
                              stored.scrollSpeed == null,
                          onInherit: isApplicationProfile
                              ? (inherit) => update(
                                  stored.copyWith(
                                    scrollSpeed: inherit
                                        ? null
                                        : resolved.scrollSpeed,
                                    clearScrollSpeed: inherit,
                                  ),
                                )
                              : null,
                          onChanged: (value) => update(
                            stored.copyWith(scrollSpeed: value),
                            debounce: true,
                          ),
                        ),
                      if (capabilities.hiResWheel)
                        _InheritedSwitch(
                          title: 'Invert vertical wheel',
                          value: resolved.invertWheel ?? false,
                          inherited:
                              isApplicationProfile &&
                              stored.invertWheel == null,
                          onInherit: isApplicationProfile
                              ? (inherit) => update(
                                  stored.copyWith(
                                    invertWheel: inherit
                                        ? null
                                        : resolved.invertWheel,
                                    clearInvertWheel: inherit,
                                  ),
                                )
                              : null,
                          onChanged: (value) =>
                              update(stored.copyWith(invertWheel: value)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (capabilities.thumbWheel) ...[
                Text('Thumb wheel', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                _ThumbWheelCard(controller: controller),
                const SizedBox(height: 16),
              ],
              if (capabilities.haptics || capabilities.forceSensing) ...[
                Text('Haptic Sense', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  child: Column(
                    children: [
                      if (capabilities.haptics)
                        SwitchListTile(
                          title: const Text('Haptic feedback'),
                          value: settings['hapticEnabled'] as bool? ?? true,
                          onChanged: (value) => controller.patchDeviceSettings({
                            'hapticEnabled': value,
                          }),
                        ),
                      if (capabilities.haptics)
                        _PlainSlider(
                          title: 'Feedback level',
                          value:
                              (settings['hapticLevel'] as num?)?.toDouble() ??
                              60,
                          display: '${settings['hapticLevel'] as int? ?? 60}%',
                          min: 0,
                          max: 100,
                          divisions: 20,
                          onChanged: (value) => controller.patchDeviceSettings({
                            'hapticLevel': value.round(),
                          }, debounce: true),
                        ),
                      if (capabilities.haptics)
                        SwitchListTile(
                          title: const Text('Power saving'),
                          subtitle: const Text(
                            'Suppress selection pulses below 20% battery.',
                          ),
                          value: settings['hapticPowerSave'] as bool? ?? false,
                          onChanged: (value) => controller.patchDeviceSettings({
                            'hapticPowerSave': value,
                          }),
                        ),
                      if (capabilities.forceSensing)
                        _PlainSlider(
                          title: 'Panel force threshold',
                          value:
                              (settings['forceThreshold'] as num?)
                                  ?.toDouble() ??
                              50,
                          display:
                              '${settings['forceThreshold'] as int? ?? 50}%',
                          min: 0,
                          max: 100,
                          divisions: 20,
                          onChanged: (value) => controller.patchDeviceSettings({
                            'forceThreshold': value.round(),
                          }, debounce: true),
                        ),
                    ],
                  ),
                ),
              ],
              if (capabilities.dpi == null &&
                  !capabilities.hiResWheel &&
                  !capabilities.smartShift &&
                  !capabilities.thumbWheel &&
                  !capabilities.haptics)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No adjustable pointer or wheel features were detected. '
                      'Button assignments remain available when the device '
                      'reports programmable controls.',
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

class _DpiCard extends StatelessWidget {
  const _DpiCard({
    required this.range,
    required this.value,
    required this.inherited,
    required this.onInherit,
    required this.onChanged,
  });

  final DpiRange range;
  final int value;
  final bool inherited;
  final ValueChanged<bool>? onInherit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          _SettingTitle(
            title: 'DPI',
            value: '$value',
            inherited: inherited,
            onInherit: onInherit,
          ),
          Slider(
            value: value.toDouble().clamp(
              range.minimum.toDouble(),
              range.maximum.toDouble(),
            ),
            min: range.minimum.toDouble(),
            max: range.maximum.toDouble(),
            divisions: ((range.maximum - range.minimum) / range.step).round(),
            label: '$value',
            onChanged: (newValue) =>
                onChanged((newValue / range.step).round() * range.step),
          ),
        ],
      ),
    ),
  );
}

class _ThumbWheelCard extends StatelessWidget {
  const _ThumbWheelCard({required this.controller});

  final ProfileController controller;

  @override
  Widget build(BuildContext context) {
    final stored = controller.editableProfile;
    final resolved = controller.resolvedProfile;
    final application = controller.selectedBundleId != null;
    final mode = resolved.thumbMode ?? 'scroll';
    return Card(
      elevation: 0,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: DropdownButtonFormField<String>(
              initialValue: mode,
              decoration: const InputDecoration(
                labelText: 'Mode',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'scroll',
                  child: Text('Horizontal scroll'),
                ),
                DropdownMenuItem(
                  value: 'actions',
                  child: Text('Directional actions'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  controller.updateProfile(stored.copyWith(thumbMode: value));
                }
              },
            ),
          ),
          if (application)
            CheckboxListTile(
              title: const Text('Use Global thumb-wheel mode'),
              value: stored.thumbMode == null,
              onChanged: (value) => controller.updateProfile(
                stored.copyWith(
                  thumbMode: value == true ? null : mode,
                  clearThumbMode: value == true,
                ),
              ),
            ),
          if (mode == 'scroll') ...[
            _InheritedSlider(
              title: 'Thumb speed',
              value: resolved.thumbSpeed ?? 1,
              display: '${((resolved.thumbSpeed ?? 1) * 100).round()}%',
              min: .05,
              max: 2,
              divisions: 39,
              inherited: application && stored.thumbSpeed == null,
              onInherit: application
                  ? (inherit) => controller.updateProfile(
                      stored.copyWith(
                        thumbSpeed: inherit ? null : resolved.thumbSpeed,
                        clearThumbSpeed: inherit,
                      ),
                    )
                  : null,
              onChanged: (value) => controller.updateProfile(
                stored.copyWith(thumbSpeed: value),
                debounce: true,
              ),
            ),
            _InheritedSwitch(
              title: 'Invert thumb wheel',
              value: resolved.thumbInvert ?? false,
              inherited: application && stored.thumbInvert == null,
              onInherit: application
                  ? (inherit) => controller.updateProfile(
                      stored.copyWith(
                        thumbInvert: inherit ? null : resolved.thumbInvert,
                        clearThumbInvert: inherit,
                      ),
                    )
                  : null,
              onChanged: (value) =>
                  controller.updateProfile(stored.copyWith(thumbInvert: value)),
            ),
          ] else ...[
            _ActionPicker(
              title: 'Turn left',
              action: resolved.thumbLeftAction,
              inherited: application && stored.thumbLeftAction == null,
              allowSmartShift: controller.state.capabilities.smartShift,
              onInherit: application
                  ? (inherit) => controller.updateProfile(
                      stored.copyWith(
                        thumbLeftAction: inherit
                            ? null
                            : resolved.thumbLeftAction,
                        clearThumbLeftAction: inherit,
                      ),
                    )
                  : null,
              onChanged: (action) => controller.updateProfile(
                stored.copyWith(thumbLeftAction: action),
              ),
            ),
            _ActionPicker(
              title: 'Turn right',
              action: resolved.thumbRightAction,
              inherited: application && stored.thumbRightAction == null,
              allowSmartShift: controller.state.capabilities.smartShift,
              onInherit: application
                  ? (inherit) => controller.updateProfile(
                      stored.copyWith(
                        thumbRightAction: inherit
                            ? null
                            : resolved.thumbRightAction,
                        clearThumbRightAction: inherit,
                      ),
                    )
                  : null,
              onChanged: (action) => controller.updateProfile(
                stored.copyWith(thumbRightAction: action),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionPicker extends StatefulWidget {
  const _ActionPicker({
    required this.title,
    required this.action,
    required this.onChanged,
    required this.inherited,
    required this.onInherit,
    required this.allowSmartShift,
  });

  final String title;
  final Map<String, dynamic>? action;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool inherited;
  final ValueChanged<bool>? onInherit;
  final bool allowSmartShift;

  @override
  State<_ActionPicker> createState() => _ActionPickerState();
}

class _ActionPickerState extends State<_ActionPicker> {
  final _catalog = const ApplicationCatalog();

  Future<void> _select(String value) async {
    if (value == 'Custom shortcut…') {
      final current = ActionBinding.fromStorage(
        actionStorageKeyFromJson(widget.action),
      );
      final keys = await showKeyCaptureDialog(
        context,
        initial: current.customKeys,
      );
      if (keys != null && keys.isNotEmpty && mounted) {
        widget.onChanged(ActionBinding.custom(keys).toJson());
      }
      return;
    }
    if (value == 'Open application…') {
      final application = await _catalog.browse();
      if (application != null && mounted) {
        widget.onChanged({
          'type': 'open',
          'kind': 'app',
          'value': application.path,
        });
      }
      return;
    }
    if (value == 'Open file…') {
      final path = await _catalog.browseFile();
      if (path != null && path.isNotEmpty && mounted) {
        widget.onChanged({'type': 'open', 'kind': 'file', 'value': path});
      }
      return;
    }
    if (value == 'Open URL…') {
      final controller = TextEditingController(
        text:
            widget.action?['type'] == 'open' && widget.action?['kind'] == 'url'
            ? (widget.action?['value']?.toString() ?? '')
            : '',
      );
      final target = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Open URL'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'https://example.com',
              labelText: 'Web address',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final input = controller.text.trim();
                if (input.isEmpty) return;
                final normalized = input.contains('://')
                    ? input
                    : 'https://$input';
                final uri = Uri.tryParse(normalized);
                if (uri != null &&
                    {'http', 'https'}.contains(uri.scheme) &&
                    uri.host.isNotEmpty) {
                  Navigator.pop(context, uri.toString());
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (target != null && mounted) {
        widget.onChanged({'type': 'open', 'kind': 'url', 'value': target});
      }
      return;
    }
    widget.onChanged(simpleActionJsonForLabel(value));
  }

  @override
  Widget build(BuildContext context) {
    final value = actionStorageKeyFromJson(widget.action);
    final options = List<String>.from(kSimpleActionLabels);
    if (!widget.allowSmartShift) options.remove('SmartShift toggle');
    if (!options.contains(value)) options.add(value);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: widget.title,
          helperText: widget.inherited ? 'Using Global' : null,
          border: const OutlineInputBorder(),
          suffixIcon: widget.onInherit == null
              ? null
              : IconButton(
                  tooltip: widget.inherited ? 'Override Global' : 'Use Global',
                  onPressed: () => widget.onInherit!(!widget.inherited),
                  icon: Icon(
                    widget.inherited ? Icons.link : Icons.link_off,
                    size: 18,
                  ),
                ),
        ),
        items: [
          for (final option in options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: (value) {
          if (value != null) _select(value);
        },
      ),
    );
  }
}

class _InheritedSwitch extends StatelessWidget {
  const _InheritedSwitch({
    required this.title,
    required this.value,
    required this.inherited,
    required this.onInherit,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final bool inherited;
  final ValueChanged<bool>? onInherit;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SwitchListTile(
        title: Text(title),
        subtitle: inherited ? const Text('Using Global') : null,
        value: value,
        onChanged: onChanged,
      ),
      if (onInherit != null)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => onInherit!(!inherited),
            child: Text(inherited ? 'Override' : 'Use Global'),
          ),
        ),
    ],
  );
}

class _InheritedSlider extends StatelessWidget {
  const _InheritedSlider({
    required this.title,
    required this.value,
    required this.display,
    required this.min,
    required this.max,
    required this.divisions,
    required this.inherited,
    required this.onInherit,
    required this.onChanged,
  });

  final String title;
  final double value;
  final String display;
  final double min;
  final double max;
  final int divisions;
  final bool inherited;
  final ValueChanged<bool>? onInherit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Column(
      children: [
        _SettingTitle(
          title: title,
          value: display,
          inherited: inherited,
          onInherit: onInherit,
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          label: display,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _PlainSlider extends StatelessWidget {
  const _PlainSlider({
    required this.title,
    required this.value,
    required this.display,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String title;
  final double value;
  final String display;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Column(
      children: [
        _SettingTitle(title: title, value: display, inherited: false),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _SettingTitle extends StatelessWidget {
  const _SettingTitle({
    required this.title,
    required this.value,
    required this.inherited,
    this.onInherit,
  });

  final String title;
  final String value;
  final bool inherited;
  final ValueChanged<bool>? onInherit;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      if (inherited)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text('Global', style: Theme.of(context).textTheme.labelSmall),
        ),
      Text(value, style: Theme.of(context).textTheme.titleMedium),
      if (onInherit != null)
        IconButton(
          tooltip: inherited ? 'Override Global' : 'Use Global',
          onPressed: () => onInherit!(!inherited),
          icon: Icon(inherited ? Icons.link : Icons.link_off, size: 18),
        ),
    ],
  );
}
