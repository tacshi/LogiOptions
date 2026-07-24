// Domain models for LogiOptions device settings (daemon + UI).

enum ConnectionType { ble, bolt, unknown }

enum ControlId {
  middle(0x52, 'Middle button'),
  back(0x53, 'Back'),
  forward(0x56, 'Forward'),
  gesture(0xC3, 'Gesture button'),
  modeShift(0xC4, 'Mode shift');

  const ControlId(this.cid, this.label);
  final int cid;
  final String label;

  String get cidHex => '0x${cid.toRadixString(16).toUpperCase()}';
}

class DeviceState {
  const DeviceState({
    this.connected = false,
    this.name = 'No device',
    this.modelId = '2b034',
    this.connection = ConnectionType.unknown,
    this.batteryPercent,
    this.charging = false,
    this.dpi = 1000,
    this.smartShiftEnabled = true,
    this.smartShiftThreshold = 30,
    this.hiresWheel = true,
    this.invertWheel = false,
    this.scrollSpeed = 1.0,
    this.thumbInvert = false,
    this.thumbSpeed = 1.0,
    this.daemonOnline = false,
    this.optionsPlusRunning = false,
    this.loginAtStartup = false,
    this.accessibilityTrusted = true,
    this.inputMonitoringTrusted = true,
  });

  final bool connected;
  final String name;
  final String modelId;
  final ConnectionType connection;
  final int? batteryPercent;
  final bool charging;
  final int dpi;
  final bool smartShiftEnabled;
  final int smartShiftThreshold;
  final bool hiresWheel;
  final bool invertWheel;
  /// 0…2 host vertical scroll speed (1.0 = 100%).
  final double scrollSpeed;
  final bool thumbInvert;
  /// 0…2 thumb wheel speed (1.0 = 100%).
  final double thumbSpeed;
  final bool daemonOnline;
  final bool optionsPlusRunning;
  /// LaunchAgent: daemon starts at login and KeepAlive restarts it.
  final bool loginAtStartup;
  final bool accessibilityTrusted;
  final bool inputMonitoringTrusted;

  /// Accessibility is enough for remaps / host scroll / Spaces.
  bool get permissionsOk => accessibilityTrusted;

  DeviceState copyWith({
    bool? connected,
    String? name,
    String? modelId,
    ConnectionType? connection,
    int? batteryPercent,
    bool clearBattery = false,
    bool? charging,
    int? dpi,
    bool? smartShiftEnabled,
    int? smartShiftThreshold,
    bool? hiresWheel,
    bool? invertWheel,
    double? scrollSpeed,
    bool? thumbInvert,
    double? thumbSpeed,
    bool? daemonOnline,
    bool? optionsPlusRunning,
    bool? loginAtStartup,
    bool? accessibilityTrusted,
    bool? inputMonitoringTrusted,
  }) {
    return DeviceState(
      connected: connected ?? this.connected,
      name: name ?? this.name,
      modelId: modelId ?? this.modelId,
      connection: connection ?? this.connection,
      batteryPercent:
          clearBattery ? null : (batteryPercent ?? this.batteryPercent),
      charging: charging ?? this.charging,
      dpi: dpi ?? this.dpi,
      smartShiftEnabled: smartShiftEnabled ?? this.smartShiftEnabled,
      smartShiftThreshold: smartShiftThreshold ?? this.smartShiftThreshold,
      hiresWheel: hiresWheel ?? this.hiresWheel,
      invertWheel: invertWheel ?? this.invertWheel,
      scrollSpeed: scrollSpeed ?? this.scrollSpeed,
      thumbInvert: thumbInvert ?? this.thumbInvert,
      thumbSpeed: thumbSpeed ?? this.thumbSpeed,
      daemonOnline: daemonOnline ?? this.daemonOnline,
      optionsPlusRunning: optionsPlusRunning ?? this.optionsPlusRunning,
      loginAtStartup: loginAtStartup ?? this.loginAtStartup,
      accessibilityTrusted: accessibilityTrusted ?? this.accessibilityTrusted,
      inputMonitoringTrusted:
          inputMonitoringTrusted ?? this.inputMonitoringTrusted,
    );
  }
}

/// Preset simple actions for buttons / gesture directions.
const kSimpleActionLabels = <String>[
  'Middle click',
  'Back',
  'Forward',
  'SmartShift toggle',
  'Mission Control',
  'App Exposé',
  'Launchpad',
  'Show Desktop',
  'Spotlight',
  'Previous Desktop',
  'Next Desktop',
  'Volume up',
  'Volume down',
  'Mute',
  'Disabled',
  'Custom shortcut…',
];

/// Top-level button actions (includes gesture mode).
const kButtonActionLabels = <String>[
  'Middle click',
  'Back',
  'Forward',
  'Gesture (4-way)',
  'SmartShift toggle',
  'Mission Control',
  'App Exposé',
  'Launchpad',
  'Show Desktop',
  'Spotlight',
  'Previous Desktop',
  'Next Desktop',
  'Volume up',
  'Volume down',
  'Mute',
  'Disabled',
  'Custom shortcut…',
];

/// One binding: either a named preset or a custom key chord.
class ActionBinding {
  const ActionBinding.preset(this.preset)
      : customKeys = null,
        assert(preset != null);

  const ActionBinding.custom(this.customKeys)
      : preset = null,
        assert(customKeys != null);

  final String? preset;
  final List<String>? customKeys;

  bool get isCustom => customKeys != null && customKeys!.isNotEmpty;

  String get displayLabel {
    if (isCustom) return formatKeyCombo(customKeys!);
    return preset ?? 'Disabled';
  }

  /// Dropdown value key (preset name, or `custom:ctrl+left`).
  String get storageKey {
    if (isCustom) return 'custom:${customKeys!.join('+')}';
    return preset ?? 'Disabled';
  }

  static ActionBinding fromStorage(String key) {
    if (key.startsWith('custom:')) {
      final body = key.substring('custom:'.length);
      if (body.isEmpty) return const ActionBinding.preset('Disabled');
      return ActionBinding.custom(
        body.split('+').where((s) => s.isNotEmpty).toList(),
      );
    }
    if (key == 'Custom shortcut…') {
      return const ActionBinding.preset('Disabled');
    }
    return ActionBinding.preset(key);
  }

  Map<String, dynamic> toJson() {
    if (isCustom) {
      return {'type': 'keystroke', 'keys': customKeys};
    }
    return simpleActionJsonForLabel(preset ?? 'Disabled');
  }
}

String formatKeyCombo(List<String> keys) {
  const symbols = <String, String>{
    'cmd': '⌘',
    'command': '⌘',
    'meta': '⌘',
    'ctrl': '⌃',
    'control': '⌃',
    'alt': '⌥',
    'option': '⌥',
    'shift': '⇧',
    'fn': 'fn',
    'left': '←',
    'right': '→',
    'up': '↑',
    'down': '↓',
    'space': 'Space',
    'return': '↩',
    'enter': '↩',
    'tab': '⇥',
    'escape': '⎋',
    'esc': '⎋',
    'delete': '⌫',
  };
  return keys.map((k) {
    final lower = k.toLowerCase();
    return symbols[lower] ?? k.toUpperCase();
  }).join('');
}

/// UI label / storage key → daemon action JSON (simple actions only).
Map<String, dynamic> simpleActionJsonForLabel(String label) {
  if (label.startsWith('custom:')) {
    return ActionBinding.fromStorage(label).toJson();
  }
  switch (label) {
    case 'Middle click':
      return {'type': 'mouse', 'button': 'middle'};
    case 'Back':
      return {'type': 'mouse', 'button': 'back'};
    case 'Forward':
      return {'type': 'mouse', 'button': 'forward'};
    case 'Left click':
      return {'type': 'mouse', 'button': 'left'};
    case 'Right click':
      return {'type': 'mouse', 'button': 'right'};
    case 'SmartShift toggle':
      return {'type': 'smartshift_toggle'};
    case 'Mission Control':
      return {'type': 'system', 'id': 'mission_control'};
    case 'App Exposé':
      return {'type': 'system', 'id': 'app_expose'};
    case 'Launchpad':
      return {'type': 'system', 'id': 'launchpad'};
    case 'Show Desktop':
      return {'type': 'system', 'id': 'desktop'};
    case 'Spotlight':
      return {'type': 'system', 'id': 'spotlight'};
    case 'Previous Desktop':
      // System action (not keystroke) so the daemon uses System Events and
      // never delivers Ctrl+Arrow into this app's bottom NavigationBar.
      return {'type': 'system', 'id': 'previous_desktop'};
    case 'Next Desktop':
      return {'type': 'system', 'id': 'next_desktop'};
    case 'Volume up':
      return {'type': 'media', 'id': 'volume_up'};
    case 'Volume down':
      return {'type': 'media', 'id': 'volume_down'};
    case 'Mute':
      return {'type': 'media', 'id': 'mute'};
    case 'Disabled':
    case 'Custom shortcut…':
    default:
      return {'type': 'none'};
  }
}

/// Full button assignment (may be a 4-way gesture).
/// [gestureDirections] maps click/up/down/left/right → storage keys.
Map<String, dynamic> actionJsonForLabel(
  String label, {
  Map<String, String>? gestureDirections,
}) {
  if (label == 'Gesture (4-way)') {
    final d = gestureDirections ??
        const {
          'click': 'Mission Control',
          'up': 'Mission Control',
          'down': 'App Exposé',
          'left': 'Previous Desktop',
          'right': 'Next Desktop',
        };
    return {
      'type': 'gesture',
      'click': simpleActionJsonForLabel(d['click'] ?? 'Mission Control'),
      'up': simpleActionJsonForLabel(d['up'] ?? 'Mission Control'),
      'down': simpleActionJsonForLabel(d['down'] ?? 'App Exposé'),
      'left': simpleActionJsonForLabel(d['left'] ?? 'Previous Desktop'),
      'right': simpleActionJsonForLabel(d['right'] ?? 'Next Desktop'),
    };
  }
  return simpleActionJsonForLabel(label);
}
