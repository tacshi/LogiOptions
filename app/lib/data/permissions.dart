import 'package:flutter/services.dart';

class PermissionStatus {
  const PermissionStatus({
    this.accessibility = false,
    this.inputMonitoring = false,
  });

  final bool accessibility;
  final bool inputMonitoring;

  bool get allGranted => accessibility && inputMonitoring;
}

/// Native channel for the macOS permissions required by the daemon.
class PermissionsService {
  static const _channel = MethodChannel('com.logioptions/permissions');

  /// Optional callback when native poll detects grant (banner can clear).
  void Function(PermissionStatus status)? onChanged;

  PermissionsService() {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'onPermissionsChanged') {
      final m = call.arguments;
      if (m is Map) {
        final status = PermissionStatus(
          accessibility: m['accessibility'] as bool? ?? false,
          inputMonitoring: m['inputMonitoring'] as bool? ?? false,
        );
        onChanged?.call(status);
      }
    }
    return null;
  }

  Future<PermissionStatus> getStatus() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('getStatus');
      return PermissionStatus(
        accessibility: m?['accessibility'] as bool? ?? false,
        inputMonitoring: m?['inputMonitoring'] as bool? ?? false,
      );
    } catch (_) {
      return const PermissionStatus();
    }
  }

  Future<PermissionStatus> request() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('request');
      return PermissionStatus(
        accessibility: m?['accessibility'] as bool? ?? false,
        inputMonitoring: m?['inputMonitoring'] as bool? ?? false,
      );
    } catch (_) {
      return const PermissionStatus();
    }
  }

  Future<void> openAccessibility() =>
      _channel.invokeMethod<void>('openAccessibility');

  Future<void> openInputMonitoring() =>
      _channel.invokeMethod<void>('openInputMonitoring');
}
