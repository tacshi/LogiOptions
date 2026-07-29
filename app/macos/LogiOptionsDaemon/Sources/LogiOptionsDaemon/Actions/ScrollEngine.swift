import CoreGraphics
import Foundation

struct WheelDetentAccumulator {
    private static let inactivityResetInterval: TimeInterval = 0.15

    private var remainder = 0
    private var lastEventTime: TimeInterval?

    mutating func consume(
        delta: Int16,
        countsPerDetent: Int,
        at eventTime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Int {
        guard delta != 0 else { return 0 }

        if let lastEventTime,
           eventTime < lastEventTime
            || eventTime - lastEventTime >= Self.inactivityResetInterval {
            remainder = 0
        }

        let value = Int(delta)
        if remainder != 0, (remainder < 0) != (value < 0) {
            remainder = 0
        }

        lastEventTime = eventTime
        remainder += value

        let threshold = max(countsPerDetent, 1)
        let detents = remainder / threshold
        remainder -= detents * threshold
        return detents
    }
}

/// Host-side wheel injection matching Options+ “smooth + speed” behaviour.
///
/// When the wheel is **diverted**, firmware invert bits often do not flip the
/// HID++ notification stream — invert is applied here in software.
final class ScrollEngine {
    typealias EventPoster = (
        _ vertical: Int32,
        _ horizontal: Int32,
        _ flags: CGEventFlags
    ) -> Void

    /// 0…2 host scale (1.0 = 100%, 2.0 = 200%).
    var verticalSpeed: Double = 1.0
    /// 0…2 thumb scale (1.0 = 100%).
    var thumbSpeed: Double = 1.0

    /// Software invert (required while host-diverted).
    var invertVertical = false
    var invertThumb = false

    /// From HIRES_WHEEL capabilities (typically 8): counts per ratchet notch.
    var hiresMultiplier: Double = 8
    /// From THUMB_WHEEL getInfo: high-resolution counts per scroll detent.
    /// MX Master 3S reports 120 while diverted.
    var thumbDivertedRes: Double = 48

    private var vertRemainder: Double = 0
    private var horizRemainder: Double = 0
    private var verticalDetents = WheelDetentAccumulator()
    private var thumbDetents = WheelDetentAccumulator()
    private let eventPoster: EventPoster

    /// Pixels per physical wheel detent at speed = 1.0.
    private let pixelsPerNotch: Double = 40

    init(eventPoster: @escaping EventPoster = ScrollEngine.postScrollEvent) {
        self.eventPoster = eventPoster
    }

    /// Vertical MagSpeed / hi-res wheel movement (`deltaV` from 0x2121).
    func injectVertical(deltaV: Int16) {
        guard deltaV != 0 else { return }
        let detents = verticalDetents.consume(
            delta: deltaV,
            countsPerDetent: max(Int(hiresMultiplier.rounded()), 1)
        )
        guard detents != 0 else { return }

        // Negate so positive device “scroll down” matches macOS content direction
        // with natural scrolling (Options+ NATURAL). Software invert flips again.
        var pixels = -Double(detents) * verticalSpeed * pixelsPerNotch
        if invertVertical { pixels = -pixels }

        let mods = Self.currentModifiers()
        if mods.contains(.maskShift) {
            // Shift + wheel = horizontal scroll (Options+ / macOS convention).
            // The wheel is host-diverted, so the OS never sees the physical wheel
            // and cannot do this itself. Strip Shift from the posted event: we
            // already chose the axis; leaving Shift on can make apps swap twice.
            postPixel(
                vertical: 0,
                horizontal: pixels,
                flags: mods.subtracting(.maskShift)
            )
        } else {
            postPixel(vertical: pixels, horizontal: 0, flags: mods)
        }
    }

    /// Thumb wheel rotation from 0x2150 (already host-diverted).
    func injectThumb(rotation: Int16) {
        guard rotation != 0 else { return }
        let detents = thumbDetents.consume(
            delta: rotation,
            countsPerDetent: max(Int(thumbDivertedRes.rounded()), 1)
        )
        guard detents != 0 else { return }

        // Match vertical sign convention for “natural” feel on macOS.
        var pixels = -Double(detents) * thumbSpeed * pixelsPerNotch
        if invertThumb { pixels = -pixels }
        // Already horizontal — Shift would only confuse axis handling.
        postPixel(
            vertical: 0,
            horizontal: pixels,
            flags: Self.currentModifiers().subtracting(.maskShift)
        )
    }

    /// Live modifier state. HID++ runs on the main run loop; this is a cheap
    /// read of the session keyboard state (no event tap required).
    private static func currentModifiers() -> CGEventFlags {
        CGEventSource.flagsState(.combinedSessionState).intersection([
            .maskCommand, .maskShift, .maskControl, .maskAlternate, .maskSecondaryFn,
        ])
    }

    private func postPixel(vertical: Double, horizontal: Double, flags: CGEventFlags = []) {
        vertRemainder += vertical
        horizRemainder += horizontal

        let v = Int32(vertRemainder.rounded(.towardZero))
        let h = Int32(horizRemainder.rounded(.towardZero))
        vertRemainder -= Double(v)
        horizRemainder -= Double(h)
        guard v != 0 || h != 0 else { return }

        eventPoster(v, h, flags)
    }

    private static func postScrollEvent(
        vertical v: Int32,
        horizontal h: Int32,
        flags: CGEventFlags
    ) {
        let loc = CGEvent(source: nil)?.location ?? .zero
        // wheel1 = vertical, wheel2 = horizontal (CGEvent).
        guard let ev = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: v,
            wheel2: h,
            wheel3: 0
        ) else { return }
        ev.location = loc
        if !flags.isEmpty {
            ev.flags = flags
        }
        ev.post(tap: .cghidEventTap)
    }
}
