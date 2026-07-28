import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/daemon_client.dart';
import '../../data/daemon_lifecycle.dart';
import '../../data/models.dart';
import '../../data/permissions.dart';
import '../../data/profile_controller.dart';
import '../apps/apps_page.dart';
import '../buttons/buttons_page.dart';
import '../point_scroll/point_scroll_page.dart';
import '../settings/settings_page.dart';
import '../widgets/device_header.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  final _client = DaemonClient();
  final _permissions = PermissionsService();
  final _daemonLifecycle = DaemonLifecycle();
  late final ProfileController _profiles;
  Timer? _poll;
  DeviceState _state = const DeviceState();
  String? _error;
  PermissionStatus _perms = const PermissionStatus();

  /// User dismissed the banner until next launch / explicit re-check fails.
  bool _permBannerDismissed = false;
  bool _restartingIncompatibleDaemon = false;

  @override
  void initState() {
    super.initState();
    _profiles = ProfileController(_client)..addListener(_profilesChanged);
    WidgetsBinding.instance.addObserver(this);
    // Native poll posts when Accessibility flips on — clear banner without
    // waiting for the next 2s status tick.
    _permissions.onChanged = (status) {
      if (!mounted) return;
      setState(() {
        _perms = status;
        _state = _state.copyWith(
          accessibilityTrusted: status.accessibility,
          inputMonitoringTrusted: status.inputMonitoring,
        );
      });
    };
    _bootstrapPermissions();
    _refresh();
    Future<void>.delayed(const Duration(milliseconds: 600), _refresh);
    Future<void>.delayed(const Duration(milliseconds: 1500), _refresh);
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // User may have toggled Accessibility in System Settings.
    if (state == AppLifecycleState.resumed) {
      _permBannerDismissed = false;
      _refresh();
    }
  }

  Future<void> _bootstrapPermissions() async {
    // Window startup is read-only. Native startup handles the initial prompt,
    // while the in-app Grant action is the only explicit Settings opener.
    final status = await _permissions.getStatus();
    if (!mounted) return;
    setState(() => _perms = status);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _profiles
      ..removeListener(_profilesChanged)
      ..dispose();
    _client.disconnect();
    super.dispose();
  }

  void _profilesChanged() {
    if (!mounted) return;
    setState(() {
      _state = _profiles.state.copyWith(
        accessibilityTrusted: _perms.accessibility,
        inputMonitoringTrusted: _perms.inputMonitoring,
      );
      _error = _profiles.error;
    });
  }

  Future<void> _refresh() async {
    final nativePerms = await _permissions.getStatus();
    try {
      final online = await _client.connect();
      if (!online) {
        if (!mounted) return;
        setState(() {
          _perms = nativePerms;
          _state = _state.copyWith(
            daemonOnline: false,
            connected: false,
            clearBattery: true,
            accessibilityTrusted: nativePerms.accessibility,
            inputMonitoringTrusted: nativePerms.inputMonitoring,
          );
          _error = 'Daemon offline — reopen LogiOptions.app';
        });
        return;
      }
      await _profiles.poll();
      if (_profiles.error?.contains('unknown method getSnapshot') == true) {
        await _restartIncompatibleDaemon();
      }
      if (!mounted) return;
      setState(() {
        _perms = nativePerms;
        _state = _profiles.state.copyWith(
          accessibilityTrusted: nativePerms.accessibility,
          inputMonitoringTrusted: nativePerms.inputMonitoring,
        );
        _error = _profiles.error;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      // Transient RPC blip — don't flash "No daemon" if we were just online.
      final soft = msg.contains('TimeoutException') || msg.contains('rpc ');
      setState(() {
        _perms = nativePerms;
        if (soft && _state.daemonOnline) {
          _error = null;
        } else {
          _state = _state.copyWith(
            daemonOnline: false,
            accessibilityTrusted: nativePerms.accessibility,
            inputMonitoringTrusted: nativePerms.inputMonitoring,
          );
          _error = soft ? 'Connecting to daemon…' : msg;
        }
      });
    }
  }

  Future<void> _restartIncompatibleDaemon() async {
    if (_restartingIncompatibleDaemon) return;
    _restartingIncompatibleDaemon = true;
    _client.disconnect();
    final restarted = await _daemonLifecycle.start(requestAccessibility: false);
    if (restarted) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _profiles.poll();
    }
    _restartingIncompatibleDaemon = false;
  }

  Future<void> _setLoginAtStartup(bool v) async {
    setState(() => _state = _state.copyWith(loginAtStartup: v));
    try {
      await _client.setLoginAtStartup(v);
    } catch (_) {}
    await _refresh();
  }

  Future<void> _stopDaemon() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop daemon?'),
        content: const Text(
          'Remaps and host scroll will stop. Native scroll is restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _client.stopDaemon();
    } catch (_) {
      // Socket may drop as the process exits — expected.
    }
    if (!mounted) return;
    setState(() {
      _state = _state.copyWith(
        daemonOnline: false,
        connected: false,
        clearBattery: true,
      );
    });
    // Give the process a moment to exit, then refresh.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _refresh();
  }

  Future<void> _startDaemon() async {
    final ok = await _daemonLifecycle.start(requestAccessibility: true);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the daemon.')),
      );
    }
    // Wait for RPC bind + device connect.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _refresh();
    if (!mounted) return;
    if (!_state.daemonOnline) {
      // One more poll — first connect can be slow after cold start.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await _refresh();
    }
  }

  Future<void> _fixPermissions() async {
    // Accessibility only — Input Monitoring is not required.
    try {
      await _client.requestAccessibility();
    } catch (_) {
      // The UI process can still register itself and open the pane while the
      // daemon is stopped; Start daemon will register the helper later.
    }
    await _permissions.openAccessibility();
    final after = await _permissions.getStatus();
    if (!mounted) return;
    setState(() => _perms = after);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      ButtonsPage(controller: _profiles),
      PointScrollPage(controller: _profiles),
      AppsPage(
        controller: _profiles,
        onEditProfile: () => setState(() => _tab = 0),
      ),
      SettingsPage(
        state: _state,
        onLoginAtStartup: _setLoginAtStartup,
        onStopDaemon: _stopDaemon,
        onStartDaemon: _startDaemon,
      ),
    ];

    // Accessibility only (daemon or UI process). Input Monitoring not required.
    final missingAccessibility = _state.daemonOnline
        ? !_state.accessibilityTrusted
        : !_perms.accessibility;
    final showPermBanner = !_permBannerDismissed && missingAccessibility;

    // Swallow arrow / Ctrl+arrow so leaked CGEvent hotkeys cannot move the
    // bottom NavigationBar (Spaces must be handled by the daemon via System Events).
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowLeft):
            const DoNothingAndStopPropagationIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight):
            const DoNothingAndStopPropagationIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            const DoNothingAndStopPropagationIntent(),
        SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            const DoNothingAndStopPropagationIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp):
            const DoNothingAndStopPropagationIntent(),
        SingleActivator(LogicalKeyboardKey.arrowDown):
            const DoNothingAndStopPropagationIntent(),
      },
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DeviceHeader(
              state: _state,
              devices: _profiles.devices,
              onDeviceSelected: _profiles.selectDevice,
              onRescan: _profiles.rescan,
            ),
            if (showPermBanner)
              Material(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.privacy_tip_outlined,
                        color: Theme.of(
                          context,
                        ).colorScheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _permissionMessage(),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _fixPermissions,
                        child: const Text('Grant'),
                      ),
                      IconButton(
                        tooltip: 'Dismiss',
                        onPressed: () =>
                            setState(() => _permBannerDismissed = true),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            if (_state.optionsPlusRunning)
              MaterialBanner(
                content: const Text(
                  'Logi Options+ is running and will conflict.',
                ),
                actions: [
                  TextButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            if (_error != null && !_state.daemonOnline)
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            Expanded(child: pages[_tab]),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.mouse_outlined),
              selectedIcon: Icon(Icons.mouse),
              label: 'Buttons',
            ),
            NavigationDestination(
              icon: Icon(Icons.speed_outlined),
              selectedIcon: Icon(Icons.speed),
              label: 'Point & scroll',
            ),
            NavigationDestination(
              icon: Icon(Icons.apps_outlined),
              selectedIcon: Icon(Icons.apps),
              label: 'Apps',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  String _permissionMessage() {
    return 'Enable Accessibility for LogiOptions and LogiOptionsDaemon '
        '(System Settings → Privacy & Security → Accessibility).';
  }
}
