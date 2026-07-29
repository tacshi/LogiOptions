import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logi_options/data/daemon_client.dart';
import 'package:logi_options/data/models.dart';
import 'package:logi_options/data/profile_controller.dart';
import 'package:logi_options/ui/point_scroll/point_scroll_page.dart';
import 'package:logi_options/ui/widgets/device_header.dart';
import 'package:logi_options/ui/widgets/device_illustration.dart';

void main() {
  group('multi-device models', () {
    test('hydrates runtime controls and MX Master 4 capabilities', () {
      final descriptor = DeviceDescriptor.fromJson({
        'id': 'unit:master4',
        'modelId': '2b042',
        'name': 'MX Master 4',
        'kind': 'mouse',
        'transport': 'bolt',
        'connected': true,
        'verification': 'compatible',
        'artworkKey': 'mx_master_4',
        'capabilities': {
          'battery': true,
          'dpi': {'minimum': 200, 'maximum': 8000, 'step': 50},
          'haptics': true,
          'forceSensing': true,
        },
        'controls': [
          for (final cid in [82, 83, 86, 195, 196, 416])
            {'cid': cid, 'label': 'Control $cid', 'x': .5, 'y': .5},
        ],
      });

      expect(descriptor.controls, hasLength(6));
      expect(descriptor.controls.last.cidHex, '0x1A0');
      expect(descriptor.capabilities.haptics, isTrue);
      expect(descriptor.capabilities.forceSensing, isTrue);
      expect(descriptor.capabilities.dpi?.maximum, 8000);
      expect(descriptor.verified, isFalse);
    });

    test('resolves sparse application values over Global independently', () {
      const global = ProfileSettings(
        dpi: 1000,
        smartShiftEnabled: true,
        scrollSpeed: 1.25,
        buttons: {
          '0x52': {'type': 'mouse', 'button': 'middle'},
        },
      );
      const application = ProfileSettings(
        dpi: 1600,
        buttons: {
          '0x53': {'type': 'mouse', 'button': 'back'},
        },
      );

      final resolved = application.mergedOver(global);
      expect(resolved.dpi, 1600);
      expect(resolved.smartShiftEnabled, isTrue);
      expect(resolved.scrollSpeed, 1.25);
      expect(resolved.buttons.keys, containsAll(['0x52', '0x53']));
    });

    test('round-trips open targets and productivity actions', () {
      expect(
        actionStorageKeyFromJson({
          'type': 'open',
          'kind': 'url',
          'value': 'https://example.com',
        }),
        'Open URL…',
      );
      expect(simpleActionJsonForLabel('Undo'), {
        'type': 'keystroke',
        'keys': ['cmd', 'z'],
      });
    });

    test('does not expose a disconnected configuration as live state', () {
      const snapshot = AppSnapshot(
        state: DeviceState(connected: false),
        devices: [],
        config: AppConfigModel(
          revision: 1,
          selectedDeviceId: 'unit:old',
          devices: {
            'unit:old': DeviceConfiguration(
              modelId: '2b034',
              global: ProfileSettings(dpi: 1600),
              apps: {},
              applicationMetadata: {},
              settings: {},
            ),
          },
        ),
        frontBundleId: null,
      );

      expect(snapshot.selectedConfiguration, isNull);
    });
  });

  group('profile controller', () {
    test('clears cached device data when daemon polling fails', () async {
      final client = _FakeDaemonClient(_snapshot());
      final controller = ProfileController(client);
      addTearDown(controller.dispose);

      await controller.load();
      expect(controller.state.daemonOnline, isTrue);
      expect(controller.state.connected, isTrue);

      client.failReads = true;
      await controller.poll();
      expect(controller.state.daemonOnline, isFalse);
      expect(controller.state.connected, isFalse);
      expect(controller.state.name, 'No device');
      expect(controller.state.deviceId, isNull);
      expect(controller.state.modelId, 'unknown');
      expect(controller.state.connection, ConnectionType.unknown);
      expect(controller.state.batteryPercent, isNull);
      expect(controller.state.capabilities, const DeviceCapabilities());
      expect(controller.state.controls, isEmpty);
      expect(controller.devices, isEmpty);
      expect(controller.deviceConfiguration, isNull);
    });

    test(
      'rolls back an optimistic profile after a structured failure',
      () async {
        final client = _FakeDaemonClient(_snapshot())..failWrites = true;
        final controller = ProfileController(client);
        addTearDown(controller.dispose);
        await controller.load();

        controller.updateProfile(
          controller.editableProfile.copyWith(dpi: 2200),
        );
        expect(controller.editableProfile.dpi, 2200);
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(controller.editableProfile.dpi, 1000);
        expect(controller.error, contains('unsupported'));
      },
    );

    test('coalesces continuous device setting changes', () async {
      final client = _FakeDaemonClient(_snapshot());
      final controller = ProfileController(client);
      addTearDown(controller.dispose);
      await controller.load();

      await controller.patchDeviceSettings({'hapticLevel': 20}, debounce: true);
      await controller.patchDeviceSettings({'hapticLevel': 60}, debounce: true);
      await Future<void>.delayed(const Duration(milliseconds: 260));

      expect(client.deviceSettingWrites, hasLength(1));
      expect(client.deviceSettingWrites.single['hapticLevel'], 60);
    });
  });

  testWidgets('capability layout exposes the supported haptic settings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = ProfileController(_FakeDaemonClient(_snapshot()));
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(home: PointScrollPage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Haptic Sense'), findsOneWidget);
    expect(find.text('Feedback level'), findsOneWidget);
  });

  testWidgets('uses full-resolution model artwork and compact thumbnail', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 400,
          height: 600,
          child: DeviceIllustration(
            artworkKey: 'model_2b034',
            modelId: '2b034',
          ),
        ),
      ),
    );
    await tester.pump();

    var image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/devices/editor/2b034.png',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: DeviceIllustration(
          artworkKey: 'model_2b034_ext1',
          modelId: '2b034',
          compact: true,
        ),
      ),
    );
    await tester.pump();

    image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/devices/catalog/2b034_ext1.png',
    );
  });

  testWidgets('shows device discovery while the daemon starts', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DeviceHeader(
          state: const DeviceState(daemonOnline: true),
          devices: const [],
          detectingDevice: true,
          onDeviceSelected: (_) {},
          onRescan: () {},
        ),
      ),
    );

    expect(find.text('Detecting device…'), findsOneWidget);
    expect(find.text('No device'), findsNothing);
  });
}

AppSnapshot _snapshot() {
  const descriptor = DeviceDescriptor(
    id: 'unit:test',
    modelId: '2b042',
    name: 'MX Master 4',
    kind: 'mouse',
    connection: ConnectionType.bolt,
    connected: true,
    verified: false,
    capabilities: DeviceCapabilities(haptics: true, forceSensing: true),
    controls: [DeviceControl(cid: 82, label: 'Middle button', x: .5, y: .2)],
    artworkKey: 'mx_master_4',
  );
  const configuration = DeviceConfiguration(
    modelId: '2b042',
    global: ProfileSettings(dpi: 1000),
    apps: {},
    applicationMetadata: {},
    settings: {'hapticLevel': 40},
  );
  return AppSnapshot(
    state: DeviceState(
      connected: true,
      name: 'MX Master 4',
      deviceId: 'unit:test',
      modelId: '2b042',
      connection: ConnectionType.bolt,
      capabilities: descriptor.capabilities,
      controls: descriptor.controls,
      artworkKey: descriptor.artworkKey,
      batteryPercent: 80,
      daemonOnline: true,
    ),
    devices: const [descriptor],
    config: const AppConfigModel(
      revision: 7,
      selectedDeviceId: 'unit:test',
      devices: {'unit:test': configuration},
    ),
    frontBundleId: null,
  );
}

class _FakeDaemonClient extends DaemonClient {
  _FakeDaemonClient(this.current) : super(socketPath: '/tmp/not-used');

  AppSnapshot current;
  bool failReads = false;
  bool failWrites = false;
  final List<Map<String, dynamic>> deviceSettingWrites = [];

  @override
  Future<AppSnapshot> getSnapshot() async {
    if (failReads) throw StateError('daemon offline');
    return current;
  }

  @override
  Future<Map<String, dynamic>> putProfile({
    required String deviceId,
    required ProfileSettings profile,
    required int expectedRevision,
    String? bundleId,
    ApplicationIdentity? application,
  }) async {
    if (failWrites) {
      throw const DaemonRpcException(
        'unsupported_capability',
        'unsupported setting',
      );
    }
    return {};
  }

  @override
  Future<Map<String, dynamic>> patchDeviceSettings({
    required String deviceId,
    required Map<String, dynamic> settings,
    required int expectedRevision,
  }) async {
    deviceSettingWrites.add(Map<String, dynamic>.from(settings));
    return {};
  }
}
