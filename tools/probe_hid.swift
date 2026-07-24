#!/usr/bin/env swift
/// Enumerate Logitech HID devices and probe HID++ 2.0 (battery, DPI, features).
/// Run:  ./tools/stop_options_plus.sh && swift tools/probe_hid.swift

import Foundation
import IOKit
import IOKit.hid

private let kLogitechVendorId = 0x046D
private let kHidppShort: UInt8 = 0x10
private let kHidppLong: UInt8 = 0x11

enum FeatureId: UInt16 {
    case featureSet = 0x0001
    case batteryStatus = 0x1000
    case unifiedBattery = 0x1004
    case smartShift = 0x2110
    case smartShiftEnhanced = 0x2111
    case adjustableDpi = 0x2201
    case extendedAdjustableDpi = 0x2202
}

final class HidppDevice {
    let device: IOHIDDevice
    let name: String
    let productId: Int
    let transport: String
    var deviceIndex: UInt8
    private var softwareId: UInt8 = 0x8
    private let reportPtr: UnsafeMutablePointer<UInt8>
    private let reportCapacity = 64
    private var waitMatch: UInt16?
    private var waitResult: Data?
    private let lock = NSLock()

    init?(device: IOHIDDevice) {
        self.device = device
        self.name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "unknown"
        self.productId = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
        self.transport = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) ?? "?"
        let isReceiver = name.localizedCaseInsensitiveContains("receiver")
            || productId == 0xC547 || productId == 0xC548 || productId == 0xC52B || productId == 0xC534
        self.deviceIndex = isReceiver ? 0x01 : 0xFF
        self.reportPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: reportCapacity)
        reportPtr.initialize(repeating: 0, count: reportCapacity)

        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            reportPtr.deallocate()
            fputs("open failed: \(name)\n", stderr)
            return nil
        }

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device,
            reportPtr,
            reportCapacity,
            { context, _, _, _, _, report, length in
                guard let context else { return }
                let me = Unmanaged<HidppDevice>.fromOpaque(context).takeUnretainedValue()
                let data = Data(bytes: report, count: Int(length))
                me.onReport(data)
            },
            ctx
        )
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    deinit {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, 0)
        reportPtr.deallocate()
    }

    private func onReport(_ data: Data) {
        guard data.count >= 4 else { return }
        let reportId = data[0]
        guard reportId == kHidppShort || reportId == kHidppLong else { return }
        let reqId = (UInt16(data[2]) << 8) | UInt16(data[3])
        lock.lock()
        defer { lock.unlock() }
        if let match = waitMatch, (match & 0xFFF0) == (reqId & 0xFFF0) {
            waitResult = Data(data.dropFirst(4))
            waitMatch = nil
        }
    }

    private func nextSwId() -> UInt8 {
        softwareId = softwareId >= 0xF ? 0x8 : softwareId + 1
        return softwareId
    }

    func request(requestId: UInt16, params: [UInt8] = [], longMessage: Bool = true, timeout: TimeInterval = 1.0) -> Data? {
        let sw = nextSwId()
        let rid = (requestId & 0xFFF0) | UInt16(sw)
        var body: [UInt8] = [deviceIndex, UInt8((rid >> 8) & 0xFF), UInt8(rid & 0xFF)] + params
        let reportId: UInt8 = (longMessage || body.count > 5) ? kHidppLong : kHidppShort
        let target = reportId == kHidppLong ? 19 : 6
        while body.count < target { body.append(0) }
        if body.count > target { body = Array(body.prefix(target)) }

        let packetLen = 1 + body.count
        let packet = UnsafeMutablePointer<UInt8>.allocate(capacity: packetLen)
        defer { packet.deallocate() }
        packet[0] = reportId
        for i in 0..<body.count { packet[i + 1] = body[i] }

        lock.lock()
        waitMatch = rid
        waitResult = nil
        lock.unlock()

        var rc = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportId), packet, packetLen)
        if rc != kIOReturnSuccess {
            // Without report-id prefix
            rc = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportId), packet + 1, packetLen - 1)
        }
        if rc != kIOReturnSuccess {
            fputs("  SetReport failed \(String(rc, radix: 16)) on \(name)\n", stderr)
            lock.lock(); waitMatch = nil; lock.unlock()
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
            lock.lock()
            let done = waitMatch == nil
            let result = waitResult
            lock.unlock()
            if done { return result }
        }
        lock.lock(); waitMatch = nil; lock.unlock()
        return nil
    }

    func featureRequest(featureIndex: UInt8, function: UInt8, params: [UInt8] = []) -> Data? {
        let requestId = (UInt16(featureIndex) << 8) | UInt16(function)
        return request(requestId: requestId, params: params, longMessage: true)
    }

    func resolveFeature(_ id: FeatureId) -> (index: UInt8, version: UInt8)? {
        let params: [UInt8] = [UInt8((id.rawValue >> 8) & 0xFF), UInt8(id.rawValue & 0xFF)]
        guard let reply = featureRequest(featureIndex: 0x00, function: 0x00, params: params),
              reply.count >= 3, reply[0] != 0 else { return nil }
        return (reply[0], reply[2])
    }

    func listFeatures() -> [(UInt16, UInt8, UInt8)] {
        guard let fs = resolveFeature(.featureSet) else { return [] }
        guard let countReply = featureRequest(featureIndex: fs.index, function: 0x00),
              !countReply.isEmpty else { return [] }
        let count = Int(countReply[0]) + 1
        var out: [(UInt16, UInt8, UInt8)] = [(0x0000, 0, 0)]
        for i in 0..<count {
            guard let r = featureRequest(featureIndex: fs.index, function: 0x10, params: [UInt8(i)]),
                  r.count >= 4 else { continue }
            let fid = (UInt16(r[0]) << 8) | UInt16(r[1])
            out.append((fid, r[2], r[3]))
        }
        return out
    }

    func readBattery() -> String {
        if let f = resolveFeature(.unifiedBattery),
           let r = featureRequest(featureIndex: f.index, function: 0x00), !r.isEmpty {
            return "unified \(r[0])% (v\(f.version))"
        }
        if let f = resolveFeature(.batteryStatus),
           let r = featureRequest(featureIndex: f.index, function: 0x00), r.count >= 1 {
            return "status raw=\(r[0]) (v\(f.version))"
        }
        return "unavailable"
    }

    func readDpi() -> String {
        if let f = resolveFeature(.extendedAdjustableDpi),
           let r = featureRequest(featureIndex: f.index, function: 0x50, params: [0x00]), r.count >= 5 {
            let dpi = (UInt16(r[1]) << 8) | UInt16(r[2])
            let def = (UInt16(r[3]) << 8) | UInt16(r[4])
            return "extended \(dpi == 0 ? def : dpi) dpi (v\(f.version))"
        }
        if let f = resolveFeature(.adjustableDpi),
           let r = featureRequest(featureIndex: f.index, function: 0x20, params: [0x00]), r.count >= 5 {
            let dpi = (UInt16(r[1]) << 8) | UInt16(r[2])
            let def = (UInt16(r[3]) << 8) | UInt16(r[4])
            return "adjustable \(dpi == 0 ? def : dpi) dpi (v\(f.version))"
        }
        return "unavailable"
    }

    func readSmartShift() -> String {
        if let f = resolveFeature(.smartShiftEnhanced),
           let r = featureRequest(featureIndex: f.index, function: 0x10), r.count >= 2 {
            return "enhanced mode=\(r[0]) thr=\(r[1]) (v\(f.version))"
        }
        if let f = resolveFeature(.smartShift),
           let r = featureRequest(featureIndex: f.index, function: 0x00), r.count >= 2 {
            return "mode=\(r[0]) thr=\(r[1]) (v\(f.version))"
        }
        return "unavailable"
    }
}

func featureName(_ id: UInt16) -> String {
    switch id {
    case 0x0000: return "ROOT"
    case 0x0001: return "FEATURE_SET"
    case 0x0003: return "FIRMWARE_INFO"
    case 0x0005: return "DEVICE_NAME"
    case 0x1000: return "BATTERY_STATUS"
    case 0x1004: return "UNIFIED_BATTERY"
    case 0x1B04: return "REPROG_CONTROLS_V4"
    case 0x1814: return "CHANGE_HOST"
    case 0x2110: return "SMART_SHIFT"
    case 0x2111: return "SMART_SHIFT_ENHANCED"
    case 0x2121: return "HIRES_WHEEL"
    case 0x2150: return "THUMB_WHEEL"
    case 0x2201: return "ADJUSTABLE_DPI"
    case 0x2202: return "EXTENDED_ADJUSTABLE_DPI"
    case 0x2205: return "POINTER_SPEED"
    case 0x8100: return "ONBOARD_PROFILES"
    default: return ""
    }
}

func pgrep(_ name: String) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-x", name]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try? task.run()
    task.waitUntilExit()
    return task.terminationStatus == 0
}

// --- main ---

print("LogiOptions HID++ probe")
print("------------------------")
if pgrep("logioptionsplus_agent") {
    print("WARNING: logioptionsplus_agent is running — run tools/stop_options_plus.sh first.\n")
}

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: kLogitechVendorId] as CFDictionary)
IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
let set = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
let devices = Array(set).sorted {
    let n1 = (IOHIDDeviceGetProperty($0, kIOHIDProductKey as CFString) as? String) ?? ""
    let n2 = (IOHIDDeviceGetProperty($1, kIOHIDProductKey as CFString) as? String) ?? ""
    return n1 < n2
}

print("Found \(devices.count) Logitech HID interface(s):\n")
var candidates: [IOHIDDevice] = []
for d in devices {
    let name = (IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String) ?? "?"
    let pid = (IOHIDDeviceGetProperty(d, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
    let transport = (IOHIDDeviceGetProperty(d, kIOHIDTransportKey as CFString) as? String) ?? "?"
    let usagePage = (IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? 0
    let usage = (IOHIDDeviceGetProperty(d, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.intValue ?? 0
    print("  \(name.padding(toLength: 32, withPad: " ", startingAt: 0)) pid=0x\(String(format: "%04X", pid)) transport=\(transport) usage=\(String(format: "%04X:%04X", usagePage, usage))")
    // HID++ lives on vendor usage pages
    if usagePage >= 0xFF00 {
        candidates.append(d)
    }
}

print("\nProbing \(candidates.count) HID++ interface(s)…\n")

for d in candidates {
    guard let client = HidppDevice(device: d) else { continue }
    print("→ \(client.name) (0x\(String(client.productId, radix: 16))) [\(client.transport)]")

    let indices: [UInt8] = client.deviceIndex == 0xFF ? [0xFF, 0x00, 0x01] : Array(1...6).map { UInt8($0) }

    var ok = false
    for idx in indices {
        client.deviceIndex = idx
        if let fs = client.resolveFeature(.featureSet) {
            print("  HID++ OK  device_index=0x\(String(format: "%02X", idx))  FeatureSet@\(fs.index) v\(fs.version)")
            let features = client.listFeatures()
            print("  Features (\(features.count)):")
            for (fid, typ, ver) in features {
                let label = featureName(fid)
                let suffix = label.isEmpty ? "" : "  \(label)"
                print("    \(String(format: "%04X", fid))  type=\(String(format: "%02X", typ)) ver=\(ver)\(suffix)")
            }
            print("  Battery:    \(client.readBattery())")
            print("  DPI:        \(client.readDpi())")
            print("  SmartShift: \(client.readSmartShift())")
            ok = true
            break
        }
    }
    if !ok {
        print("  No HID++ response on this interface (device off-slot / pairing / report path)")
    }
    print("")
}

print("Done.")
