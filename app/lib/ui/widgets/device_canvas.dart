import 'package:flutter/material.dart';

import '../../data/models.dart';

/// Side-view device art from Options+ depot (`side_core.png`) with hotspot markers.
///
/// Marker positions come from Options+ `core_metadata.json` (percent of image).
class DeviceCanvas extends StatelessWidget {
  const DeviceCanvas({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final ControlId? selected;
  final ValueChanged<ControlId> onSelect;

  /// Options+ `device_buttons_image` markers (percent of 636×1024 art).
  static const _layout = <ControlId, Offset>{
    ControlId.middle: Offset(71, 15),
    ControlId.modeShift: Offset(81, 34),
    ControlId.forward: Offset(35, 43),
    ControlId.back: Offset(45, 60),
    ControlId.gesture: Offset(8, 58),
    // Thumb wheel shown as non-button; skip hotspot or place near art
  };

  static const _imageAsset = 'assets/devices/mx_master_3s/side_core.png';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Art is portrait (~636×1024). Fit height-first, center horizontally.
        final maxH = constraints.maxHeight;
        final maxW = constraints.maxWidth;
        const aspect = 636 / 1024;
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
                  child: Image.asset(
                    _imageAsset,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, __, ___) => _FallbackBody(theme: Theme.of(context)),
                  ),
                ),
                for (final entry in _layout.entries)
                  Positioned(
                    left: w * (entry.value.dx / 100) - 14,
                    top: h * (entry.value.dy / 100) - 14,
                    child: _Hotspot(
                      label: entry.key.label,
                      selected: selected == entry.key,
                      onTap: () => onSelect(entry.key),
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

class _FallbackBody extends StatelessWidget {
  const _FallbackBody({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(48),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.mouse, size: 64, color: theme.colorScheme.outline),
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
