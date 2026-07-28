import 'package:flutter/material.dart';

import '../../data/models.dart';
import 'device_illustration.dart';

/// Product artwork with capability-derived control hotspots.
class DeviceCanvas extends StatelessWidget {
  const DeviceCanvas({
    super.key,
    required this.state,
    required this.selected,
    required this.onSelect,
  });

  final DeviceState state;
  final DeviceControl? selected;
  final ValueChanged<DeviceControl> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        final maxW = constraints.maxWidth;
        final modelId = state.modelId.toLowerCase();
        final aspect = {'6b023', '2b034', '2b043'}.contains(modelId)
            ? 636 / 1024
            : 2 / 3;
        double h = maxH;
        double w = h * aspect;
        if (w > maxW) {
          w = maxW;
          h = w / aspect;
        }
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DeviceIllustration(
                    artworkKey: state.artworkKey,
                    modelId: state.modelId,
                  ),
                ),
                for (final control in state.controls)
                  Positioned(
                    left: w * control.x - 14,
                    top: h * control.y - 14,
                    child: _Hotspot(
                      label: control.label,
                      selected: selected?.cid == control.cid,
                      onTap: () => onSelect(control),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Hotspot extends StatelessWidget {
  const _Hotspot({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? theme.colorScheme.primary
                  : const Color(0xFF2B5F7A).withValues(alpha: 0.92),
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: selected ? 10 : 6,
                ),
              ],
            ),
            child: selected
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}
