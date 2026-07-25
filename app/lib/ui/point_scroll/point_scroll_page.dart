import 'package:flutter/material.dart';

import '../../data/models.dart';

class PointScrollPage extends StatelessWidget {
  const PointScrollPage({
    super.key,
    required this.state,
    required this.onDpiChanged,
    required this.onSmartShiftChanged,
    required this.onHiresChanged,
    required this.onInvertWheel,
    required this.onScrollSpeed,
    required this.onThumbInvert,
    required this.onThumbSpeed,
  });

  final DeviceState state;
  final ValueChanged<int> onDpiChanged;
  final void Function(bool enabled, int threshold) onSmartShiftChanged;
  final ValueChanged<bool> onHiresChanged;
  final ValueChanged<bool> onInvertWheel;
  final ValueChanged<double> onScrollSpeed;
  final ValueChanged<bool> onThumbInvert;
  final ValueChanged<double> onThumbSpeed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Pointer', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text('DPI', style: theme.textTheme.titleMedium),
                    const Spacer(),
                    Text('${state.dpi}', style: theme.textTheme.titleMedium),
                  ],
                ),
                Slider(
                  value: state.dpi.toDouble().clamp(200, 8000),
                  min: 200,
                  max: 8000,
                  divisions: 78,
                  label: '${state.dpi}',
                  onChanged: (v) => onDpiChanged(v.round()),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('MagSpeed wheel', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          child: Column(
            children: [
              SwitchListTile(
                dense: true,
                title: const Text('SmartShift'),
                value: state.smartShiftEnabled,
                onChanged: (v) =>
                    onSmartShiftChanged(v, state.smartShiftThreshold),
              ),
              if (state.smartShiftEnabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Text('Sensitivity'),
                          const Spacer(),
                          Text('${state.smartShiftThreshold}'),
                        ],
                      ),
                      Slider(
                        value:
                            state.smartShiftThreshold.toDouble().clamp(1, 50),
                        min: 1,
                        max: 50,
                        divisions: 49,
                        onChanged: (v) =>
                            onSmartShiftChanged(true, v.round()),
                      ),
                    ],
                  ),
                ),
              SwitchListTile(
                dense: true,
                title: const Text('High-resolution scroll'),
                value: state.hiresWheel,
                onChanged: onHiresChanged,
              ),
              if (state.hiresWheel)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Text('Scrolling speed'),
                          const Spacer(),
                          Text('${(state.scrollSpeed * 100).round()}%'),
                        ],
                      ),
                      Slider(
                        value: state.scrollSpeed.clamp(0.05, 2.0),
                        min: 0.05,
                        max: 2.0,
                        divisions: 39,
                        label: '${(state.scrollSpeed * 100).round()}%',
                        onChanged: onScrollSpeed,
                      ),
                    ],
                  ),
                ),
              SwitchListTile(
                dense: true,
                title: const Text('Invert vertical wheel'),
                value: state.invertWheel,
                onChanged: onInvertWheel,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Thumb wheel', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Text('Thumb speed'),
                        const Spacer(),
                        Text('${(state.thumbSpeed * 100).round()}%'),
                      ],
                    ),
                    Slider(
                      value: state.thumbSpeed.clamp(0.05, 2.0),
                      min: 0.05,
                      max: 2.0,
                      divisions: 39,
                      label: '${(state.thumbSpeed * 100).round()}%',
                      onChanged: onThumbSpeed,
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                dense: true,
                title: const Text('Invert thumb wheel'),
                value: state.thumbInvert,
                onChanged: onThumbInvert,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
