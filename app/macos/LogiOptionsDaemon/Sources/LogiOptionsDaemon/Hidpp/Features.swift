import Foundation

/// Capability-gated HID++ helpers shared by supported pointing devices.
struct DeviceFeatures {
    let device: HidppRequesting

    // MARK: - Battery

    /// UNIFIED_BATTERY (0x1004) uses function 0x10 — see Solaar `get_battery_unified`.
    /// Response: discharge% : u8, level_flags : u8, status : u8, …
    func readBattery() -> (percent: Int, charging: Bool)? {
        if device.protocolVersion < 2 {
            if let charge = device.legacyReadRegister(0x0D),
               charge.count >= 3 {
                let percent = min(100, Int(charge[0]))
                let state = charge[2] & 0xF0
                return (percent, state == 0x50 || state == 0x90)
            }
            if let status = device.legacyReadRegister(0x07),
               status.count >= 2 {
                let approximate = [0: 5, 1: 10, 3: 30, 5: 70, 7: 100]
                return (
                    approximate[Int(status[0])] ?? 5,
                    status[1] & 0x03 != 0
                )
            }
            return nil
        }
        if let f = device.resolveFeature(.unifiedBattery),
           let r = device.featureRequest(featureIndex: f.index, function: 0x10),
           r.count >= 3 {
            let discharge = Int(r[0]) // 0–100 when known
            let levelFlags = r[1]
            let statusByte = r[2]
            // status: 0 discharging, 1 recharging, 2 full, … (BatteryStatus)
            let charging = statusByte == 1 || statusByte == 2 || statusByte == 3
            if discharge > 0 && discharge <= 100 {
                return (discharge, charging && discharge < 100)
            }
            // Fallback approximate from level bitmask (FULL=8, GOOD=4, LOW=2, CRITICAL=1)
            let approx: Int
            if levelFlags & 0x08 != 0 { approx = 100 }
            else if levelFlags & 0x04 != 0 { approx = 70 }
            else if levelFlags & 0x02 != 0 { approx = 30 }
            else if levelFlags & 0x01 != 0 { approx = 10 }
            else { approx = 5 }
            return (approx, charging)
        }
        if let f = device.resolveFeature(.batteryStatus),
           let r = device.featureRequest(featureIndex: f.index, function: 0x00),
           !r.isEmpty {
            // BATTERY_STATUS discharge next level + status
            let map = [0: 0, 1: 5, 2: 20, 3: 50, 4: 70, 5: 90, 6: 100, 7: 100]
            let level = Int(r[0])
            let percent = map[level] ?? min(100, level)
            let status = r.count > 2 ? r[2] : 0
            return (percent, status == 1 || status == 3)
        }
        return nil
    }

    /// Friendly product name when available (feature 0x0005 DEVICE_NAME).
    func readDeviceName() -> String? {
        let product = device.name
        if !device.isReceiver, product != "unknown" {
            return product
        }
        guard let feature = device.resolveFeature(.deviceName),
              let lengthReply = device.featureRequest(featureIndex: feature.index, function: 0x00),
              let length = lengthReply.first, length > 0 else {
            return product == "unknown" || device.isReceiver ? nil : product
        }
        var bytes: [UInt8] = []
        var offset: UInt8 = 0
        while bytes.count < Int(length) {
            guard let chunk = device.featureRequest(
                featureIndex: feature.index,
                function: 0x10,
                params: [offset]
            ), !chunk.isEmpty else { break }
            bytes.append(contentsOf: chunk)
            offset = UInt8(clamping: bytes.count)
        }
        let trimmed = Array(bytes.prefix(Int(length))).prefix { $0 != 0 }
        return String(bytes: trimmed, encoding: .utf8)
    }

    /// DEVICE_FW_VERSION exposes a stable unit id, model id, and colour/model
    /// derivative. The model bytes begin at offset 6; starting at offset 7
    /// drops the product-family nibble (for example 2b034 becomes b034).
    func readIdentity() -> (unitId: String?, modelId: String?, extendedModel: Int?) {
        guard let feature = device.resolveFeature(.deviceInfo),
              let reply = device.featureRequest(featureIndex: feature.index, function: 0x00),
              reply.count >= 12 else {
            return (nil, nil, nil)
        }
        return Self.parseIdentityReply(reply)
    }

    static func parseIdentityReply(
        _ reply: Data
    ) -> (unitId: String?, modelId: String?, extendedModel: Int?) {
        guard reply.count >= 12 else { return (nil, nil, nil) }
        let unit = reply[1...4].map { String(format: "%02x", $0) }.joined()
        var modelBytes = Array(reply.dropFirst(6).prefix(6))
        while modelBytes.last == 0 {
            modelBytes.removeLast()
        }
        let encodedModel = modelBytes
            .map { String(format: "%02x", $0) }
            .joined()
        let model = encodedModel
            .drop(while: { $0 == "0" })
        let extendedModel = reply.count > 12 ? Int(reply[12]) : nil
        return (
            unit == "00000000" ? nil : unit,
            model.isEmpty ? nil : String(model),
            extendedModel == 0 ? nil : extendedModel
        )
    }

    func detectedCapabilities(fallbackDpi: DpiRange?) -> DeviceCapabilities {
        DeviceCapabilities(
            battery: device.resolveFeature(.unifiedBattery) != nil
                || device.resolveFeature(.batteryStatus) != nil,
            dpi: device.resolveFeature(.extendedAdjustableDpi) != nil
                || device.resolveFeature(.adjustableDpi) != nil ? fallbackDpi : nil,
            hiResWheel: device.resolveFeature(.hiResWheel) != nil,
            smartShift: device.resolveFeature(.smartShiftEnhanced) != nil
                || device.resolveFeature(.smartShift) != nil,
            thumbWheel: device.resolveFeature(.thumbWheel) != nil,
            haptics: device.resolveFeature(.haptic) != nil,
            forceSensing: device.resolveFeature(.forceSensingButton) != nil
        )
    }

    // MARK: - DPI

    func readDpi() -> Int? {
        if let f = device.resolveFeature(.extendedAdjustableDpi),
           let r = device.featureRequest(featureIndex: f.index, function: 0x50, params: [0x00]),
           r.count >= 5 {
            let dpi = (UInt16(r[1]) << 8) | UInt16(r[2])
            let def = (UInt16(r[3]) << 8) | UInt16(r[4])
            return Int(dpi == 0 ? def : dpi)
        }
        if let f = device.resolveFeature(.adjustableDpi),
           let r = device.featureRequest(featureIndex: f.index, function: 0x20, params: [0x00]),
           r.count >= 5 {
            let dpi = (UInt16(r[1]) << 8) | UInt16(r[2])
            let def = (UInt16(r[3]) << 8) | UInt16(r[4])
            return Int(dpi == 0 ? def : dpi)
        }
        return nil
    }

    @discardableResult
    func setDpi(_ dpi: Int) -> Bool {
        let value = UInt16(clamping: dpi)
        let hi = UInt8((value >> 8) & 0xFF)
        let lo = UInt8(value & 0xFF)
        if let f = device.resolveFeature(.extendedAdjustableDpi) {
            // write_fnid 0x60, sensor 0, dpi X
            return device.featureRequest(
                featureIndex: f.index,
                function: 0x60,
                params: [0x00, hi, lo]
            ) != nil
        }
        if let f = device.resolveFeature(.adjustableDpi) {
            // write_fnid 0x30, sensor 0, dpi
            return device.featureRequest(
                featureIndex: f.index,
                function: 0x30,
                params: [0x00, hi, lo]
            ) != nil
        }
        return false
    }

    // MARK: - SmartShift

    func readSmartShift() -> (enabled: Bool, threshold: Int)? {
        if let f = device.resolveFeature(.smartShiftEnhanced),
           let r = device.featureRequest(featureIndex: f.index, function: 0x10),
           r.count >= 2 {
            let mode = r[0]
            let thr = Int(r[1])
            // mode 1 = freespin, 2 = ratcheted/smart
            return (mode != 1, thr == 255 ? 50 : min(thr, 50))
        }
        if let f = device.resolveFeature(.smartShift),
           let r = device.featureRequest(featureIndex: f.index, function: 0x00),
           r.count >= 2 {
            let mode = r[0]
            let thr = Int(r[1])
            return (mode != 1, thr == 255 ? 50 : min(thr, 50))
        }
        return nil
    }

    @discardableResult
    func setSmartShift(enabled: Bool, threshold: Int) -> Bool {
        // mode: 1 freespin, 2 smart/ratchet; thr 1..50 (255 = always ratchet)
        var thr = max(1, min(50, threshold))
        let mode: UInt8
        if !enabled {
            mode = 1
            thr = 1
        } else if thr >= 50 {
            mode = 2
            thr = 255
        } else {
            mode = 2
        }
        let params: [UInt8] = [mode, UInt8(thr)]
        if let f = device.resolveFeature(.smartShiftEnhanced) {
            return device.featureRequest(featureIndex: f.index, function: 0x20, params: params) != nil
        }
        if let f = device.resolveFeature(.smartShift) {
            return device.featureRequest(featureIndex: f.index, function: 0x10, params: params) != nil
        }
        return false
    }

    @discardableResult
    func toggleSmartShift() -> Bool {
        guard let cur = readSmartShift() else { return false }
        return setSmartShift(enabled: !cur.enabled, threshold: cur.threshold)
    }

    // MARK: - HiRes wheel

    /// capabilities: multi (counts per notch), flags…
    func readHiResCapabilities() -> (multiplier: Int, flags: UInt8)? {
        guard let f = device.resolveFeature(.hiResWheel),
              let r = device.featureRequest(featureIndex: f.index, function: 0x00),
              !r.isEmpty else { return nil }
        let multi = max(1, Int(r[0]))
        let flags = r.count > 1 ? r[1] : 0
        return (multi, flags)
    }

    func readHiResWheel() -> (hires: Bool, invert: Bool, diverted: Bool)? {
        guard let f = device.resolveFeature(.hiResWheel),
              let r = device.featureRequest(featureIndex: f.index, function: 0x10),
              !r.isEmpty else { return nil }
        let flags = r[0]
        return (
            hires: (flags & 0x02) != 0,
            invert: (flags & 0x04) != 0,
            // target / divert bit — host receives wheel movement events
            diverted: (flags & 0x01) != 0
        )
    }

    @discardableResult
    func setHiResWheel(hires: Bool, invert: Bool, diverted: Bool = false) -> Bool {
        guard let f = device.resolveFeature(.hiResWheel),
              let cur = device.featureRequest(featureIndex: f.index, function: 0x10),
              !cur.isEmpty else { return false }
        var flags = cur[0]
        // bit0 target/divert, bit1 hires, bit2 invert (Solaar / logiops)
        flags = diverted ? (flags | 0x01) : (flags & ~0x01)
        flags = hires ? (flags | 0x02) : (flags & ~0x02)
        flags = invert ? (flags | 0x04) : (flags & ~0x04)
        let ok = device.featureRequest(featureIndex: f.index, function: 0x20, params: [flags]) != nil
        DaemonLog.info(String(
            format: "setHiResWheel hires=%@ invert=%@ divert=%@ flags=0x%02X → %@",
            String(hires), String(invert), String(diverted), flags, ok ? "ok" : "fail"
        ))
        return ok
    }

    var hiResFeatureIndex: UInt8? {
        device.resolveFeature(.hiResWheel)?.index
    }

    // MARK: - Thumb wheel

    /// nativeRes / divertedRes (logiops ThumbWheel::getInfo).
    func readThumbWheelInfo() -> (nativeRes: Int, divertedRes: Int)? {
        guard let f = device.resolveFeature(.thumbWheel),
              let r = device.featureRequest(featureIndex: f.index, function: 0x00),
              r.count >= 4 else { return nil }
        let native = (Int(r[0]) << 8) | Int(r[1])
        let diverted = (Int(r[2]) << 8) | Int(r[3])
        return (max(1, native), max(1, diverted))
    }

    func readThumbWheel() -> (diverted: Bool, invert: Bool)? {
        guard let f = device.resolveFeature(.thumbWheel),
              let r = device.featureRequest(featureIndex: f.index, function: 0x10),
              r.count >= 2 else { return nil }
        return ((r[0] & 0x01) != 0, (r[1] & 0x01) != 0)
    }

    @discardableResult
    func setThumbWheel(diverted: Bool, invert: Bool) -> Bool {
        guard let f = device.resolveFeature(.thumbWheel) else { return false }
        let b0: UInt8 = diverted ? 0x01 : 0x00
        let b1: UInt8 = invert ? 0x01 : 0x00
        return device.featureRequest(featureIndex: f.index, function: 0x20, params: [b0, b1]) != nil
    }

    // MARK: - Reprog / divert

    var reprogFeatureIndex: UInt8? {
        device.resolveFeature(.reprogControlsV4)?.index
    }

    /// Returns every control the firmware explicitly says can be diverted.
    /// `nil` means the feature/query was unavailable; an empty array is a
    /// successful probe with no host-configurable controls.
    func readProgrammableControls() -> [UInt16]? {
        guard let feature = device.resolveFeature(.reprogControlsV4),
              let countReply = device.featureRequest(featureIndex: feature.index, function: 0x00),
              let count = countReply.first else { return nil }
        var controls: [UInt16] = []
        for index in 0..<count {
            guard let reply = device.featureRequest(
                featureIndex: feature.index,
                function: 0x10,
                params: [index]
            ), reply.count >= 5 else { continue }
            let cid = (UInt16(reply[0]) << 8) | UInt16(reply[1])
            let flags = UInt16(reply[4])
                | (reply.count >= 9 ? UInt16(reply[8]) << 8 : 0)
            let divertable = flags & 0x20 != 0 || flags & 0x40 != 0
            if cid != 0, divertable { controls.append(cid) }
        }
        return controls
    }

    /// Mapping flags for setCidReporting (byte 2 of params).
    /// Divert + valid: 0x01|0x02. RawXY + valid: 0x10|0x20.
    @discardableResult
    func setDivert(cid: UInt16, diverted: Bool, rawXY: Bool = false) -> Bool {
        guard let f = device.resolveFeature(.reprogControlsV4) else { return false }
        let cidHi = UInt8((cid >> 8) & 0xFF)
        let cidLo = UInt8(cid & 0xFF)
        var flags: UInt8 = 0
        if diverted {
            flags |= 0x01 | 0x02 // diverted + divertedValid
            if rawXY {
                flags |= 0x10 | 0x20 // rawXY diverted + valid
            }
        } else {
            flags = 0x02 | 0x20 // clear divert bits but mark fields valid
        }
        // setCidReporting fn 0x30: cid:u16, flags:u8, remap:u16
        let params: [UInt8] = [cidHi, cidLo, flags, 0x00, 0x00]
        let ok = device.featureRequest(featureIndex: f.index, function: 0x30, params: params) != nil
        DaemonLog.info(String(format: "setDivert cid=0x%04X divert=%@ rawXY=%@ → %@",
                              cid, String(diverted), String(rawXY), ok ? "ok" : "fail"))
        return ok
    }

    /// Apply divert for remappable CIDs. Gesture controls can additionally
    /// request RAW_XY so GestureTracker receives movement while held.
    func applyDiverts(cids: [UInt16], rawXYCids: Set<UInt16> = [0x00C3]) {
        for cid in cids {
            let raw = rawXYCids.contains(cid)
            if !setDivert(cid: cid, diverted: true, rawXY: raw), raw {
                // Some firmware rejects rawXY — fall back to divert-only.
                _ = setDivert(cid: cid, diverted: true, rawXY: false)
            }
        }
    }

    // MARK: - Haptics / force sensing

    func readHapticLevel() -> Int? {
        guard let feature = device.resolveFeature(.haptic),
              let reply = device.featureRequest(featureIndex: feature.index, function: 0x10),
              reply.count >= 2 else { return nil }
        return reply[0] & 0x01 == 0 ? 0 : Int(reply[1])
    }

    @discardableResult
    func setHapticLevel(_ level: Int) -> Bool {
        guard let feature = device.resolveFeature(.haptic) else { return false }
        let clamped = UInt8(clamping: max(0, min(100, level)))
        let params: [UInt8] = clamped == 0 ? [0x00, 50] : [0x01, clamped]
        return device.featureRequest(featureIndex: feature.index, function: 0x20, params: params) != nil
    }

    @discardableResult
    func playHaptic(waveform: UInt8) -> Bool {
        guard let feature = device.resolveFeature(.haptic) else { return false }
        return device.featureRequest(featureIndex: feature.index, function: 0x40, params: [waveform]) != nil
    }

    func readForceThreshold(buttonIndex: UInt8 = 0) -> (minimum: Int, maximum: Int, current: Int)? {
        guard let feature = device.resolveFeature(.forceSensingButton),
              let limits = device.featureRequest(
                featureIndex: feature.index,
                function: 0x10,
                params: [buttonIndex]
              ),
              limits.count >= 8,
              let currentReply = device.featureRequest(
                featureIndex: feature.index,
                function: 0x20,
                params: [buttonIndex]
              ),
              currentReply.count >= 2 else { return nil }
        let maximum = Int((UInt16(limits[4]) << 8) | UInt16(limits[5]))
        let minimum = Int((UInt16(limits[6]) << 8) | UInt16(limits[7]))
        let current = Int((UInt16(currentReply[0]) << 8) | UInt16(currentReply[1]))
        return (minimum, maximum, current)
    }

    @discardableResult
    func setForceThreshold(_ threshold: Int, buttonIndex: UInt8 = 0) -> Bool {
        guard let feature = device.resolveFeature(.forceSensingButton),
              let limits = readForceThreshold(buttonIndex: buttonIndex),
              (limits.minimum...limits.maximum).contains(threshold) else { return false }
        let value = UInt16(clamping: threshold)
        return device.featureRequest(
            featureIndex: feature.index,
            function: 0x30,
            params: [buttonIndex, UInt8(value >> 8), UInt8(value & 0xFF)]
        ) != nil
    }
}

/// Parse ReprogControls V4 divert notification params.
struct DivertEvent {
    let cid: UInt16
    let isDown: Bool
    /// Optional raw XY when RAW_XY diverted.
    let dx: Int16?
    let dy: Int16?

    static func parse(function: UInt8, params: Data) -> DivertEvent? {
        // Common: fn 0x00 diverted key event: cid:u16, flags?
        // Solaar: notification with cid and pressed state in params
        guard params.count >= 3 else { return nil }
        let cid = (UInt16(params[0]) << 8) | UInt16(params[1])
        // Byte 2 often carries pressed bit (0x01 = down) or task info
        let isDown = (params[2] & 0x01) != 0 || function == 0x00 && params.count >= 3 && params[2] != 0
        // Heuristic: some firmwares send 0x00 for up, non-zero for down in flags
        var down = isDown
        if params.count >= 3 {
            // If bit patterns look like "released"
            if params[2] == 0x00 { down = false }
            if params[2] == 0x01 || params[2] == 0x80 || (params[2] & 0x40) != 0 { down = true }
        }
        var dx: Int16?
        var dy: Int16?
        if params.count >= 7 {
            dx = Int16(bitPattern: (UInt16(params[3]) << 8) | UInt16(params[4]))
            dy = Int16(bitPattern: (UInt16(params[5]) << 8) | UInt16(params[6]))
        }
        return DivertEvent(cid: cid, isDown: down, dx: dx, dy: dy)
    }
}
