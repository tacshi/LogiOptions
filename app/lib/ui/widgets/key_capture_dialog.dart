import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';

/// Modal that records a key combination (modifiers + one key).
Future<List<String>?> showKeyCaptureDialog(
  BuildContext context, {
  List<String>? initial,
}) {
  return showDialog<List<String>>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _KeyCaptureDialog(initial: initial),
  );
}

class _KeyCaptureDialog extends StatefulWidget {
  const _KeyCaptureDialog({this.initial});

  final List<String>? initial;

  @override
  State<_KeyCaptureDialog> createState() => _KeyCaptureDialogState();
}

class _KeyCaptureDialogState extends State<_KeyCaptureDialog> {
  final _focus = FocusNode();
  List<String> _keys = [];

  @override
  void initState() {
    super.initState();
    _keys = List<String>.from(widget.initial ?? const []);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;

    final parts = <String>[];
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;

    if (pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight) ||
        event.logicalKey == LogicalKeyboardKey.metaLeft ||
        event.logicalKey == LogicalKeyboardKey.metaRight) {
      parts.add('cmd');
    }
    if (pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight) ||
        event.logicalKey == LogicalKeyboardKey.controlLeft ||
        event.logicalKey == LogicalKeyboardKey.controlRight) {
      parts.add('ctrl');
    }
    if (pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight) ||
        event.logicalKey == LogicalKeyboardKey.altLeft ||
        event.logicalKey == LogicalKeyboardKey.altRight) {
      parts.add('alt');
    }
    if (pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight) ||
        event.logicalKey == LogicalKeyboardKey.shiftLeft ||
        event.logicalKey == LogicalKeyboardKey.shiftRight) {
      parts.add('shift');
    }

    final keyName = _keyName(event.logicalKey);
    if (keyName == null) {
      // Modifier-only press — wait for a non-modifier key.
      return KeyEventResult.handled;
    }
    parts.add(keyName);
    setState(() => _keys = parts);
    return KeyEventResult.handled;
  }

  String? _keyName(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight) {
      return null;
    }
    if (key == LogicalKeyboardKey.arrowLeft) return 'left';
    if (key == LogicalKeyboardKey.arrowRight) return 'right';
    if (key == LogicalKeyboardKey.arrowUp) return 'up';
    if (key == LogicalKeyboardKey.arrowDown) return 'down';
    if (key == LogicalKeyboardKey.space) return 'space';
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      return 'return';
    }
    if (key == LogicalKeyboardKey.tab) return 'tab';
    if (key == LogicalKeyboardKey.escape) return 'escape';
    if (key == LogicalKeyboardKey.backspace) return 'delete';
    final label = key.keyLabel;
    if (label.length == 1) return label.toLowerCase();
    // F-keys etc.
    if (label.startsWith('F') && label.length <= 3) return label.toLowerCase();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Custom shortcut'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Press the key combination you want (e.g. Control + ← for Previous Desktop).',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Focus(
              focusNode: _focus,
              autofocus: true,
              onKeyEvent: _onKey,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.primary),
                ),
                alignment: Alignment.center,
                child: Text(
                  _keys.isEmpty ? 'Waiting for keys…' : formatKeyCombo(_keys),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tip: macOS Switch Desktop is usually ⌃← / ⌃→',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _keys = []),
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _keys.isEmpty
              ? null
              : () => Navigator.of(context).pop(List<String>.from(_keys)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
