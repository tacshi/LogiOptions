import AppKit
import Foundation
import IOKit.hid

enum DeviceReconnectPolicy {
    static func shouldReconnect(hasActiveDevice: Bool) -> Bool {
        !hasActiveDevice
    }
}

final class Daemon {
    private var config: AppConfig
    private let deviceService = DeviceService()
    private var device: HidppDevice?
    private var features: DeviceFeatures?
    private var featuresBox: DeviceFeaturesBox?
    private let engine = ActionEngine()
    private lazy var gestures = GestureTracker(engine: engine)
    private let scroll = ScrollEngine()
    private let focus = AppFocusMonitor()
    private let rpc = RpcServer(path: SocketPaths.socket)
    private var reconnectTimer: Timer?
    private var batteryTimer: Timer?
    private var activeProfile: ProfileSettings = .defaultGlobal
    /// Currently diverted controls reported as pressed (REPROG_V4 event 0x00).
    private var keysDown: Set<UInt16> = []
    private var heldMousePresses: [UInt16: MousePress] = [:]
    private var lastBattery: (percent: Int, charging: Bool)?
    private var lastDpi: Int?
    private var lastSmartShift: (enabled: Bool, threshold: Int)?
    private var lastHiRes: (hires: Bool, invert: Bool, diverted: Bool)?
    private var lastThumb: (diverted: Bool, invert: Bool)?
    private var optionsPlusRunning = false
    /// Snapshot served to RPC — never do multi-second HID++ work on the RPC queue.
    private var statusCache: [String: Any] = [:]
    private var statusRefreshTimer: Timer?
    private var signalSources: [Any] = []
    private var thumbActionAccumulator: Int = 0
    private var thumbActionStep: Int = 8
    private var lastThumbActionAt = Date.distantPast

    /// Shared so signal handlers can undivert the wheel before exit.
    private static weak var shared: Daemon?

    init() {
        config = ConfigStore.load()
        activeProfile = config.global
        Daemon.shared = self
    }

    func run() {
        installSignalHandlers()
        BatteryNotifier.requestAuthorization()
        setupRpc()
        focus.onChange = { [weak self] bid in
            // Profile apply can be HID-heavy — always on main.
            DispatchQueue.main.async {
                self?.applyProfile(forBundleId: bid)
            }
        }
        focus.start()
        scheduleReconnect()
        scheduleStatusRefresh()

        // Cursor fallback only when RAW_XY is missing (divert usually freezes the pointer).
        Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.gestures.updatePointer()
        }

        // Connect AFTER the main run loop is spinning so HID++ replies can be delivered.
        DispatchQueue.main.async { [weak self] in
            self?.checkOptionsPlus()
            self?.connectDevice()
            self?.refreshStatusCache(light: false)
            DaemonLog.info("device setup finished — config \(SocketPaths.configFile.path)")
        }

        DaemonLog.info("running — RPC ready, connecting device…")
        RunLoop.main.run()
    }

    private func noteBattery(_ bat: (percent: Int, charging: Bool)) {
        lastBattery = bat
        let name = features?.readDeviceName() ?? device?.name
        BatteryNotifier.evaluate(percent: bat.percent, charging: bat.charging, deviceName: name)
    }

    /// Release host divert so macOS gets native scroll if the daemon dies.
    func restoreNativeScroll() {
        releaseHeldMouseButtons()
        guard let features else { return }
        DaemonLog.info("restoring native scroll (undivert hi-res + thumb)")
        let capabilities = deviceService.selectedDescriptor?.capabilities
        if capabilities?.hiResWheel == true {
            _ = features.setHiResWheel(hires: true, invert: false, diverted: false)
        }
        if capabilities?.thumbWheel == true {
            _ = features.setThumbWheel(diverted: false, invert: false)
        }
    }

    private func installSignalHandlers() {
        // Safe async handlers on main — undivert so scroll is not left dead.
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        term.setEventHandler { [weak self] in
            DaemonLog.info("SIGTERM — restoring native scroll")
            self?.restoreNativeScroll()
            exit(0)
        }
        term.resume()
        let intSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        intSrc.setEventHandler { [weak self] in
            DaemonLog.info("SIGINT — restoring native scroll")
            self?.restoreNativeScroll()
            exit(0)
        }
        intSrc.resume()
        signalSources = [term, intSrc]
    }

    // MARK: - Device

    private func connectDevice() {
        restoreNativeScroll()
        device = nil
        features = nil
        featuresBox = nil
        lastBattery = nil
        lastDpi = nil
        lastSmartShift = nil
        lastHiRes = nil
        lastThumb = nil

        let originalConfig = config
        config.pruneUnsupportedDevices()
        let preferredDeviceId = config.selectedDeviceId == AppConfig.legacyDeviceId
            ? nil
            : config.selectedDeviceId
        _ = deviceService.rescan(preferredDeviceId: preferredDeviceId)
        for endpoint in deviceService.endpoints {
            config.ensureDevice(endpoint.descriptor)
        }
        if let selectedId = deviceService.selectedDescriptor?.id {
            config.selectedDeviceId = selectedId
        }
        if config != originalConfig {
            config.bumpRevision()
            ConfigStore.save(config)
        }

        guard let dev = deviceService.selectedDevice else {
            DaemonLog.warn("No HID++ device found")
            refreshStatusCache()
            return
        }
        device = dev
        let feat = DeviceFeatures(device: dev)
        features = feat
        let box = DeviceFeaturesBox(feat)
        featuresBox = box
        engine.features = box

        dev.onNotification = { [weak self] featureIndex, function, params in
            self?.handleNotification(featureIndex: featureIndex, function: function, params: params)
        }
        dev.onRemoval = { [weak self, weak dev] in
            guard let self, let dev, self.device === dev else { return }
            DaemonLog.info("HID++ device removed — waiting to reconnect")
            self.releaseHeldMouseButtons()
            self.device = nil
            self.features = nil
            self.featuresBox = nil
            self.engine.features = nil
            DispatchQueue.main.async { [weak self] in
                guard let self, self.device == nil else { return }
                self.connectDevice()
                self.refreshStatusCache()
            }
        }

        applyProfile(forBundleId: focus.frontBundleId)
        if let bat = feat.readBattery() {
            noteBattery(bat)
            DaemonLog.info("Battery \(bat.percent)% charging=\(bat.charging)")
        }
        if let dpi = feat.readDpi() {
            lastDpi = dpi
            DaemonLog.info("DPI \(dpi)")
        }
        refreshStatusCache()
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.checkOptionsPlus()
            if DeviceReconnectPolicy.shouldReconnect(hasActiveDevice: self.device != nil) {
                self.connectDevice()
                self.refreshStatusCache()
            }
            // Avoid HID ping every few seconds (was blocking RPC). Cache refresh handles liveness.
        }
    }

    private func scheduleStatusRefresh() {
        statusRefreshTimer?.invalidate()
        // Light refresh: battery + permission flags. Full sensor reads less often.
        statusRefreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshStatusCache(light: true)
        }
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.refreshStatusCache(light: false)
        }
    }

    /// Update cached snapshot on the main thread (safe for HID++).
    private func refreshStatusCache(light: Bool = false) {
        // Skip if a HID++ exchange is already pumping the run loop.
        if device?.isBusy == true {
            statusCache = buildStatusDict(includeLiveSensors: false)
            return
        }
        if light {
            if deviceService.selectedDescriptor?.capabilities.battery == true,
               let bat = features?.readBattery() {
                noteBattery(bat)
            }
            statusCache = buildStatusDict(includeLiveSensors: false)
            return
        }
        let capabilities = deviceService.selectedDescriptor?.capabilities
        if capabilities?.battery == true, let bat = features?.readBattery() { noteBattery(bat) }
        if capabilities?.dpi != nil, let dpi = features?.readDpi(), (50...32_000).contains(dpi) {
            lastDpi = dpi
        }
        if capabilities?.smartShift == true, let ss = features?.readSmartShift() { lastSmartShift = ss }
        if capabilities?.hiResWheel == true, let hw = features?.readHiResWheel() { lastHiRes = hw }
        if capabilities?.thumbWheel == true, let tw = features?.readThumbWheel() { lastThumb = tw }
        statusCache = buildStatusDict(includeLiveSensors: false)
    }

    private func checkOptionsPlus() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "logioptionsplus_agent"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        optionsPlusRunning = task.terminationStatus == 0
    }

    // MARK: - Profiles

    private func applyProfile(forBundleId bundleId: String?) {
        var profile = config.global
        if let bundleId, let app = config.apps[bundleId] {
            profile = app.merged(over: config.global)
        }
        activeProfile = profile
        applyOnDevice(profile)
        DaemonLog.info("Active profile: \(bundleId ?? "global")")
    }

    private func applyOnDevice(_ profile: ProfileSettings) {
        guard let features else { return }
        let capabilities = deviceService.selectedDescriptor?.capabilities ?? .minimal
        // Keep this short — long multi-feature storms make RPC look dead.
        if capabilities.dpi != nil, let dpi = profile.dpi {
            if features.setDpi(dpi) { lastDpi = dpi }
        }
        if capabilities.smartShift, let en = profile.smartShiftEnabled {
            let thr = profile.smartShiftThreshold ?? 10
            if features.setSmartShift(enabled: en, threshold: thr) {
                lastSmartShift = (en, thr)
            }
        }
        // Options+ host-scales scroll. Divert hi-res wheel so we inject pixel
        // steps (native HID hi-res often lands as huge line jumps on macOS).
        if capabilities.hiResWheel, let caps = features.readHiResCapabilities() {
            scroll.hiresMultiplier = Double(caps.multiplier)
        }
        if capabilities.thumbWheel, let info = features.readThumbWheelInfo() {
            scroll.thumbDivertedRes = Double(info.divertedRes)
            // About fifteen intentional action detents per full revolution;
            // scales with each device's reported diverted resolution.
            thumbActionStep = max(1, info.divertedRes / 15)
            DaemonLog.info("thumb res native=\(info.nativeRes) diverted=\(info.divertedRes)")
        }
        scroll.verticalSpeed = profile.scrollSpeed ?? 1.0
        scroll.thumbSpeed = profile.thumbSpeed ?? 1.0
        // Invert must be software-side while diverted (HID++ deltas ignore fw invert).
        scroll.invertVertical = profile.invertWheel ?? false
        scroll.invertThumb = profile.thumbInvert ?? false

        if capabilities.hiResWheel, let hires = profile.hiresWheel {
            let invert = profile.invertWheel ?? false
            // Always divert while active: speed and software inversion must
            // continue working even when high-resolution mode is disabled.
            let divert = true
            // Firmware invert is unreliable on diverted path — keep fw invert off.
            if features.setHiResWheel(hires: hires, invert: false, diverted: divert) {
                lastHiRes = (hires, invert, divert)
            }
        }
        if capabilities.thumbWheel {
            let thumbDivert = profile.thumbMode == "actions" ? true : (profile.thumbDivert ?? true)
            let thumbInvert = profile.thumbInvert ?? false
            if features.setThumbWheel(diverted: thumbDivert, invert: false) {
                lastThumb = (thumbDivert, thumbInvert)
            }
        }
        if capabilities.haptics,
           let deviceId = config.selectedDeviceId,
           let settings = config.devices[deviceId]?.settings {
            let level = settings.hapticEnabled ? settings.hapticLevel : 0
            _ = features.setHapticLevel(level)
        }
        if capabilities.forceSensing,
           let deviceId = config.selectedDeviceId,
           let threshold = config.devices[deviceId]?.settings.forceThreshold {
            _ = features.setForceThreshold(threshold)
        }
        DaemonLog.info(String(
            format: "scroll cfg speed=%.2f thumb=%.2f invV=%@ invT=%@",
            scroll.verticalSpeed, scroll.thumbSpeed,
            String(scroll.invertVertical), String(scroll.invertThumb)
        ))

        let controls = deviceService.selectedDescriptor?.controls.map(\.cid) ?? []
        let rawControls = Set(controls.filter {
            guard let action = profile.action(forCid: $0) else { return false }
            if case .gesture = action { return true }
            return false
        })
        features.applyDiverts(cids: controls, rawXYCids: rawControls)
        refreshStatusCache(light: true)
    }

    // MARK: - Notifications

    private func handleNotification(featureIndex: UInt8, function: UInt8, params: Data) {
        guard let features else { return }

        // ReprogControls V4 divert + rawXY
        if let idx = features.reprogFeatureIndex, idx == featureIndex {
            handleReprogNotification(function: function, params: params)
            return
        }

        // HiRes wheel movement (0x2121 fn 0x00) when target/divert is set.
        if let idx = features.hiResFeatureIndex, idx == featureIndex, function == 0x00 {
            handleHiResWheel(params: params)
            return
        }

        // Thumb wheel divert (0x2150): typically reports delta
        if let tw = device?.resolveFeature(.thumbWheel), tw.index == featureIndex {
            handleThumbWheel(params: params)
            return
        }
    }

    /// REPROG_CONTROLS_V4 (Solaar-compatible):
    /// - event 0x00: up to 4 currently-pressed CIDs (big-endian u16 × 4)
    /// - event 0x10: rawXY dx, dy (signed i16 × 2) while a rawXY-diverted control is held
    private func handleReprogNotification(function: UInt8, params: Data) {
        switch function {
        case 0x00:
            handleDivertedKeysPressed(params: params)
        case 0x10:
            handleRawXY(params: params)
        default:
            break
        }
    }

    private func handleDivertedKeysPressed(params: Data) {
        // Build set of CIDs currently held (zeros mean empty slot).
        var newDown = Set<UInt16>()
        var offset = 0
        let limit = min(params.count, 8)
        while offset + 1 < limit {
            let cid = (UInt16(params[offset]) << 8) | UInt16(params[offset + 1])
            if cid != 0 {
                newDown.insert(cid)
            }
            offset += 2
        }

        let pressed = newDown.subtracting(keysDown)
        let released = keysDown.subtracting(newDown)
        keysDown = newDown

        for cid in pressed {
            DaemonLog.info(String(format: "divert DOWN 0x%04X keys=%@", cid, String(describing: newDown)))
            onButtonDown(cid: cid)
        }
        for cid in released {
            DaemonLog.info(String(format: "divert UP 0x%04X", cid))
            onButtonUp(cid: cid)
        }
    }

    private func handleRawXY(params: Data) {
        guard params.count >= 4 else { return }
        let dx = Int16(bitPattern: (UInt16(params[0]) << 8) | UInt16(params[1]))
        let dy = Int16(bitPattern: (UInt16(params[2]) << 8) | UInt16(params[3]))
        gestures.addRawDelta(dx: dx, dy: dy)
    }

    private func onButtonDown(cid: UInt16) {
        guard let action = activeProfile.action(forCid: cid) else {
            DaemonLog.warn(String(format: "no action for cid 0x%04X in active profile", cid))
            return
        }
        if case .mouse(let button) = action {
            if heldMousePresses[cid] == nil,
               let press = engine.beginMouseButton(button) {
                heldMousePresses[cid] = press
            }
            return
        }
        if isGestureAction(action) {
            gestures.begin(spec: action)
            return
        }
        if case .smartShiftToggle = action {
            engine.execute(action)
            return
        }
        // Fire simple actions on press (Options+-like for non-gesture buttons).
        engine.execute(action)
    }

    private func onButtonUp(cid: UInt16) {
        if let press = heldMousePresses.removeValue(forKey: cid) {
            engine.endMouseButton(press)
        }
        if gestures.isActive {
            // End gesture on any release while tracking (typically the gesture CID).
            let releasedAction = activeProfile.action(forCid: cid)
            if releasedAction.map(isGestureAction) == true || keysDown.isEmpty {
                gestures.end()
            }
        }
    }

    private func releaseHeldMouseButtons() {
        for press in heldMousePresses.values {
            engine.endMouseButton(press)
        }
        heldMousePresses.removeAll()
    }

    private func isGestureAction(_ action: ActionSpec) -> Bool {
        if case .gesture = action { return true }
        return false
    }

    /// HIRES_WHEEL movement event: flags, deltaV:i16 (Solaar / logiops).
    private func handleHiResWheel(params: Data) {
        guard params.count >= 3 else { return }
        // byte0: periods + hiRes flag; bytes1-2: deltaV big-endian
        let deltaV = Int16(bitPattern: (UInt16(params[1]) << 8) | UInt16(params[2]))
        scroll.injectVertical(deltaV: deltaV)
    }

    private func handleThumbWheel(params: Data) {
        // rotation:i16 BE, timestamp, status, flags (logiops ThumbwheelEvent)
        guard params.count >= 2 else { return }
        let rotation = Int16(bitPattern: (UInt16(params[0]) << 8) | UInt16(params[1]))
        if activeProfile.thumbMode == "actions" {
            let value = (activeProfile.thumbInvert ?? false) ? -Int(rotation) : Int(rotation)
            thumbActionAccumulator += value
            let now = Date()
            guard abs(thumbActionAccumulator) >= thumbActionStep,
                  now.timeIntervalSince(lastThumbActionAt) >= 0.08 else { return }
            let action = thumbActionAccumulator < 0
                ? activeProfile.thumbLeftAction
                : activeProfile.thumbRightAction
            thumbActionAccumulator += thumbActionAccumulator < 0
                ? thumbActionStep : -thumbActionStep
            lastThumbActionAt = now
            if let action { engine.execute(action.toActionSpec()) }
            return
        }
        scroll.injectThumb(rotation: rotation)
    }

    // MARK: - RPC

    private func setupRpc() {
        rpc.handler = { [weak self] method, params in
            guard let self else { return ["ok": false, "error": "daemon gone"] }
            return self.dispatch(method: method, params: params)
        }
        do {
            try rpc.start()
        } catch {
            DaemonLog.error("RPC failed: \(error)")
        }
    }

    private func dispatch(method: String, params: [String: Any]?) -> [String: Any] {
        switch method {
        case "ping":
            return ["ok": true, "pong": true]
        case "getStatus":
            // Instant — never block RPC on HID++.
            return statusDictFast()
        case "getSnapshot":
            return snapshotDict()
        case "listDevices":
            return devicesDict()
        case "selectDevice":
            return runOnMainSync { self.selectDevice(params) }
        case "rescanDevices":
            return runOnMainSync {
                self.connectDevice()
                return self.snapshotDict()
            }
        case "getConfig":
            return configDict()
        case "requestAccessibility":
            return runOnMainSync {
                Permissions.requestForDaemonFromUser()
                self.refreshStatusCache(light: true)
                return [
                    "ok": true,
                    "accessibilityTrusted": Permissions.accessibilityTrusted(),
                ]
            }
        case "putProfile":
            return runOnMainSync { self.putProfile(params) }
        case "deleteProfile":
            return runOnMainSync { self.deleteProfile(params) }
        case "patchDeviceSettings":
            return runOnMainSync { self.patchDeviceSettings(params) }
        case "setConfig":
            return runOnMainSync { self.setConfig(params) }
        case "setDpi":
            return runOnMainSync {
                let dpi = params?["dpi"] as? Int ?? 1000
                self.config.global.dpi = dpi
                self.config.bumpRevision()
                ConfigStore.save(self.config)
                let ok = self.features?.setDpi(dpi) ?? false
                if ok { self.lastDpi = dpi }
                self.refreshStatusCache(light: true)
                return ["ok": ok, "dpi": dpi]
            }
        case "setSmartShift":
            return runOnMainSync {
                let en = params?["enabled"] as? Bool ?? true
                let thr = params?["threshold"] as? Int ?? 10
                self.config.global.smartShiftEnabled = en
                self.config.global.smartShiftThreshold = thr
                self.config.bumpRevision()
                ConfigStore.save(self.config)
                let ok = self.features?.setSmartShift(enabled: en, threshold: thr) ?? false
                if ok { self.lastSmartShift = (en, thr) }
                self.refreshStatusCache(light: true)
                return ["ok": ok]
            }
        case "setHiResWheel":
            return runOnMainSync {
                let hires = JsonUtil.bool(params?["hires"], default: true)
                let invert = JsonUtil.bool(params?["invert"], default: false)
                self.config.global.hiresWheel = hires
                self.config.global.invertWheel = invert
                self.config.bumpRevision()
                self.scroll.invertVertical = invert
                ConfigStore.save(self.config)
                let divert = hires
                // Software invert while diverted; leave firmware invert off.
                let ok = self.features?.setHiResWheel(hires: hires, invert: false, diverted: divert) ?? false
                if ok { self.lastHiRes = (hires, invert, divert) }
                DaemonLog.info("setHiResWheel hires=\(hires) invert=\(invert) divert=\(divert)")
                self.refreshStatusCache(light: true)
                return ["ok": ok]
            }
        case "setScrollSpeed":
            return runOnMainSync {
                let v = min(2, max(0.05, JsonUtil.double(params?["speed"], default: 1.0)))
                self.config.global.scrollSpeed = v
                self.config.bumpRevision()
                self.scroll.verticalSpeed = v
                ConfigStore.save(self.config)
                DaemonLog.info(String(format: "setScrollSpeed %.2f", v))
                self.refreshStatusCache(light: true)
                return ["ok": true, "scrollSpeed": v]
            }
        case "setThumbWheel":
            return runOnMainSync {
                let divert = JsonUtil.bool(params?["divert"], default: true)
                let invert = JsonUtil.bool(params?["invert"], default: false)
                self.config.global.thumbDivert = divert
                self.config.global.thumbInvert = invert
                self.config.bumpRevision()
                self.scroll.invertThumb = invert
                ConfigStore.save(self.config)
                // Software invert while diverted.
                let ok = self.features?.setThumbWheel(diverted: divert, invert: false) ?? false
                if ok { self.lastThumb = (divert, invert) }
                DaemonLog.info("setThumbWheel divert=\(divert) invert=\(invert)")
                self.refreshStatusCache(light: true)
                return ["ok": ok]
            }
        case "setThumbSpeed":
            return runOnMainSync {
                let v = min(2, max(0.05, JsonUtil.double(params?["speed"], default: 1.0)))
                self.config.global.thumbSpeed = v
                self.config.bumpRevision()
                self.scroll.thumbSpeed = v
                ConfigStore.save(self.config)
                DaemonLog.info(String(format: "setThumbSpeed %.2f", v))
                self.refreshStatusCache(light: true)
                return ["ok": true, "thumbSpeed": v]
            }
        case "setButton":
            return runOnMainSync { self.setButton(params) }
        case "applyProfile":
            return runOnMainSync {
                self.applyProfile(forBundleId: self.focus.frontBundleId)
                return ["ok": true]
            }
        case "reconnect":
            return runOnMainSync {
                self.connectDevice()
                self.refreshStatusCache(light: false)
                return self.statusDictFast()
            }
        case "getLoginItem":
            return [
                "ok": true,
                "enabled": FileManager.default.fileExists(atPath: LoginAgent.plistURL.path),
            ]
        case "setLoginItem":
            return runOnMainSync {
                let en = JsonUtil.bool(params?["enabled"], default: false)
                let ok = LoginAgent.setEnabled(en)
                self.refreshStatusCache(light: true)
                return [
                    "ok": ok,
                    "enabled": FileManager.default.fileExists(atPath: LoginAgent.plistURL.path),
                ]
            }
        case "stopDaemon":
            // Critical: undivert scroll, stop LaunchAgent session (no KeepAlive
            // bounce), then exit after the RPC reply is written.
            return runOnMainSync {
                DaemonLog.info("stopDaemon requested — restoring native scroll and exiting")
                self.restoreNativeScroll()
                LoginAgent.stopSession()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    exit(0)
                }
                return ["ok": true, "stopping": true]
            }
        default:
            return ["ok": false, "error": "unknown method \(method)"]
        }
    }

    private func runOnMainSync(_ body: @escaping () -> [String: Any]) -> [String: Any] {
        if Thread.isMainThread { return body() }
        var result: [String: Any] = ["ok": false, "error": "main hop failed"]
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            result = body()
            sem.signal()
        }
        // Keep RPC responsive; setters should finish well under this.
        _ = sem.wait(timeout: .now() + 2.5)
        return result
    }

    private func statusDictFast() -> [String: Any] {
        if statusCache.isEmpty {
            // First call before main has refreshed — build without blocking HID if possible.
            return buildStatusDict(includeLiveSensors: false)
        }
        var d = statusCache
        d["daemonOnline"] = true
        d["frontApp"] = focus.frontBundleId as Any
        d["optionsPlusRunning"] = optionsPlusRunning
        d["accessibilityTrusted"] = Permissions.accessibilityTrusted()
        d["inputMonitoringTrusted"] = Permissions.inputMonitoringTrusted()
        return d
    }

    private func buildStatusDict(includeLiveSensors: Bool) -> [String: Any] {
        let connected = device != nil
        let descriptor = deviceService.selectedDescriptor
            ?? config.selectedDeviceId.flatMap { config.recentDevices[$0] }
        let transport = descriptor?.transport ?? "unknown"
        var d: [String: Any] = [
            "ok": true,
            "daemonOnline": true,
            "connected": connected,
            "deviceId": descriptor?.id as Any,
            "deviceName": descriptor?.name ?? features?.readDeviceName() ?? device?.name ?? "No device",
            "modelId": descriptor?.modelId ?? "unknown",
            "connection": transport,
            "verification": descriptor?.verification.rawValue ?? "compatible",
            "capabilities": descriptor.flatMap { JsonUtil.object($0.capabilities) } as Any,
            "controls": descriptor.flatMap { JsonUtil.object($0.controls) } as Any,
            "artworkKey": descriptor?.artworkKey ?? "generic_mouse",
            "optionsPlusRunning": optionsPlusRunning,
            "frontApp": focus.frontBundleId as Any,
            "accessibilityTrusted": Permissions.accessibilityTrusted(),
            "inputMonitoringTrusted": Permissions.inputMonitoringTrusted(),
        ]

        if includeLiveSensors {
            if let bat = features?.readBattery() { lastBattery = bat }
            if let dpi = features?.readDpi(), (200...8000).contains(dpi) { lastDpi = dpi }
            if let ss = features?.readSmartShift() { lastSmartShift = ss }
            if let hw = features?.readHiResWheel() { lastHiRes = hw }
            if let tw = features?.readThumbWheel() { lastThumb = tw }
        }

        if let bat = lastBattery {
            d["batteryPercent"] = bat.percent
            d["charging"] = bat.charging
        }
        d["dpi"] = lastDpi ?? activeProfile.dpi ?? 1000
        if let ss = lastSmartShift {
            d["smartShiftEnabled"] = ss.enabled
            d["smartShiftThreshold"] = ss.threshold
        } else {
            d["smartShiftEnabled"] = activeProfile.smartShiftEnabled as Any
            d["smartShiftThreshold"] = activeProfile.smartShiftThreshold as Any
        }
        // Prefer config for invert/speed (host-owned while diverted), not device flags.
        d["hiresWheel"] = lastHiRes?.hires ?? activeProfile.hiresWheel as Any
        d["invertWheel"] = activeProfile.invertWheel ?? scroll.invertVertical
        d["thumbDivert"] = lastThumb?.diverted ?? activeProfile.thumbDivert as Any
        d["thumbInvert"] = activeProfile.thumbInvert ?? scroll.invertThumb
        d["scrollSpeed"] = activeProfile.scrollSpeed ?? scroll.verticalSpeed
        d["thumbSpeed"] = activeProfile.thumbSpeed ?? scroll.thumbSpeed
        d["revision"] = config.revision
        // Plist present = user opted in (even if this process was UI-spawned).
        let loginPlist = FileManager.default.fileExists(atPath: LoginAgent.plistURL.path)
        d["loginAtStartup"] = loginPlist || LoginAgent.isEnabled()
        return d
    }

    private func configDict() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(config),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["ok": false, "error": "encode failed"]
        }
        return ["ok": true, "revision": config.revision, "config": obj]
    }

    private func setConfig(_ params: [String: Any]?) -> [String: Any] {
        guard let raw = params?["config"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return ["ok": false, "error": "invalid config"]
        }
        config = cfg
        config.version = 3
        config.bumpRevision()
        ConfigStore.save(config)
        applyProfile(forBundleId: focus.frontBundleId)
        return ["ok": true]
    }

    private func devicesDict() -> [String: Any] {
        let recent = Array(config.recentDevices.values)
        let descriptors = deviceService.descriptors(includingRecent: recent)
        return [
            "ok": true,
            "devices": JsonUtil.object(descriptors) ?? [],
            "selectedDeviceId": config.selectedDeviceId as Any,
            "revision": config.revision,
        ]
    }

    private func snapshotDict() -> [String: Any] {
        var result = statusDictFast()
        let deviceResult = devicesDict()
        result["devices"] = deviceResult["devices"]
        result["selectedDeviceId"] = config.selectedDeviceId as Any
        result["revision"] = config.revision
        result["config"] = JsonUtil.object(config)
        return result
    }

    private func revisionConflict(_ params: [String: Any]?) -> [String: Any]? {
        guard let expected = params?["expectedRevision"] else { return nil }
        let value = JsonUtil.int(expected, default: -1)
        guard value != config.revision else { return nil }
        return [
            "ok": false,
            "error": [
                "code": "revision_conflict",
                "message": "Configuration changed; refresh and try again.",
            ],
            "revision": config.revision,
        ]
    }

    private func selectDevice(_ params: [String: Any]?) -> [String: Any] {
        if let conflict = revisionConflict(params) { return conflict }
        guard let id = params?["deviceId"] as? String,
              deviceService.endpoints.contains(where: { $0.descriptor.id == id }) else {
            return rpcError("device_not_found", "The selected device is not connected.")
        }
        restoreNativeScroll()
        config.selectedDeviceId = id
        config.bumpRevision()
        ConfigStore.save(config)
        connectDevice()
        return snapshotDict()
    }

    private func putProfile(_ params: [String: Any]?) -> [String: Any] {
        if let conflict = revisionConflict(params) { return conflict }
        guard let deviceId = params?["deviceId"] as? String,
              var configuration = config.devices[deviceId],
              let profile = JsonUtil.decode(ProfileSettings.self, from: params?["profile"]) else {
            return rpcError("invalid_profile", "Profile data or device id is invalid.")
        }
        if let bundleId = params?["bundleId"] as? String, !bundleId.isEmpty {
            configuration.apps[bundleId] = profile
            if let metadata = JsonUtil.decode(AppIdentity.self, from: params?["application"]) {
                configuration.applicationMetadata[bundleId] = metadata
            }
        } else {
            configuration.global = profile
        }
        config.devices[deviceId] = configuration
        config.bumpRevision()
        ConfigStore.save(config)
        if config.selectedDeviceId == deviceId {
            applyProfile(forBundleId: focus.frontBundleId)
        }
        return ["ok": true, "revision": config.revision, "config": JsonUtil.object(config) as Any]
    }

    private func deleteProfile(_ params: [String: Any]?) -> [String: Any] {
        if let conflict = revisionConflict(params) { return conflict }
        guard let deviceId = params?["deviceId"] as? String,
              let bundleId = params?["bundleId"] as? String,
              var configuration = config.devices[deviceId] else {
            return rpcError("invalid_profile", "Device id and application bundle id are required.")
        }
        configuration.apps.removeValue(forKey: bundleId)
        configuration.applicationMetadata.removeValue(forKey: bundleId)
        config.devices[deviceId] = configuration
        config.bumpRevision()
        ConfigStore.save(config)
        if config.selectedDeviceId == deviceId {
            applyProfile(forBundleId: focus.frontBundleId)
        }
        return ["ok": true, "revision": config.revision]
    }

    private func patchDeviceSettings(_ params: [String: Any]?) -> [String: Any] {
        if let conflict = revisionConflict(params) { return conflict }
        guard let deviceId = params?["deviceId"] as? String,
              var configuration = config.devices[deviceId],
              let patch = params?["settings"] as? [String: Any] else {
            return rpcError("invalid_settings", "Device settings are invalid.")
        }
        let descriptor = config.recentDevices[deviceId]
        let patchesHaptics = patch["hapticEnabled"] != nil
            || patch["hapticLevel"] != nil
            || patch["hapticPowerSave"] != nil
        if patchesHaptics, descriptor?.capabilities.haptics != true {
            return rpcError("unsupported_capability", "This device does not expose haptics.")
        }
        if patch["forceThreshold"] != nil, descriptor?.capabilities.forceSensing != true {
            return rpcError("unsupported_capability", "This device does not expose force sensing.")
        }
        if let value = patch["hapticEnabled"] {
            configuration.settings.hapticEnabled = JsonUtil.bool(value)
        }
        if let value = patch["hapticLevel"] {
            configuration.settings.hapticLevel = min(100, max(0, JsonUtil.int(value)))
        }
        if let value = patch["hapticPowerSave"] {
            configuration.settings.hapticPowerSave = JsonUtil.bool(value)
        }
        if let value = patch["forceThreshold"] {
            configuration.settings.forceThreshold = min(100, max(0, JsonUtil.int(value)))
        }
        config.devices[deviceId] = configuration
        config.bumpRevision()
        ConfigStore.save(config)

        var applied = true
        if config.selectedDeviceId == deviceId {
            if patch["hapticEnabled"] != nil || patch["hapticLevel"] != nil {
                let level = configuration.settings.hapticEnabled
                    ? configuration.settings.hapticLevel : 0
                applied = features?.setHapticLevel(level) ?? false
            }
            if let threshold = configuration.settings.forceThreshold,
               patch["forceThreshold"] != nil {
                applied = (features?.setForceThreshold(threshold) ?? false) && applied
            }
        }
        return ["ok": applied, "revision": config.revision]
    }

    private func rpcError(_ code: String, _ message: String) -> [String: Any] {
        [
            "ok": false,
            "error": ["code": code, "message": message],
            "revision": config.revision,
        ]
    }

    private func setButton(_ params: [String: Any]?) -> [String: Any] {
        guard let cid = params?["cid"] as? String,
              let actionObj = params?["action"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: actionObj),
              let action = try? JSONDecoder().decode(ActionSpec.self, from: data) else {
            return ["ok": false, "error": "invalid button params"]
        }
        let bundleId = params?["bundleId"] as? String
        if let bundleId {
            var app = config.apps[bundleId] ?? ProfileSettings()
            app.buttons[cid] = action
            config.apps[bundleId] = app
        } else {
            config.global.buttons[cid] = action
        }
        config.bumpRevision()
        ConfigStore.save(config)
        applyProfile(forBundleId: focus.frontBundleId)
        DaemonLog.info("setButton \(cid) → \(String(data: data, encoding: .utf8) ?? "?")")
        return ["ok": true]
    }
}

private extension DeviceFeatures {
    func resolveAlive() -> Bool {
        device.resolveFeature(.featureSet) != nil
    }
}

// Accessibility check
import ApplicationServices
