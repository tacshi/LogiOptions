import AppKit
import CoreGraphics
import Foundation

/// 4-way gesture button tracker (MX Master gesture CID + RAW_XY).
///
/// Modelled on **logiops GestureAction** + Options+ feel:
///
/// - **Per-direction progress** from each RAW_XY sample (not net position).
///   Going left then returning right credits `left` then `right` separately, so
///   the intended outward stroke still wins — net/peak vectors flip and cause
///   L↔R / U↔D mis-fires.
/// - **Settle window** after press ignores the first few samples (button jitter).
/// - **OnRelease** is the primary decision (logiops / Options+ default configs).
/// - **Early fire** only when one direction is clearly leading (high progress +
///   strong lead over the second), for 跟手 without locking a false start.
///
/// Sensor axes (HID++ RAW_XY / logiops): +X right, +Y down, −Y up.
final class GestureTracker {
    private let engine: ActionEngine
    private var active = false
    private var origin: CGPoint = .zero
    private var last: CGPoint = .zero
    private var hasRawXY = false
    private var gestureSpec: ActionSpec?
    private var map: GestureMap?

    // Net displacement (debug / screen fallback only).
    private var netDX: CGFloat = 0
    private var netDY: CGFloat = 0

    /// Travel accumulated *into* each cardinal direction (logiops-style).
    private var progressUp: CGFloat = 0
    private var progressDown: CGFloat = 0
    private var progressLeft: CGFloat = 0
    private var progressRight: CGFloat = 0

    private var beginTime: CFTimeInterval = 0
    private var fired = false
    private var locked: Direction?

    /// Ignore motion right after press (ms) — Options+ effectively debounces press.
    private let settleMs: CFTimeInterval = 0.045
    /// logiops default threshold ≈ 50 raw counts.
    private let releaseThreshold: CGFloat = 55
    /// Early fire needs more travel so a false start cannot steal the stroke.
    private let liveThreshold: CGFloat = 110
    /// Early: winner must lead second place by this ratio.
    private let liveLead: CGFloat = 2.2
    /// Release: mild lead so diagonals still resolve.
    private let releaseLead: CGFloat = 1.15
    private let screenThreshold: CGFloat = 30

    private enum Direction: String, Equatable {
        case up, down, left, right
    }

    init(engine: ActionEngine) {
        self.engine = engine
    }

    func begin(spec: ActionSpec) {
        gestureSpec = spec
        if case let .gesture(m) = spec {
            map = m
        } else {
            map = nil
        }
        active = true
        hasRawXY = false
        netDX = 0
        netDY = 0
        progressUp = 0
        progressDown = 0
        progressLeft = 0
        progressRight = 0
        fired = false
        locked = nil
        beginTime = CACurrentMediaTime()
        origin = CGEvent(source: nil)?.location ?? .zero
        last = origin
        DaemonLog.info("gesture begin")
    }

    func updatePointer() {
        guard active, !hasRawXY else { return }
        let p = CGEvent(source: nil)?.location ?? last
        let dx = p.x - last.x
        let dy = p.y - last.y
        last = p
        guard abs(dx) > 0.5 || abs(dy) > 0.5 else { return }
        credit(dx: dx, dy: dy)
        maybeEarlyFire()
    }

    /// RAW_XY divert stream (REPROG_CONTROLS_V4 event 0x10).
    func addRawDelta(dx: Int16, dy: Int16) {
        guard active else { return }
        hasRawXY = true
        credit(dx: CGFloat(dx), dy: CGFloat(dy))
        maybeEarlyFire()
    }

    func end() {
        guard active else { return }
        active = false
        defer { resetState() }

        guard let spec = gestureSpec else { return }

        if case let .gesture(gestureMap) = spec {
            if fired {
                DaemonLog.info(
                    "gesture end alreadyFired locked=\(locked?.rawValue ?? "-") " +
                    progressSummary()
                )
                return
            }

            let simple: SimpleAction
            if let dir = bestDirection(
                minProgress: hasRawXY ? releaseThreshold : screenThreshold,
                minLead: releaseLead
            ) {
                locked = dir
                simple = action(for: dir, map: gestureMap)
            } else {
                simple = gestureMap.click
            }

            DaemonLog.info(
                "gesture end → \(simple) locked=\(locked?.rawValue ?? "click") " +
                progressSummary()
            )
            engine.execute(simple.toActionSpec())
            fired = true
        } else {
            engine.execute(spec)
        }
    }

    var isActive: Bool { active }

    // MARK: - Progress (logiops-style)

    private func credit(dx: CGFloat, dy: CGFloat) {
        // Settle: drop early noise from button press / hand shift.
        if CACurrentMediaTime() - beginTime < settleMs {
            return
        }

        netDX += dx
        netDY += dy

        // Independent axis credit (same idea as logiops GestureAction::move).
        if dx > 0 {
            progressRight += dx
        } else if dx < 0 {
            progressLeft += -dx
        }
        if dy > 0 {
            progressDown += dy
        } else if dy < 0 {
            progressUp += -dy
        }
    }

    private func maybeEarlyFire() {
        guard active, !fired, let gestureMap = map else { return }
        let thr = hasRawXY ? liveThreshold : screenThreshold * 2.5
        guard let dir = bestDirection(minProgress: thr, minLead: liveLead) else { return }

        locked = dir
        DaemonLog.info(
            "gesture fire \(dir.rawValue) (early) " + progressSummary()
        )
        engine.execute(action(for: dir, map: gestureMap).toActionSpec())
        fired = true
    }

    /// Winner among the four progress buckets.
    private func bestDirection(minProgress: CGFloat, minLead: CGFloat) -> Direction? {
        let scored: [(Direction, CGFloat)] = [
            (.up, progressUp),
            (.down, progressDown),
            (.left, progressLeft),
            (.right, progressRight),
        ]
        let sorted = scored.sorted { $0.1 > $1.1 }
        guard let first = sorted.first, first.1 >= minProgress else { return nil }
        let second = sorted.count > 1 ? sorted[1].1 : 0
        // Require a clear lead when the second place is meaningful.
        if second > minProgress * 0.35 && first.1 < second * minLead {
            return nil
        }
        return first.0
    }

    private func action(for dir: Direction, map: GestureMap) -> SimpleAction {
        switch dir {
        case .up: return map.up
        case .down: return map.down
        case .left: return map.left
        case .right: return map.right
        }
    }

    private func progressSummary() -> String {
        String(
            format: "prog U=%.0f D=%.0f L=%.0f R=%.0f net=(%.0f,%.0f) rawXY=%@",
            progressUp, progressDown, progressLeft, progressRight,
            netDX, netDY, String(hasRawXY)
        )
    }

    private func resetState() {
        gestureSpec = nil
        map = nil
        locked = nil
        fired = false
    }
}
