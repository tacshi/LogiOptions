import CoreGraphics
import Foundation

/// Host-side wheel injection matching Options+ “smooth + speed” behaviour.
///
/// When the wheel is **diverted**, firmware invert bits often do not flip the
/// HID++ notification stream — invert is applied here in software.
final class ScrollEngine {
    /// 0…2 host scale (1.0 = 100%, 2.0 = 200%).
    var verticalSpeed: Double = 1.0
    /// 0…2 thumb scale (1.0 = 100%).
    var thumbSpeed: Double = 1.0

    /// Software invert (required while host-diverted).
    var invertVertical = false
    var invertThumb = false

    /// From HIRES_WHEEL capabilities (typically 8): counts per ratchet notch.
    var hiresMultiplier: Double = 8
    /// From THUMB_WHEEL getInfo diverted resolution (counts per full revolution).
    /// MX Master 3S reports native≈18, diverted≈120 when diverted.
    var thumbDivertedRes: Double = 48

    private var vertRemainder: Double = 0
    private var horizRemainder: Double = 0

    /// Pixels per MagSpeed ratchet notch at vertical speed = 1.0.
    private let pixelsPerNotch: Double = 40
    /// Pixels for one full physical thumb-wheel revolution at thumb speed = 1.0.
    ///
    /// Must not reuse `pixelsPerNotch`: divertedRes is ~120 counts/rev, so
    /// `rotation/res * 40` only moves ~40 px per full turn (80 px at 200%) —
    /// far too slow. Options+ is closer to several hundred px per revolution.
    private let thumbPixelsPerRevolution: Double = 720

    /// Vertical MagSpeed / hi-res wheel movement (`deltaV` from 0x2121).
    func injectVertical(deltaV: Int16) {
        guard deltaV != 0 else { return }
        let multi = max(hiresMultiplier, 1)
        // Negate so positive device “scroll down” matches macOS content direction
        // with natural scrolling (Options+ NATURAL). Software invert flips again.
        var pixels = -Double(deltaV) / multi * verticalSpeed * pixelsPerNotch
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
        // `thumbDivertedRes` = counts per full revolution while diverted.
        let res = max(thumbDivertedRes, 1)
        // Match vertical sign convention for “natural” feel on macOS.
        var pixels =
            -Double(rotation) / res * thumbSpeed * thumbPixelsPerRevolution
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
