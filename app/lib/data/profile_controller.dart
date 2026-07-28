import 'dart:async';

import 'package:flutter/foundation.dart';

import 'daemon_client.dart';
import 'models.dart';

/// Deep UI module for device selection, profile inheritance, optimistic edits,
/// revision conflicts, write serialization, and polling coalescence.
class ProfileController extends ChangeNotifier {
  ProfileController(this.client);

  final DaemonClient client;
  AppSnapshot? _snapshot;
  String? _selectedBundleId;
  ProfileSettings? _optimisticProfile;
  final Map<String, dynamic> _optimisticDeviceSettings = {};
  Timer? _saveDebounce;
  Timer? _deviceSettingsDebounce;
  bool _loading = false;
  bool _writing = false;
  bool _reachable = false;
  String? _error;

  AppSnapshot? get snapshot => _snapshot;
  DeviceState get state {
    final current = _snapshot?.state ?? const DeviceState();
    return _reachable
        ? current
        : current.copyWith(
            connected: false,
            daemonOnline: false,
            clearBattery: true,
          );
  }

  List<DeviceDescriptor> get devices => _snapshot?.devices ?? const [];
  AppConfigModel get config =>
      _snapshot?.config ??
      const AppConfigModel(revision: 0, selectedDeviceId: null, devices: {});
  String? get selectedBundleId => _selectedBundleId;
  bool get loading => _loading;
  bool get writing => _writing;
  String? get error => _error;

  DeviceConfiguration? get deviceConfiguration =>
      _snapshot?.selectedConfiguration;

  Map<String, dynamic> get deviceSettings => {
    ...?deviceConfiguration?.settings,
    ..._optimisticDeviceSettings,
  };

  ProfileSettings get globalProfile =>
      deviceConfiguration?.global ?? const ProfileSettings();

  ProfileSettings get storedProfile {
    if (_selectedBundleId == null) return globalProfile;
    return deviceConfiguration?.apps[_selectedBundleId] ??
        const ProfileSettings();
  }

  ProfileSettings get editableProfile => _optimisticProfile ?? storedProfile;

  ProfileSettings get resolvedProfile {
    if (_selectedBundleId == null) return editableProfile;
    return editableProfile.mergedOver(globalProfile);
  }

  List<String?> get profileIds {
    final ids = deviceConfiguration?.apps.keys.toList() ?? <String>[];
    ids.sort();
    return [null, ...ids];
  }

  Future<void> load() async {
    if (_loading || _writing) return;
    _loading = true;
    try {
      _snapshot = await client.getSnapshot();
      _reachable = true;
      _error = null;
    } catch (error) {
      _reachable = false;
      _error = error.toString();
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> poll() async {
    if (_loading || _writing || _saveDebounce?.isActive == true) return;
    try {
      _snapshot = await client.getSnapshot();
      _reachable = true;
      _error = null;
      notifyListeners();
    } catch (error) {
      _reachable = false;
      _error = error.toString();
      notifyListeners();
    }
  }

  void selectProfile(String? bundleId) {
    _saveDebounce?.cancel();
    _optimisticProfile = null;
    _selectedBundleId = bundleId;
    _error = null;
    notifyListeners();
  }

  Future<void> selectDevice(String deviceId) async {
    if (deviceId == state.deviceId || _writing) return;
    _writing = true;
    _error = null;
    notifyListeners();
    try {
      _snapshot = await client.selectDevice(
        deviceId: deviceId,
        expectedRevision: config.revision,
      );
      _reachable = true;
      _selectedBundleId = null;
      _optimisticProfile = null;
    } on DaemonRpcException catch (error) {
      if (error.code == 'revision_conflict') {
        await _reloadWithoutNotification();
      }
      _error = error.message;
    } catch (error) {
      _reachable = false;
      _error = error.toString();
    } finally {
      _writing = false;
      notifyListeners();
    }
  }

  Future<void> rescan() async {
    if (_writing) return;
    _writing = true;
    notifyListeners();
    try {
      _snapshot = await client.rescanDevices();
      _reachable = true;
      _error = null;
    } catch (error) {
      _reachable = false;
      _error = error.toString();
    } finally {
      _writing = false;
      notifyListeners();
    }
  }

  void updateProfile(ProfileSettings profile, {bool debounce = false}) {
    _optimisticProfile = profile;
    _error = null;
    notifyListeners();
    _saveDebounce?.cancel();
    if (debounce) {
      _saveDebounce = Timer(
        const Duration(milliseconds: 180),
        () => _saveProfile(profile),
      );
    } else {
      unawaited(_saveProfile(profile));
    }
  }

  void updateButton(DeviceControl control, Map<String, dynamic> action) {
    final buttons = Map<String, Map<String, dynamic>>.from(
      editableProfile.buttons,
    );
    buttons[control.cidHex] = action;
    updateProfile(editableProfile.copyWith(buttons: buttons));
  }

  Future<void> addApplication({
    required String bundleId,
    required ApplicationIdentity application,
    ProfileSettings profile = const ProfileSettings(),
  }) async {
    _selectedBundleId = bundleId;
    _optimisticProfile = profile;
    notifyListeners();
    await _saveProfile(profile, application: application);
  }

  Future<void> deleteSelectedApplication() async {
    final deviceId = state.deviceId;
    final bundleId = _selectedBundleId;
    if (deviceId == null || bundleId == null || _writing) return;
    _writing = true;
    notifyListeners();
    try {
      await client.deleteProfile(
        deviceId: deviceId,
        bundleId: bundleId,
        expectedRevision: config.revision,
      );
      _selectedBundleId = null;
      _optimisticProfile = null;
      await _reloadWithoutNotification();
      _error = null;
    } catch (error) {
      _error = error.toString();
    } finally {
      _writing = false;
      notifyListeners();
    }
  }

  Future<void> patchDeviceSettings(
    Map<String, dynamic> settings, {
    bool debounce = false,
  }) async {
    _optimisticDeviceSettings.addAll(settings);
    _error = null;
    notifyListeners();
    _deviceSettingsDebounce?.cancel();
    if (debounce) {
      _deviceSettingsDebounce = Timer(
        const Duration(milliseconds: 180),
        _saveDeviceSettings,
      );
      return;
    }
    await _saveDeviceSettings();
  }

  Future<void> _saveDeviceSettings() async {
    final deviceId = state.deviceId;
    if (deviceId == null || _optimisticDeviceSettings.isEmpty) return;
    while (_writing) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final pending = Map<String, dynamic>.from(_optimisticDeviceSettings);
    _writing = true;
    notifyListeners();
    try {
      await client.patchDeviceSettings(
        deviceId: deviceId,
        settings: pending,
        expectedRevision: config.revision,
      );
      await _reloadWithoutNotification();
      _reachable = true;
      for (final entry in pending.entries) {
        if (_optimisticDeviceSettings[entry.key] == entry.value) {
          _optimisticDeviceSettings.remove(entry.key);
        }
      }
      _error = null;
    } on DaemonRpcException catch (error) {
      for (final key in pending.keys) {
        _optimisticDeviceSettings.remove(key);
      }
      if (error.code == 'revision_conflict') {
        await _reloadWithoutNotification();
      }
      _error = error.message;
    } catch (error) {
      for (final key in pending.keys) {
        _optimisticDeviceSettings.remove(key);
      }
      _reachable = false;
      _error = error.toString();
    } finally {
      _writing = false;
      notifyListeners();
      if (_optimisticDeviceSettings.isNotEmpty) {
        _deviceSettingsDebounce = Timer(
          const Duration(milliseconds: 20),
          _saveDeviceSettings,
        );
      }
    }
  }

  Future<void> _saveProfile(
    ProfileSettings profile, {
    ApplicationIdentity? application,
  }) async {
    final deviceId = state.deviceId;
    if (deviceId == null) return;
    while (_writing) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    _writing = true;
    notifyListeners();
    try {
      await client.putProfile(
        deviceId: deviceId,
        profile: profile,
        expectedRevision: config.revision,
        bundleId: _selectedBundleId,
        application: application,
      );
      await _reloadWithoutNotification();
      _reachable = true;
      _optimisticProfile = null;
      _error = null;
    } on DaemonRpcException catch (error) {
      _optimisticProfile = null;
      if (error.code == 'revision_conflict') {
        await _reloadWithoutNotification();
      }
      _error = error.message;
    } catch (error) {
      _optimisticProfile = null;
      _reachable = false;
      _error = error.toString();
    } finally {
      _writing = false;
      notifyListeners();
    }
  }

  Future<void> _reloadWithoutNotification() async {
    _snapshot = await client.getSnapshot();
    _reachable = true;
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _deviceSettingsDebounce?.cancel();
    super.dispose();
  }
}
