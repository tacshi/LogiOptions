@testable import LogiOptionsDaemon
import Foundation
import XCTest

final class DeviceRegistryTests: XCTestCase {
    func testCurrentPointingDeviceCatalogHasExpectedCoverage() {
        XCTAssertEqual(DeviceRegistry.entries.count, 63)
        XCTAssertEqual(
            Set(DeviceRegistry.entries.map(\.modelId)).count,
            DeviceRegistry.entries.count
        )
        XCTAssertTrue(DeviceRegistry.entries.allSatisfy { !$0.controls.isEmpty })
    }

    func testMaster4ExposesItsUniqueCapabilities() throws {
        let device = try XCTUnwrap(
            DeviceRegistry.entries.first { $0.modelId == "2b042" }
        )
        XCTAssertEqual(device.name, "MX Master 4")
        XCTAssertTrue(device.capabilities.haptics)
        XCTAssertTrue(device.capabilities.forceSensing)
        XCTAssertTrue(device.controls.contains { $0.cid == 416 })
        XCTAssertEqual(device.capabilities.dpi?.maximum, 8_000)
    }

    func testRegistryMatchesDirectProductSuffix() {
        let device = DeviceRegistry.entry(
            modelId: nil,
            name: nil,
            productId: 0xB034
        )
        XCTAssertEqual(device?.name, "MX Master 3S")
    }

    func testRuntimeControlsUseHumanReadableMouseLabels() {
        XCTAssertEqual(DeviceRegistry.controlLabel(for: 0x60), "Button 11")
        XCTAssertEqual(DeviceRegistry.controlLabel(for: 0xCE), "Back")
        XCTAssertEqual(
            DeviceRegistry.controlLabel(for: 0xD7),
            "Virtual gesture button"
        )
        XCTAssertEqual(DeviceRegistry.controlLabel(for: 0xED), "DPI change")
    }

    func testOnlyHardwareExercisedModelsAreVerified() {
        XCTAssertFalse(DeviceRegistry.isVerified(modelId: "6B023"))
        XCTAssertTrue(DeviceRegistry.isVerified(modelId: "2b034"))
        XCTAssertTrue(DeviceRegistry.isVerified(modelId: "2B043"))
        XCTAssertFalse(DeviceRegistry.isVerified(modelId: "2b042"))
    }

    func testTransportDistinguishesBoltReceiverAndDirectUsb() {
        XCTAssertEqual(
            HidppDiscovery.normalizedTransport(
                "USB",
                productId: 0xC548,
                isReceiver: true
            ),
            "bolt"
        )
        XCTAssertEqual(
            HidppDiscovery.normalizedTransport(
                "USB",
                productId: 0xC52B,
                isReceiver: true
            ),
            "receiver"
        )
        XCTAssertEqual(
            HidppDiscovery.normalizedTransport(
                "USB",
                productId: 0xB000,
                isReceiver: false
            ),
            "usb"
        )
    }

    func testOnlyExactOptionsCatalogInterfacesAreOpened() {
        XCTAssertFalse(
            DeviceRegistry.shouldInspectHidProduct(
                productId: 0xC547,
                name: "USB Receiver"
            )
        )
        XCTAssertFalse(
            DeviceRegistry.shouldInspectHidProduct(
                productId: 0xB000,
                name: "MX Master 3S"
            )
        )
        XCTAssertTrue(
            DeviceRegistry.shouldInspectHidProduct(
                productId: 0xC548,
                name: "USB Receiver"
            )
        )
        XCTAssertTrue(
            DeviceRegistry.shouldInspectHidProduct(
                productId: 0xB034,
                name: "unknown"
            )
        )
        XCTAssertTrue(
            DeviceRegistry.directProductModels.allSatisfy { productId, modelId in
                DeviceRegistry.shouldInspectHidProduct(
                    productId: productId,
                    name: "irrelevant"
                ) && DeviceRegistry.supports(modelId: modelId)
            }
        )
    }

    func testDeviceInfoIdentityKeepsProductFamilyNibbleAndVariant() {
        let reply = Data([
            0x03,
            0x4A, 0x2F, 0x9B, 0x29,
            0x00,
            0x02, 0xB0, 0x34, 0x00, 0x00, 0x00,
            0x0A,
        ])

        let identity = DeviceFeatures.parseIdentityReply(reply)

        XCTAssertEqual(identity.unitId, "4a2f9b29")
        XCTAssertEqual(identity.modelId, "2b034")
        XCTAssertEqual(identity.extendedModel, 10)
        XCTAssertEqual(
            DeviceRegistry.artworkKey(
                modelId: try! XCTUnwrap(identity.modelId),
                extendedModel: identity.extendedModel
            ),
            "model_2b034_ext10"
        )
    }
}

final class DeviceServiceTests: XCTestCase {
    func testEveryReceiverSlotIsExposedAndDuplicateIdentityIsRemoved() {
        let endpoints = (1 ... 6).map { slot in
            HidppEndpoint(
                interfaceKey: "receiver",
                deviceIndex: UInt8(slot),
                descriptor: descriptor(
                    id: "unit:\(slot)",
                    name: "Mouse \(slot)"
                )
            )
        } + [
            HidppEndpoint(
                interfaceKey: "duplicate-interface",
                deviceIndex: 0xFF,
                descriptor: descriptor(id: "unit:1", name: "Mouse 1")
            ),
        ]
        let service = DeviceService(adapter: FakeDeviceAdapter(endpoints: endpoints))

        _ = service.rescan(preferredDeviceId: nil)

        XCTAssertEqual(
            Set(service.descriptors(includingRecent: []).map(\.id)).count,
            6
        )
    }

    func testFakeAdapterSelectsAndRetainsDisconnectedDevices() throws {
        let endpoint = HidppEndpoint(
            interfaceKey: "fake",
            deviceIndex: 1,
            descriptor: descriptor(id: "unit:one", name: "Test Mouse")
        )
        let adapter = FakeDeviceAdapter(endpoints: [endpoint])
        let service = DeviceService(adapter: adapter)

        XCTAssertTrue(service.rescan(preferredDeviceId: "unit:one"))
        XCTAssertEqual(service.selectedDescriptor?.id, "unit:one")

        adapter.endpoints = []
        XCTAssertTrue(service.rescan(preferredDeviceId: "unit:one"))
        let recent = descriptor(id: "unit:old", name: "Offline Mouse")
        let listed = service.descriptors(includingRecent: [recent])
        XCTAssertEqual(listed.count, 1)
        XCTAssertFalse(try XCTUnwrap(listed.first).connected)
    }

    func testMissingPreferredDeviceDoesNotSelectAnotherProduct() {
        let preferred = HidppEndpoint(
            interfaceKey: "preferred",
            deviceIndex: 1,
            descriptor: descriptor(id: "unit:preferred", name: "Preferred")
        )
        let other = HidppEndpoint(
            interfaceKey: "other",
            deviceIndex: 1,
            descriptor: descriptor(id: "unit:other", name: "Other")
        )
        let adapter = FakeDeviceAdapter(endpoints: [preferred, other])
        let service = DeviceService(adapter: adapter)
        _ = service.rescan(preferredDeviceId: "unit:preferred")

        adapter.endpoints = [other]
        _ = service.rescan(preferredDeviceId: "unit:preferred")

        XCTAssertNil(service.selectedDescriptor)
    }

    private func descriptor(id: String, name: String) -> DeviceDescriptor {
        DeviceDescriptor(
            id: id,
            modelId: "test",
            name: name,
            kind: .mouse,
            transport: "ble",
            connected: true,
            verification: .compatible,
            capabilities: .minimal,
            controls: [
                DeviceControl(cid: 82, label: "Middle", x: 0.5, y: 0.2),
            ],
            artworkKey: "generic_mouse"
        )
    }
}

final class ConfigMigrationTests: XCTestCase {
    func testVersionOneConfigMigratesWithoutLosingProfiles() throws {
        let json = """
        {
          "version": 1,
          "global": {"dpi": 1200, "buttons": {"0x52": {"type": "mouse", "button": "middle"}}},
          "apps": {
            "com.apple.Safari": {"dpi": 800, "buttons": {}}
          }
        }
        """
        let config = try JSONDecoder().decode(
            AppConfig.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(config.version, 3)
        XCTAssertEqual(config.selectedDeviceId, AppConfig.legacyDeviceId)
        XCTAssertEqual(config.global.dpi, 1200)
        XCTAssertEqual(config.apps["com.apple.Safari"]?.dpi, 800)

        let encoded = try JSONEncoder().encode(config)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(object["version"] as? Int, 3)
        XCTAssertNotNil(object["devices"])
        XCTAssertNil(object["global"])
    }

    func testSparseApplicationProfileInheritsEachSetting() {
        let global = ProfileSettings(
            dpi: 1_000,
            smartShiftEnabled: true,
            scrollSpeed: 1.25,
            buttons: ["0x52": .mouse(button: "middle")]
        )
        let application = ProfileSettings(
            dpi: 1_600,
            buttons: ["0x53": .mouse(button: "back")]
        )
        let resolved = application.merged(over: global)

        XCTAssertEqual(resolved.dpi, 1_600)
        XCTAssertEqual(resolved.smartShiftEnabled, true)
        XCTAssertEqual(resolved.scrollSpeed, 1.25)
        XCTAssertNotNil(resolved.buttons["0x52"])
        XCTAssertNotNil(resolved.buttons["0x53"])
    }

    func testUnsupportedGamingDeviceIsPrunedAndSelectionReturnsToOptionsDevice() {
        let supported = DeviceDescriptor(
            id: "unit:master",
            modelId: "6b023",
            name: "MX Master 3",
            kind: .mouse,
            transport: "bolt",
            connected: true,
            verification: .verified,
            capabilities: .minimal,
            controls: [],
            artworkKey: "mx_master"
        )
        let gaming = DeviceDescriptor(
            id: "unit:g502",
            modelId: "c547",
            name: "G502 X LIGHTSPEED",
            kind: .mouse,
            transport: "receiver",
            connected: true,
            verification: .compatible,
            capabilities: .minimal,
            controls: [],
            artworkKey: "generic_mouse"
        )
        var config = AppConfig(
            selectedDeviceId: gaming.id,
            devices: [
                supported.id: DeviceConfiguration(
                    modelId: supported.modelId,
                    global: .defaultGlobal
                ),
                gaming.id: DeviceConfiguration(
                    modelId: gaming.modelId,
                    global: .defaultGlobal
                ),
            ],
            recentDevices: [supported.id: supported, gaming.id: gaming]
        )

        config.pruneUnsupportedDevices()

        XCTAssertNil(config.devices[gaming.id])
        XCTAssertNil(config.recentDevices[gaming.id])
        XCTAssertEqual(config.selectedDeviceId, supported.id)
    }

    func testStableDeviceIdentityCorrectsPreviouslyMisclassifiedModel() {
        let id = "unit:4a2f9b29"
        var config = AppConfig(
            selectedDeviceId: id,
            devices: [
                id: DeviceConfiguration(
                    modelId: "6b023",
                    global: ProfileSettings(dpi: 1_600)
                ),
            ]
        )
        let corrected = DeviceDescriptor(
            id: id,
            modelId: "2b034",
            name: "MX Master 3S",
            kind: .mouse,
            transport: "bolt",
            connected: true,
            verification: .verified,
            capabilities: .minimal,
            controls: [],
            artworkKey: "model_2b034"
        )

        config.ensureDevice(corrected)

        XCTAssertEqual(config.devices[id]?.modelId, "2b034")
        XCTAssertEqual(config.devices[id]?.global.dpi, 1_600)
        XCTAssertEqual(config.recentDevices[id]?.artworkKey, "model_2b034")
    }
}

final class Master4FeatureTests: XCTestCase {
    func testHapticLevelUsesDocumentedFeaturePayload() {
        let hid = FakeHidpp()
        hid.features[.haptic] = (index: 4, version: 1)
        let features = DeviceFeatures(device: hid)

        XCTAssertTrue(features.setHapticLevel(75))
        XCTAssertEqual(
            hid.requests.last,
            FeatureRequest(index: 4, function: 0x20, params: [0x01, 75])
        )
    }

    func testForceThresholdValidatesLimitsAndWritesBigEndian() {
        let hid = FakeHidpp()
        hid.features[.forceSensingButton] = (index: 5, version: 1)
        hid.responses["5:16:0"] = Data([0, 1, 0, 50, 0, 100, 0, 0])
        hid.responses["5:32:0"] = Data([0, 50])
        let features = DeviceFeatures(device: hid)

        XCTAssertTrue(features.setForceThreshold(60))
        XCTAssertEqual(
            hid.requests.last,
            FeatureRequest(index: 5, function: 0x30, params: [0, 0, 60])
        )
        XCTAssertFalse(features.setForceThreshold(101))
    }
}

final class LegacyFeatureTests: XCTestCase {
    func testHidppOneBatteryChargeRegister() {
        let hid = FakeHidpp()
        hid.protocolVersion = 1.0
        hid.legacyResponses[0x0D] = Data([64, 0, 0x50])

        let battery = DeviceFeatures(device: hid).readBattery()

        XCTAssertEqual(battery?.percent, 64)
        XCTAssertEqual(battery?.charging, true)
        XCTAssertEqual(hid.legacyRequests, [0x0D])
    }
}

final class UnifiedBatteryFeatureTests: XCTestCase {
    func testEmptyUnifiedBatterySampleIsIgnored() {
        let hid = FakeHidpp()
        hid.features[.unifiedBattery] = (index: 6, version: 1)
        hid.responses["6:16:"] = Data([0, 0, 0])

        let battery = DeviceFeatures(device: hid).readBattery()

        XCTAssertNil(battery)
    }

    func testUnifiedBatteryLevelFlagRemainsAValidFallback() {
        let hid = FakeHidpp()
        hid.features[.unifiedBattery] = (index: 6, version: 1)
        hid.responses["6:16:"] = Data([0, 0x02, 0])

        let battery = DeviceFeatures(device: hid).readBattery()

        XCTAssertEqual(battery?.percent, 30)
        XCTAssertEqual(battery?.charging, false)
    }
}

final class ProgrammableControlTests: XCTestCase {
    func testOnlyFirmwareDivertableControlsAreExposed() {
        let hid = FakeHidpp()
        hid.features[.reprogControlsV4] = (index: 7, version: 4)
        hid.responses["7:0:"] = Data([3])
        hid.responses["7:16:0"] = controlInfo(cid: 0x50, flags: 0x10)
        hid.responses["7:16:1"] = controlInfo(cid: 0x52, flags: 0x20)
        hid.responses["7:16:2"] = controlInfo(cid: 0xC3, flags: 0x40)

        let controls = DeviceFeatures(device: hid).readProgrammableControls()

        XCTAssertEqual(controls, [0x52, 0xC3])
    }

    private func controlInfo(cid: UInt16, flags: UInt8) -> Data {
        Data([
            UInt8(cid >> 8), UInt8(cid & 0xFF),
            0, 0,
            flags,
            0, 0, 0, 0,
        ])
    }
}

final class PermissionPolicyTests: XCTestCase {
    func testNormalStartupNeverRequestsAccessibility() {
        XCTAssertFalse(
            Permissions.shouldRequestFromUser(
                arguments: ["/Applications/LogiOptionsDaemon"]
            )
        )
    }

    func testExplicitStartCanRequestAccessibilityAgain() {
        XCTAssertTrue(
            Permissions.shouldRequestFromUser(
                arguments: [
                    "/Applications/LogiOptionsDaemon",
                    "--request-accessibility",
                ]
            )
        )
    }
}

private struct FeatureRequest: Equatable {
    var index: UInt8
    var function: UInt8
    var params: [UInt8]
}

private final class FakeHidpp: HidppRequesting {
    let name = "MX Master 4"
    let isReceiver = false
    var protocolVersion = 2.0
    var features: [Hidpp.Feature: (index: UInt8, version: UInt8)] = [:]
    var responses: [String: Data] = [:]
    var legacyResponses: [UInt16: Data] = [:]
    var requests: [FeatureRequest] = []
    var legacyRequests: [UInt16] = []

    func resolveFeature(_ id: Hidpp.Feature) -> (index: UInt8, version: UInt8)? {
        features[id]
    }

    func featureRequest(
        featureIndex: UInt8,
        function: UInt8,
        params: [UInt8]
    ) -> Data? {
        requests.append(
            FeatureRequest(
                index: featureIndex,
                function: function,
                params: params
            )
        )
        return responses[
            "\(featureIndex):\(function):\(params.map(String.init).joined(separator: ","))"
        ] ?? Data()
    }

    func legacyReadRegister(_ register: UInt16, params _: [UInt8]) -> Data? {
        legacyRequests.append(register)
        return legacyResponses[register]
    }
}
