// Domain models for LogiOptions device settings (daemon + UI).

enum ConnectionType { ble, bolt, usb, receiver, unknown }

class DpiRange {
  const DpiRange({
    required this.minimum,
    required this.maximum,
    required this.step,
  });

  factory DpiRange.fromJson(Map<String, dynamic> json) => DpiRange(
    minimum: json['minimum'] as int? ?? 200,
    maximum: json['maximum'] as int? ?? 4000,
    step: json['step'] as int? ?? 50,
  );

  final int minimum;
  final int maximum;
  final int step;
}

class DeviceCapabilities {
  const DeviceCapabilities({
    this.battery = false,
    this.dpi,
    this.hiResWheel = false,
    this.smartShift = false,
    this.thumbWheel = false,
    this.haptics = false,
    this.forceSensing = false,
  });

  factory DeviceCapabilities.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DeviceCapabilities();
    return DeviceCapabilities(
      battery: json['battery'] as bool? ?? false,
      dpi: json['dpi'] is Map
          ? DpiRange.fromJson(Map<String, dynamic>.from(json['dpi'] as Map))
          : null,
      hiResWheel: json['hiResWheel'] as bool? ?? false,
      smartShift: json['smartShift'] as bool? ?? false,
      thumbWheel: json['thumbWheel'] as bool? ?? false,
      haptics: json['haptics'] as bool? ?? false,
      forceSensing: json['forceSensing'] as bool? ?? false,
    );
  }

  final bool battery;
  final DpiRange? dpi;
  final bool hiResWheel;
  final bool smartShift;
  final bool thumbWheel;
  final bool haptics;
  final bool forceSensing;
}

class DeviceControl {
  const DeviceControl({
    required this.cid,
    required this.label,
    required this.x,
    required this.y,
  });

  factory DeviceControl.fromJson(Map<String, dynamic> json) => DeviceControl(
    cid: json['cid'] as int? ?? 0,
    label: json['label'] as String? ?? 'Button',
    x: (json['x'] as num?)?.toDouble() ?? .5,
    y: (json['y'] as num?)?.toDouble() ?? .5,
  );

  final int cid;
  final String label;
  final double x;
  final double y;

  String get cidHex => '0x${cid.toRadixString(16).toUpperCase()}';
}

class DeviceDescriptor {
  const DeviceDescriptor({
    required this.id,
    required this.modelId,
    required this.name,
    required this.kind,
    required this.connection,
    required this.connected,
    required this.verified,
    required this.capabilities,
    required this.controls,
    required this.artworkKey,
  });

  factory DeviceDescriptor.fromJson(Map<String, dynamic> json) =>
      DeviceDescriptor(
        id: json['id'] as String? ?? 'unknown',
        modelId: json['modelId'] as String? ?? 'unknown',
        name: json['name'] as String? ?? 'Compatible Logitech device',
        kind: json['kind'] as String? ?? 'mouse',
        connection: connectionTypeFromString(json['transport'] as String?),
        connected: json['connected'] as bool? ?? false,
        verified: json['verification'] == 'verified',
        capabilities: DeviceCapabilities.fromJson(
          json['capabilities'] is Map
              ? Map<String, dynamic>.from(json['capabilities'] as Map)
              : null,
        ),
        controls: (json['controls'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map(
              (value) =>
                  DeviceControl.fromJson(Map<String, dynamic>.from(value)),
            )
            .toList(),
        artworkKey: json['artworkKey'] as String? ?? 'generic_mouse',
      );

  final String id;
  final String modelId;
  final String name;
  final String kind;
  final ConnectionType connection;
  final bool connected;
  final bool verified;
  final DeviceCapabilities capabilities;
  final List<DeviceControl> controls;
  final String artworkKey;
}

ConnectionType connectionTypeFromString(String? value) => switch (value) {
  'ble' => ConnectionType.ble,
  'bolt' => ConnectionType.bolt,
  'usb' => ConnectionType.usb,
  'receiver' => ConnectionType.receiver,
  _ => ConnectionType.unknown,
};

class DeviceState {
  const DeviceState({
    this.connected = false,
    this.name = 'No device',
    this.deviceId,
    this.modelId = 'unknown',
    this.connection = ConnectionType.unknown,
    this.verified = false,
    this.capabilities = const DeviceCapabilities(),
    this.controls = const [],
    this.artworkKey = 'generic_mouse',
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

  factory DeviceState.fromJson(
    Map<String, dynamic> json, {
    DeviceDescriptor? descriptor,
  }) => DeviceState(
    connected: json['connected'] as bool? ?? descriptor?.connected ?? false,
    name: json['deviceName'] as String? ?? descriptor?.name ?? 'No device',
    deviceId: json['deviceId'] as String? ?? descriptor?.id,
    modelId: json['modelId'] as String? ?? descriptor?.modelId ?? 'unknown',
    connection: connectionTypeFromString(json['connection'] as String?),
    verified:
        json['verification'] == 'verified' || descriptor?.verified == true,
    capabilities:
        descriptor?.capabilities ??
        DeviceCapabilities.fromJson(
          json['capabilities'] is Map
              ? Map<String, dynamic>.from(json['capabilities'] as Map)
              : null,
        ),
    controls:
        descriptor?.controls ??
        (json['controls'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map(
              (value) =>
                  DeviceControl.fromJson(Map<String, dynamic>.from(value)),
            )
            .toList(),
    artworkKey:
        json['artworkKey'] as String? ??
        descriptor?.artworkKey ??
        'generic_mouse',
    batteryPercent: json['batteryPercent'] as int?,
    charging: json['charging'] as bool? ?? false,
    dpi: json['dpi'] as int? ?? 1000,
    smartShiftEnabled: json['smartShiftEnabled'] as bool? ?? false,
    smartShiftThreshold: json['smartShiftThreshold'] as int? ?? 10,
    hiresWheel: json['hiresWheel'] as bool? ?? false,
    invertWheel: json['invertWheel'] as bool? ?? false,
    scrollSpeed: (json['scrollSpeed'] as num?)?.toDouble() ?? 1,
    thumbInvert: json['thumbInvert'] as bool? ?? false,
    thumbSpeed: (json['thumbSpeed'] as num?)?.toDouble() ?? 1,
    daemonOnline: json['daemonOnline'] as bool? ?? true,
    optionsPlusRunning: json['optionsPlusRunning'] as bool? ?? false,
    loginAtStartup: json['loginAtStartup'] as bool? ?? false,
    accessibilityTrusted: json['accessibilityTrusted'] as bool? ?? false,
    inputMonitoringTrusted: json['inputMonitoringTrusted'] as bool? ?? false,
  );

  final bool connected;
  final String name;
  final String? deviceId;
  final String modelId;
  final ConnectionType connection;
  final bool verified;
  final DeviceCapabilities capabilities;
  final List<DeviceControl> controls;
  final String artworkKey;
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
    String? deviceId,
    String? modelId,
    ConnectionType? connection,
    bool? verified,
    DeviceCapabilities? capabilities,
    List<DeviceControl>? controls,
    String? artworkKey,
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
      deviceId: deviceId ?? this.deviceId,
      modelId: modelId ?? this.modelId,
      connection: connection ?? this.connection,
      verified: verified ?? this.verified,
      capabilities: capabilities ?? this.capabilities,
      controls: controls ?? this.controls,
      artworkKey: artworkKey ?? this.artworkKey,
      batteryPercent: clearBattery
          ? null
          : (batteryPercent ?? this.batteryPercent),
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

class ProfileSettings {
  const ProfileSettings({
    this.dpi,
    this.smartShiftEnabled,
    this.smartShiftThreshold,
    this.hiresWheel,
    this.invertWheel,
    this.scrollSpeed,
    this.thumbDivert,
    this.thumbInvert,
    this.thumbSpeed,
    this.thumbMode,
    this.thumbLeftAction,
    this.thumbRightAction,
    this.buttons = const {},
  });

  factory ProfileSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ProfileSettings();
    return ProfileSettings(
      dpi: json['dpi'] as int?,
      smartShiftEnabled: json['smartShiftEnabled'] as bool?,
      smartShiftThreshold: json['smartShiftThreshold'] as int?,
      hiresWheel: json['hiresWheel'] as bool?,
      invertWheel: json['invertWheel'] as bool?,
      scrollSpeed: (json['scrollSpeed'] as num?)?.toDouble(),
      thumbDivert: json['thumbDivert'] as bool?,
      thumbInvert: json['thumbInvert'] as bool?,
      thumbSpeed: (json['thumbSpeed'] as num?)?.toDouble(),
      thumbMode: json['thumbMode'] as String?,
      thumbLeftAction: json['thumbLeftAction'] is Map
          ? Map<String, dynamic>.from(json['thumbLeftAction'] as Map)
          : null,
      thumbRightAction: json['thumbRightAction'] is Map
          ? Map<String, dynamic>.from(json['thumbRightAction'] as Map)
          : null,
      buttons:
          (json['buttons'] as Map?)?.map(
            (key, value) => MapEntry(
              key.toString(),
              Map<String, dynamic>.from(value as Map),
            ),
          ) ??
          const {},
    );
  }

  final int? dpi;
  final bool? smartShiftEnabled;
  final int? smartShiftThreshold;
  final bool? hiresWheel;
  final bool? invertWheel;
  final double? scrollSpeed;
  final bool? thumbDivert;
  final bool? thumbInvert;
  final double? thumbSpeed;
  final String? thumbMode;
  final Map<String, dynamic>? thumbLeftAction;
  final Map<String, dynamic>? thumbRightAction;
  final Map<String, Map<String, dynamic>> buttons;

  ProfileSettings copyWith({
    int? dpi,
    bool clearDpi = false,
    bool? smartShiftEnabled,
    bool clearSmartShiftEnabled = false,
    int? smartShiftThreshold,
    bool clearSmartShiftThreshold = false,
    bool? hiresWheel,
    bool clearHiresWheel = false,
    bool? invertWheel,
    bool clearInvertWheel = false,
    double? scrollSpeed,
    bool clearScrollSpeed = false,
    bool? thumbDivert,
    bool clearThumbDivert = false,
    bool? thumbInvert,
    bool clearThumbInvert = false,
    double? thumbSpeed,
    bool clearThumbSpeed = false,
    String? thumbMode,
    bool clearThumbMode = false,
    Map<String, dynamic>? thumbLeftAction,
    bool clearThumbLeftAction = false,
    Map<String, dynamic>? thumbRightAction,
    bool clearThumbRightAction = false,
    Map<String, Map<String, dynamic>>? buttons,
  }) => ProfileSettings(
    dpi: clearDpi ? null : dpi ?? this.dpi,
    smartShiftEnabled: clearSmartShiftEnabled
        ? null
        : smartShiftEnabled ?? this.smartShiftEnabled,
    smartShiftThreshold: clearSmartShiftThreshold
        ? null
        : smartShiftThreshold ?? this.smartShiftThreshold,
    hiresWheel: clearHiresWheel ? null : hiresWheel ?? this.hiresWheel,
    invertWheel: clearInvertWheel ? null : invertWheel ?? this.invertWheel,
    scrollSpeed: clearScrollSpeed ? null : scrollSpeed ?? this.scrollSpeed,
    thumbDivert: clearThumbDivert ? null : thumbDivert ?? this.thumbDivert,
    thumbInvert: clearThumbInvert ? null : thumbInvert ?? this.thumbInvert,
    thumbSpeed: clearThumbSpeed ? null : thumbSpeed ?? this.thumbSpeed,
    thumbMode: clearThumbMode ? null : thumbMode ?? this.thumbMode,
    thumbLeftAction: clearThumbLeftAction
        ? null
        : thumbLeftAction ?? this.thumbLeftAction,
    thumbRightAction: clearThumbRightAction
        ? null
        : thumbRightAction ?? this.thumbRightAction,
    buttons: buttons ?? this.buttons,
  );

  ProfileSettings mergedOver(ProfileSettings base) => ProfileSettings(
    dpi: dpi ?? base.dpi,
    smartShiftEnabled: smartShiftEnabled ?? base.smartShiftEnabled,
    smartShiftThreshold: smartShiftThreshold ?? base.smartShiftThreshold,
    hiresWheel: hiresWheel ?? base.hiresWheel,
    invertWheel: invertWheel ?? base.invertWheel,
    scrollSpeed: scrollSpeed ?? base.scrollSpeed,
    thumbDivert: thumbDivert ?? base.thumbDivert,
    thumbInvert: thumbInvert ?? base.thumbInvert,
    thumbSpeed: thumbSpeed ?? base.thumbSpeed,
    thumbMode: thumbMode ?? base.thumbMode,
    thumbLeftAction: thumbLeftAction ?? base.thumbLeftAction,
    thumbRightAction: thumbRightAction ?? base.thumbRightAction,
    buttons: {...base.buttons, ...buttons},
  );

  Map<String, dynamic> toJson() => {
    if (dpi != null) 'dpi': dpi,
    if (smartShiftEnabled != null) 'smartShiftEnabled': smartShiftEnabled,
    if (smartShiftThreshold != null) 'smartShiftThreshold': smartShiftThreshold,
    if (hiresWheel != null) 'hiresWheel': hiresWheel,
    if (invertWheel != null) 'invertWheel': invertWheel,
    if (scrollSpeed != null) 'scrollSpeed': scrollSpeed,
    if (thumbDivert != null) 'thumbDivert': thumbDivert,
    if (thumbInvert != null) 'thumbInvert': thumbInvert,
    if (thumbSpeed != null) 'thumbSpeed': thumbSpeed,
    if (thumbMode != null) 'thumbMode': thumbMode,
    if (thumbLeftAction != null) 'thumbLeftAction': thumbLeftAction,
    if (thumbRightAction != null) 'thumbRightAction': thumbRightAction,
    'buttons': buttons,
  };
}

class ApplicationIdentity {
  const ApplicationIdentity({required this.displayName, this.path});

  factory ApplicationIdentity.fromJson(Map<String, dynamic> json) =>
      ApplicationIdentity(
        displayName: json['displayName'] as String? ?? 'Application',
        path: json['path'] as String?,
      );

  final String displayName;
  final String? path;

  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    if (path != null) 'path': path,
  };
}

class DeviceConfiguration {
  const DeviceConfiguration({
    required this.modelId,
    required this.global,
    required this.apps,
    required this.applicationMetadata,
    required this.settings,
  });

  factory DeviceConfiguration.fromJson(
    Map<String, dynamic> json,
  ) => DeviceConfiguration(
    modelId: json['modelId'] as String? ?? 'unknown',
    global: ProfileSettings.fromJson(
      Map<String, dynamic>.from(json['global'] as Map? ?? const {}),
    ),
    apps: (json['apps'] as Map? ?? const {}).map(
      (key, value) => MapEntry(
        key.toString(),
        ProfileSettings.fromJson(Map<String, dynamic>.from(value as Map)),
      ),
    ),
    applicationMetadata: (json['applicationMetadata'] as Map? ?? const {}).map(
      (key, value) => MapEntry(
        key.toString(),
        ApplicationIdentity.fromJson(Map<String, dynamic>.from(value as Map)),
      ),
    ),
    settings: Map<String, dynamic>.from(json['settings'] as Map? ?? const {}),
  );

  final String modelId;
  final ProfileSettings global;
  final Map<String, ProfileSettings> apps;
  final Map<String, ApplicationIdentity> applicationMetadata;
  final Map<String, dynamic> settings;
}

class AppConfigModel {
  const AppConfigModel({
    required this.revision,
    required this.selectedDeviceId,
    required this.devices,
  });

  factory AppConfigModel.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const AppConfigModel(
        revision: 0,
        selectedDeviceId: null,
        devices: {},
      );
    }
    return AppConfigModel(
      revision: json['revision'] as int? ?? 0,
      selectedDeviceId: json['selectedDeviceId'] as String?,
      devices: (json['devices'] as Map? ?? const {}).map(
        (key, value) => MapEntry(
          key.toString(),
          DeviceConfiguration.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
    );
  }

  final int revision;
  final String? selectedDeviceId;
  final Map<String, DeviceConfiguration> devices;
}

class AppSnapshot {
  const AppSnapshot({
    required this.state,
    required this.devices,
    required this.config,
    required this.frontBundleId,
  });

  factory AppSnapshot.fromJson(Map<String, dynamic> json) {
    final devices = (json['devices'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (value) =>
              DeviceDescriptor.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList();
    final selectedId =
        json['selectedDeviceId'] as String? ?? json['deviceId'] as String?;
    DeviceDescriptor? selected;
    for (final device in devices) {
      if (device.id == selectedId) {
        selected = device;
        break;
      }
    }
    return AppSnapshot(
      state: DeviceState.fromJson(json, descriptor: selected),
      devices: devices,
      config: AppConfigModel.fromJson(
        json['config'] is Map
            ? Map<String, dynamic>.from(json['config'] as Map)
            : null,
      ),
      frontBundleId: json['frontApp'] as String?,
    );
  }

  final DeviceState state;
  final List<DeviceDescriptor> devices;
  final AppConfigModel config;
  final String? frontBundleId;

  DeviceConfiguration? get selectedConfiguration {
    final id = state.deviceId ?? config.selectedDeviceId;
    return id == null ? null : config.devices[id];
  }
}

/// Preset simple actions for buttons / gesture directions.
const kSimpleActionLabels = <String>[
  'Left click',
  'Right click',
  'Middle click',
  'Back',
  'Forward',
  'Undo',
  'Redo',
  'Cut',
  'Copy',
  'Paste',
  'New tab',
  'Close tab',
  'Previous tab',
  'Next tab',
  'Previous app',
  'Next app',
  'Zoom in',
  'Zoom out',
  'Screenshot selection',
  'Screenshot screen',
  'Open application…',
  'Open file…',
  'Open URL…',
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
  'Play/Pause',
  'Next track',
  'Previous track',
  'Disabled',
  'Custom shortcut…',
];

/// Top-level button actions (includes gesture mode).
const kButtonActionLabels = <String>['Gesture (4-way)', ...kSimpleActionLabels];

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
  return keys
      .map((k) {
        final lower = k.toLowerCase();
        return symbols[lower] ?? k.toUpperCase();
      })
      .join('');
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
    case 'Undo':
      return {
        'type': 'keystroke',
        'keys': ['cmd', 'z'],
      };
    case 'Redo':
      return {
        'type': 'keystroke',
        'keys': ['cmd', 'shift', 'z'],
      };
    case 'Cut':
      return {
        'type': 'keystroke',
        'keys': ['cmd', 'x'],
      };
    case 'Copy':
      return {
        'type': 'keystroke',
        'keys': ['cmd', 'c'],
      };
    case 'Paste':
      return {
        'type': 'keystroke',
        'keys': ['cmd', 'v'],
      };
    case 'New tab':
      return {
        'type': 'keystroke',
        'keys': ['cmd', 't'],
      };
    case 'Close tab':
      return {
        'type': 'keystroke',
        'keys': ['cmd', 'w'],
      };
    case 'Previous tab':
      return {
        'type': 'keystroke',
        'keys': ['ctrl', 'shift', 'tab'],
      };
    case 'Next tab':
      return {
        'type': 'keystroke',
        'keys': ['ctrl', 'tab'],
      };
    case 'Previous app':
      return {
        'type': 'keystroke',
        'keys': ['cmd', 'shift', 'tab'],
      };
    case 'Next app':
      return {
        'type': 'keystroke',
        'keys': ['cmd', 'tab'],
      };
    case 'Zoom in':
      return {
        'type': 'keystroke',
        'keys': ['cmd', '+'],
      };
    case 'Zoom out':
      return {
        'type': 'keystroke',
        'keys': ['cmd', '-'],
      };
    case 'Screenshot selection':
      return {
        'type': 'keystroke',
        'keys': ['cmd', 'shift', '4'],
      };
    case 'Screenshot screen':
      return {
        'type': 'keystroke',
        'keys': ['cmd', 'shift', '3'],
      };
    case 'Open application…':
      return {'type': 'open', 'kind': 'app', 'value': ''};
    case 'Open file…':
      return {'type': 'open', 'kind': 'file', 'value': ''};
    case 'Open URL…':
      return {'type': 'open', 'kind': 'url', 'value': ''};
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
    case 'Play/Pause':
      return {'type': 'media', 'id': 'play_pause'};
    case 'Next track':
      return {'type': 'media', 'id': 'next'};
    case 'Previous track':
      return {'type': 'media', 'id': 'previous'};
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
    final d =
        gestureDirections ??
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

String actionStorageKeyFromJson(Map<String, dynamic>? action) {
  if (action == null) return 'Disabled';
  switch (action['type']) {
    case 'mouse':
      return switch (action['button']) {
        'middle' => 'Middle click',
        'back' => 'Back',
        'forward' => 'Forward',
        'left' => 'Left click',
        'right' => 'Right click',
        _ => 'Disabled',
      };
    case 'smartshift_toggle':
      return 'SmartShift toggle';
    case 'gesture':
      return 'Gesture (4-way)';
    case 'system':
      return switch (action['id']) {
        'mission_control' => 'Mission Control',
        'app_expose' => 'App Exposé',
        'launchpad' => 'Launchpad',
        'desktop' || 'show_desktop' => 'Show Desktop',
        'spotlight' => 'Spotlight',
        'previous_desktop' => 'Previous Desktop',
        'next_desktop' => 'Next Desktop',
        _ => 'Disabled',
      };
    case 'media':
      return switch (action['id']) {
        'volume_up' => 'Volume up',
        'volume_down' => 'Volume down',
        'mute' => 'Mute',
        'play_pause' => 'Play/Pause',
        'next' => 'Next track',
        'previous' => 'Previous track',
        _ => 'Disabled',
      };
    case 'keystroke':
      final keys = (action['keys'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList();
      const known = <String, String>{
        'cmd+z': 'Undo',
        'cmd+shift+z': 'Redo',
        'cmd+x': 'Cut',
        'cmd+c': 'Copy',
        'cmd+v': 'Paste',
        'cmd+t': 'New tab',
        'cmd+w': 'Close tab',
        'ctrl+shift+tab': 'Previous tab',
        'ctrl+tab': 'Next tab',
        'cmd+shift+tab': 'Previous app',
        'cmd+tab': 'Next app',
        'cmd++': 'Zoom in',
        'cmd+-': 'Zoom out',
        'cmd+shift+4': 'Screenshot selection',
        'cmd+shift+3': 'Screenshot screen',
      };
      return known[keys.join('+')] ?? 'custom:${keys.join('+')}';
    case 'open':
      return switch (action['kind']) {
        'app' => 'Open application…',
        'file' => 'Open file…',
        'url' => 'Open URL…',
        _ => 'Disabled',
      };
    default:
      return 'Disabled';
  }
}
