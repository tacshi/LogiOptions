import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// Line-delimited JSON-RPC client to LogiOptionsDaemon Unix socket.
class DaemonClient {
  DaemonClient({String? socketPath})
      : socketPath = socketPath ?? _defaultSocketPath();

  final String socketPath;
  Socket? _socket;
  final _buffer = StringBuffer();
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  int _nextId = 1;
  bool _connecting = false;

  static String _defaultSocketPath() {
    // Must match LogiOptionsDaemon SocketPaths.socket (fixed path).
    return '/tmp/logioptions.sock';
  }

  bool get isConnected => _socket != null;

  Future<bool> connect({Duration timeout = const Duration(seconds: 2)}) async {
    if (_socket != null) return true;
    if (_connecting) return false;
    _connecting = true;
    try {
      final socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
        timeout: timeout,
      );
      _socket = socket;
      socket.listen(
        _onData,
        onError: (_) => _tearDown(),
        onDone: _tearDown,
        cancelOnError: true,
      );
      return true;
    } catch (_) {
      _tearDown();
      return false;
    } finally {
      _connecting = false;
    }
  }

  void disconnect() => _tearDown();

  void _tearDown() {
    _socket?.destroy();
    _socket = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('disconnected'));
      }
    }
    _pending.clear();
    _buffer.clear();
  }

  void _onData(List<int> data) {
    _buffer.write(utf8.decode(data));
    var content = _buffer.toString();
    var idx = content.indexOf('\n');
    while (idx >= 0) {
      final line = content.substring(0, idx).trim();
      content = content.substring(idx + 1);
      if (line.isNotEmpty) {
        _handleLine(line);
      }
      idx = content.indexOf('\n');
    }
    _buffer
      ..clear()
      ..write(content);
  }

  void _handleLine(String line) {
    try {
      final map = jsonDecode(line) as Map<String, dynamic>;
      final id = map['id'];
      if (id is int && _pending.containsKey(id)) {
        final c = _pending.remove(id)!;
        if (map['error'] != null) {
          c.completeError(StateError(map['error'].toString()));
        } else {
          final result = map['result'];
          c.complete(
            result is Map<String, dynamic>
                ? result
                : <String, dynamic>{'value': result},
          );
        }
      }
    } catch (_) {
      // ignore malformed
    }
  }

  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (!await connect()) {
      throw StateError('daemon offline');
    }
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final payload = jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      'params': params ?? {},
      'id': id,
    });
    _socket!.add(utf8.encode('$payload\n'));
    await _socket!.flush();
    return completer.future.timeout(
      // getStatus is cached and should be instant; keep headroom for set* calls.
      const Duration(seconds: 5),
      onTimeout: () {
        _pending.remove(id);
        // Drop half-open connection so the next poll reconnects cleanly.
        _tearDown();
        throw TimeoutException('rpc $method');
      },
    );
  }

  Future<DeviceState> getStatus() async {
    final r = await call('getStatus');
    return DeviceState(
      connected: r['connected'] as bool? ?? false,
      name: r['deviceName'] as String? ?? 'No device',
      modelId: r['modelId'] as String? ?? '2b034',
      connection: _connection(r['connection'] as String?),
      batteryPercent: r['batteryPercent'] as int?,
      charging: r['charging'] as bool? ?? false,
      dpi: r['dpi'] as int? ?? 1000,
      smartShiftEnabled: r['smartShiftEnabled'] as bool? ?? true,
      smartShiftThreshold: r['smartShiftThreshold'] as int? ?? 10,
      hiresWheel: r['hiresWheel'] as bool? ?? true,
      invertWheel: r['invertWheel'] as bool? ?? false,
      scrollSpeed: (r['scrollSpeed'] as num?)?.toDouble() ?? 1.0,
      thumbInvert: r['thumbInvert'] as bool? ?? false,
      thumbSpeed: (r['thumbSpeed'] as num?)?.toDouble() ?? 1.0,
      daemonOnline: r['daemonOnline'] as bool? ?? true,
      optionsPlusRunning: r['optionsPlusRunning'] as bool? ?? false,
      loginAtStartup: r['loginAtStartup'] as bool? ?? false,
      accessibilityTrusted: r['accessibilityTrusted'] as bool? ?? false,
      inputMonitoringTrusted: r['inputMonitoringTrusted'] as bool? ?? false,
    );
  }

  ConnectionType _connection(String? s) {
    switch (s) {
      case 'ble':
        return ConnectionType.ble;
      case 'bolt':
        return ConnectionType.bolt;
      default:
        return ConnectionType.unknown;
    }
  }

  Future<void> setDpi(int dpi) => call('setDpi', {'dpi': dpi});

  Future<void> setSmartShift({required bool enabled, required int threshold}) =>
      call('setSmartShift', {'enabled': enabled, 'threshold': threshold});

  Future<void> setHiResWheel({required bool hires, required bool invert}) =>
      call('setHiResWheel', {'hires': hires, 'invert': invert});

  Future<void> setScrollSpeed(double speed) =>
      call('setScrollSpeed', {'speed': speed});

  Future<void> setThumbWheel({required bool divert, required bool invert}) =>
      call('setThumbWheel', {'divert': divert, 'invert': invert});

  Future<void> setThumbSpeed(double speed) =>
      call('setThumbSpeed', {'speed': speed});

  Future<void> setLoginAtStartup(bool enabled) =>
      call('setLoginItem', {'enabled': enabled});

  /// Stop the background daemon (restores native scroll; Dock UI can stay open).
  Future<void> stopDaemon() => call('stopDaemon');

  Future<void> setButton({
    required String cid,
    required Map<String, dynamic> action,
    String? bundleId,
  }) {
    return call('setButton', {
      'cid': cid,
      'action': action,
      'bundleId': ?bundleId,
    });
  }

  Future<void> reconnect() => call('reconnect');
}
