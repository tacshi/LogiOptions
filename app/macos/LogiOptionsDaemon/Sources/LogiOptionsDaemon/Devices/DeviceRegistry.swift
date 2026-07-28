import Foundation

enum DeviceRegistry {
    static let verifiedModelIds: Set<String> = ["2b034", "2b043"]

    /// Exact DEVIO interfaces from the Options+ mouse/trackball catalog.
    ///
    /// Discovery is deliberately positive: a Logitech vendor-page interface is
    /// never opened merely because its name looks like a mouse. This keeps
    /// G-series devices owned by G Hub, including models we have never seen.
    static let directProductModels: [Int: String] = [
        0x1017: "41017",
        0x101A: "4101a",
        0x101B: "4101b",
        0x1028: "41028",
        0x4040: "4040",
        0x4041: "6b012",
        0x404A: "6b013",
        0x4050: "44050",
        0x4051: "44051",
        0x4052: "44052",
        0x4054: "4054",
        0x4055: "44055",
        0x4057: "44057",
        0x4058: "44058",
        0x405E: "6b015",
        0x4060: "6b017",
        0x4063: "6b018",
        0x4069: "6b019",
        0x406A: "6b01a",
        0x406B: "6b01b",
        0x406D: "4406d",
        0x406F: "6b01d",
        0x4071: "6b01e",
        0x4072: "6b01f",
        0x407B: "eb020",
        0x4082: "6b023",
        0x4090: "6b025",
        0x4091: "4091",
        0x4094: "44094",
        0x4096: "6b027",
        0xABDD: "8c0a2",
        0xB012: "6b012",
        0xB013: "6b013",
        0xB014: "1b014",
        0xB015: "6b015",
        0xB016: "1b016",
        0xB017: "6b017",
        0xB018: "6b018",
        0xB019: "6b019",
        0xB01A: "6b01a",
        0xB01B: "6b01b",
        0xB01D: "6b01d",
        0xB01E: "6b01e",
        0xB01F: "6b01f",
        0xB020: "eb020",
        0xB023: "6b023",
        0xB025: "6b025",
        0xB027: "6b027",
        0xB028: "2b028",
        0xB02A: "2b02a",
        0xB02B: "2b02b",
        0xB02C: "2b02c",
        0xB02D: "2b02d",
        0xB02F: "2b02f",
        0xB030: "2b030",
        0xB031: "2b031",
        0xB032: "2b032",
        0xB033: "2b033",
        0xB034: "2b034",
        0xB035: "2b035",
        0xB036: "2b036",
        0xB037: "2b037",
        0xB038: "2b038",
        0xB03A: "2b03a",
        0xB03B: "2b03b",
        0xB03D: "2b03d",
        0xB03E: "2b03e",
        0xB040: "2b040",
        0xB041: "2b041",
        0xB042: "2b042",
        0xB043: "2b043",
        0xB044: "2b044",
        0xB045: "2b045",
        0xB047: "2b047",
        0xB048: "2b048",
        0xB049: "2b049",
        0xB04B: "2b04b",
        0xC08A: "eb020",
        0xC093: "8c093",
        0xC0A2: "8c0a2",
    ]

    static let entries: [DeviceCatalogEntry] = [
        master("6b023", "MX Master 3", maxDpi: 4_000),
        anywhere("6b025", "MX Anywhere 3", maxDpi: 4_000, smartShift: true),
        standard("44057", "M275/M280/M320/M330/M331", [82]),
        standard("4040", "M275/M280/M320/M330/M331", [82]),
        standard("44058", "M275/M280/M320/M330/M331", [82]),
        standard("2b02b", "Signature M550 L", [82]),
        standard("2b02a", "Signature M650 L", [82, 83, 86]),
        standard("2b032", "Signature M650 for Business", [82, 83, 86]),
        standard("2b02c", "Signature Plus M750 L", [82, 83, 86, 253]),
        master("2b028", "MX Master 3 for Business", maxDpi: 4_000),
        anywhere("2b02d", "MX Anywhere 3 for Business", maxDpi: 4_000, smartShift: true),
        trackball("6b01d", "MX Ergo", [82, 83, 86, 91, 93, 237]),
        vertical("2b031", "Lift", [82, 83, 86, 253]),
        vertical("2b033", "Lift for Business", [82, 83, 86, 253]),
        master("2b034", "MX Master 3S", maxDpi: 8_000),
        master("2b035", "MX Master 3S for Business", maxDpi: 8_000),
        master("2b043", "MX Master 3S", maxDpi: 8_000),
        master("2b044", "MX Master 3S for Business", maxDpi: 8_000),
        standard("2b030", "POP Mouse", [82, 264], hiRes: true),
        standard("44051", "M510", [82, 83, 86, 91, 93], hiRes: true),
        standard("44055", "Wireless Mouse", [82], hiRes: true),
        trackball("6b027", "Ergo M575", [82, 83, 86], hiRes: false),
        trackball("2b02f", "Ergo M575 for Business", [82, 83, 86]),
        vertical("eb020", "MX Vertical", [82, 83, 86, 253]),
        standard("6b015", "M720 Triathlon", [82, 83, 86, 91, 93, 208], hiRes: true),
        standard("4091", "Wireless Mouse", [82], hiRes: true),
        standard("4054", "Wireless Mouse", [82], hiRes: true),
        anywhere("6b013", "MX Anywhere 2", maxDpi: 4_000),
        anywhere("6b018", "MX Anywhere 2", maxDpi: 4_000),
        anywhere("6b01f", "MX Anywhere 2", maxDpi: 4_000),
        anywhere("6b01a", "MX Anywhere 2S", maxDpi: 4_000),
        master("6b019", "MX Master 2S", maxDpi: 4_000),
        standard("8c093", "M500s", [82, 83, 86, 91, 93], battery: false, hiRes: true),
        standard("6b01b", "M585/M590", [82, 83, 86, 91, 93]),
        standard("44052", "M545/M546", [82, 83, 86, 91, 93], hiRes: true),
        standard("44094", "M325", [82, 83, 86], hiRes: true),
        master("6b012", "MX Master", maxDpi: 4_000),
        master("6b01e", "MX Master", maxDpi: 4_000),
        master("6b017", "MX Master", maxDpi: 4_000),
        standard("1b016", "M336 / M337 / M535", [82, 206, 207, 208], hiRes: true),
        standard("44050", "M335", [82, 83, 86, 204], hiRes: true),
        standard("1b014", "M336/M337/M535", [82, 206, 207, 208], hiRes: true),
        standard("4101b", "M705", [82, 83, 86, 89, 91, 93]),
        standard("4406d", "M705", [82, 83, 86, 91, 93], hiRes: true),
        standard("41017", "MX Anywhere", [82, 83, 86, 91, 93], battery: false, hiRes: true),
        trackball("41028", "M570", [82, 83, 86], hiRes: false),
        standard("4101a", "Performance MX", [82, 83, 86, 89, 91, 93, 94], hiRes: true),
        standard("2b03b", "M240 Silent for Business", [82]),
        standard("2b03a", "M240 Silent", [82]),
        anywhere("2b037", "MX Anywhere 3S", maxDpi: 8_000, smartShift: true),
        anywhere("2b038", "MX Anywhere 3S for Business", maxDpi: 8_000, smartShift: true),
        standard("2b036", "Pebble Mouse 2 M350s", [82]),
        standard("2b03d", "Signature Plus M750 L for Business", [82, 83, 86, 253]),
        trackball("2b03e", "MX Ergo S", [82, 83, 86, 91, 93, 253], dpi: DpiRange(minimum: 100, maximum: 2_000, step: 50)),
        standard("2b040", "Signature AI Edition M750", [82, 83, 86, 253]),
        trackball("2b041", "ERGO M575S Trackball", [82, 83, 86]),
        master4("2b042", "MX Master 4"),
        master4("2b048", "MX Master 4 for Business"),
        standard("8c0a2", "Signature Wired M520 L for Business", [82, 253], battery: false),
        standard("2b045", "Mobi Fold", [83, 86], dpi: DpiRange(minimum: 400, maximum: 4_000, step: 100)),
        standard("2b047", "Mobi Fold for Business", [83, 86]),
        standard("2b049", "Signature Comfort Plus M850 L", [82, 83, 86, 253]),
        standard("2b04b", "Signature Comfort Plus M850 L for Business", [82, 83, 86, 253]),
    ]

    static func entry(modelId: String?, name: String?, productId: Int) -> DeviceCatalogEntry? {
        let baseModelId = modelId?
            .lowercased()
            .components(separatedBy: "_ext")
            .first
        if let baseModelId,
           let exact = entries.first(where: {
               $0.modelId.caseInsensitiveCompare(baseModelId) == .orderedSame
           }) {
            return exact
        }
        if let catalogModelId = directProductModels[productId],
           let direct = entries.first(where: {
               $0.modelId.caseInsensitiveCompare(catalogModelId) == .orderedSame
           }) {
            return direct
        }
        // Product names are presentation strings, not identities. In
        // particular, prefix/fuzzy matching confuses MX Master 3 and 3S.
        _ = name
        return nil
    }

    static func fallback(name: String, productId: Int) -> DeviceCatalogEntry {
        DeviceCatalogEntry(
            modelId: String(format: "%04x", productId),
            name: name == "unknown" ? "Compatible Logitech pointing device" : name,
            kind: .mouse,
            capabilities: .minimal,
            controls: [],
            artworkKey: "generic_mouse"
        )
    }

    static func isVerified(modelId: String) -> Bool {
        verifiedModelIds.contains(modelId.lowercased())
    }

    static func supports(modelId: String) -> Bool {
        entries.contains {
            $0.modelId.caseInsensitiveCompare(modelId) == .orderedSame
        }
    }

    static func shouldInspectHidProduct(productId: Int, name _: String) -> Bool {
        Hidpp.receiverProductIds.contains(productId)
            || directProductModels[productId] != nil
    }

    static func artworkKey(modelId: String, extendedModel: Int?) -> String {
        let base = "model_\(modelId.lowercased())"
        guard let extendedModel, extendedModel > 0 else { return base }
        return "\(base)_ext\(extendedModel)"
    }

    static func controlLabel(for cid: UInt16) -> String {
        switch cid {
        case 0x50: return "Left button"
        case 0x51: return "Right button"
        case 0x52: return "Middle button"
        case 0x53, 0x54, 0x55: return "Back"
        case 0x56, 0x57, 0x58: return "Forward"
        case 0x59: return "Button 6"
        case 0x5A, 0x5B: return "Wheel tilt left"
        case 0x5C, 0x5D: return "Wheel tilt right"
        case 0x5E: return "Button 9"
        case 0x5F: return "Button 10"
        case 0x60...0x6D: return "Button \(Int(cid) - 0x55)"
        case 0x97: return "Horizontal scroll"
        case 0xAA: return "Zoom in"
        case 0xAB: return "Zoom out"
        case 0xAC: return "Back (horizontal scroll)"
        case 0xBF: return "Screen capture"
        case 0xC3: return "Gesture button"
        case 0xC4: return "Mode shift"
        case 0xCE: return "Back"
        case 0xCF: return "Forward"
        case 0xD0: return "Gesture button"
        case 0xD7: return "Virtual gesture button"
        case 0xD8: return "Cursor button (long press)"
        case 0xD9: return "Next button"
        case 0xDA: return "Next button (long press)"
        case 0xDB: return "Back button"
        case 0xDC: return "Back button (long press)"
        case 0xE0: return "Mission Control"
        case 0xE1: return "Launchpad"
        case 0xED: return "DPI change"
        case 0xEE: return "Open new tab"
        case 0xFD: return "Pointer speed"
        case 0x1A0: return "Haptic Sense panel"
        default: return String(format: "Button 0x%X", cid)
        }
    }

    private static func master(_ id: String, _ name: String, maxDpi: Int) -> DeviceCatalogEntry {
        var result = entry(
            id,
            name,
            controls: [82, 83, 86, 195, 196],
            dpi: DpiRange(minimum: 200, maximum: maxDpi, step: 50),
            hiRes: true,
            smartShift: true,
            thumb: true,
            artwork: "mx_master"
        )
        // Options+ side-art coordinates for the MX Master chassis.
        result.controls = [
            DeviceControl(cid: 82, label: controlLabel(for: 82), x: 0.71, y: 0.15),
            DeviceControl(cid: 83, label: controlLabel(for: 83), x: 0.45, y: 0.60),
            DeviceControl(cid: 86, label: controlLabel(for: 86), x: 0.35, y: 0.43),
            DeviceControl(cid: 195, label: controlLabel(for: 195), x: 0.08, y: 0.58),
            DeviceControl(cid: 196, label: controlLabel(for: 196), x: 0.81, y: 0.34),
        ]
        return result
    }

    private static func master4(_ id: String, _ name: String) -> DeviceCatalogEntry {
        entry(
            id,
            name,
            controls: [82, 83, 86, 195, 196, 416],
            dpi: DpiRange(minimum: 200, maximum: 8_000, step: 50),
            hiRes: true,
            smartShift: true,
            thumb: true,
            haptics: true,
            force: true,
            artwork: "mx_master_4"
        )
    }

    private static func anywhere(
        _ id: String,
        _ name: String,
        maxDpi: Int,
        smartShift: Bool = false
    ) -> DeviceCatalogEntry {
        entry(
            id,
            name,
            controls: [82, 83, 86, 196],
            dpi: DpiRange(minimum: 200, maximum: maxDpi, step: 50),
            hiRes: true,
            smartShift: smartShift,
            artwork: "mx_anywhere"
        )
    }

    private static func vertical(_ id: String, _ name: String, _ controls: [UInt16]) -> DeviceCatalogEntry {
        entry(id, name, controls: controls, hiRes: true, artwork: "vertical")
    }

    private static func trackball(
        _ id: String,
        _ name: String,
        _ controls: [UInt16],
        hiRes: Bool = true,
        dpi: DpiRange = DpiRange(minimum: 200, maximum: 4_000, step: 50)
    ) -> DeviceCatalogEntry {
        entry(id, name, kind: .trackball, controls: controls, dpi: dpi, hiRes: hiRes, artwork: "trackball")
    }

    private static func standard(
        _ id: String,
        _ name: String,
        _ controls: [UInt16],
        battery: Bool = true,
        hiRes: Bool = false,
        dpi: DpiRange = DpiRange(minimum: 200, maximum: 4_000, step: 50)
    ) -> DeviceCatalogEntry {
        entry(id, name, controls: controls, battery: battery, dpi: dpi, hiRes: hiRes, artwork: "standard_mouse")
    }

    private static func entry(
        _ id: String,
        _ name: String,
        kind: PointingDeviceKind = .mouse,
        controls: [UInt16],
        battery: Bool = true,
        dpi: DpiRange? = DpiRange(minimum: 200, maximum: 4_000, step: 50),
        hiRes: Bool = false,
        smartShift: Bool = false,
        thumb: Bool = false,
        haptics: Bool = false,
        force: Bool = false,
        artwork _: String
    ) -> DeviceCatalogEntry {
        DeviceCatalogEntry(
            modelId: id,
            name: name,
            kind: kind,
            capabilities: DeviceCapabilities(
                battery: battery,
                dpi: dpi,
                hiResWheel: hiRes,
                smartShift: smartShift,
                thumbWheel: thumb,
                haptics: haptics,
                forceSensing: force
            ),
            controls: controls.enumerated().map { index, cid in
                control(cid, index: index, count: controls.count)
            },
            artworkKey: "model_\(id.lowercased())"
        )
    }

    private static func control(_ cid: UInt16, index: Int, count: Int) -> DeviceControl {
        let label = controlLabel(for: cid)
        let positions: [(Double, Double)] = [
            (0.67, 0.18), (0.30, 0.47), (0.43, 0.38), (0.18, 0.68),
            (0.75, 0.34), (0.48, 0.72), (0.60, 0.58),
        ]
        let point = positions[min(index, positions.count - 1)]
        return DeviceControl(cid: cid, label: label, x: point.0, y: point.1)
    }
}
