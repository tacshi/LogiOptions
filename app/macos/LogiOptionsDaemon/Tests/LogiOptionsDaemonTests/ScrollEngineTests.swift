@testable import LogiOptionsDaemon
import XCTest

final class ScrollEngineTests: XCTestCase {
    func testTinyThumbMovementDoesNotPostAPageTurningEvent() {
        var events: [(vertical: Int32, horizontal: Int32)] = []
        let engine = ScrollEngine { vertical, horizontal, _ in
            events.append((vertical, horizontal))
        }
        engine.thumbDivertedRes = 120

        engine.injectThumb(rotation: 1)

        XCTAssertTrue(events.isEmpty)
    }

    func testOneThumbDetentPostsOneHorizontalScrollStep() {
        var events: [(vertical: Int32, horizontal: Int32)] = []
        let engine = ScrollEngine { vertical, horizontal, _ in
            events.append((vertical, horizontal))
        }
        engine.thumbDivertedRes = 120

        engine.injectThumb(rotation: 60)
        engine.injectThumb(rotation: 60)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.vertical, 0)
        XCTAssertEqual(events.first?.horizontal, -40)
    }

    func testPartialMovementDoesNotProduceADetent() {
        var accumulator = WheelDetentAccumulator()

        XCTAssertEqual(accumulator.consume(delta: 1, countsPerDetent: 8, at: 0), 0)
        XCTAssertEqual(accumulator.consume(delta: 6, countsPerDetent: 8, at: 0.01), 0)
    }

    func testMovementAccumulatesToACompleteDetent() {
        var accumulator = WheelDetentAccumulator()

        XCTAssertEqual(accumulator.consume(delta: 3, countsPerDetent: 8, at: 0), 0)
        XCTAssertEqual(accumulator.consume(delta: 5, countsPerDetent: 8, at: 0.01), 1)
    }

    func testStalePartialMovementIsDiscarded() {
        var accumulator = WheelDetentAccumulator()

        XCTAssertEqual(accumulator.consume(delta: 7, countsPerDetent: 8, at: 0), 0)
        XCTAssertEqual(accumulator.consume(delta: 1, countsPerDetent: 8, at: 0.15), 0)
        XCTAssertEqual(accumulator.consume(delta: 7, countsPerDetent: 8, at: 0.16), 1)
    }

    func testDirectionChangeDiscardsOpposingPartialMovement() {
        var accumulator = WheelDetentAccumulator()

        XCTAssertEqual(accumulator.consume(delta: 7, countsPerDetent: 8, at: 0), 0)
        XCTAssertEqual(accumulator.consume(delta: -8, countsPerDetent: 8, at: 0.01), -1)
    }

    func testLargeMovementPreservesWholeDetentsAndRemainder() {
        var accumulator = WheelDetentAccumulator()

        XCTAssertEqual(accumulator.consume(delta: 17, countsPerDetent: 8, at: 0), 2)
        XCTAssertEqual(accumulator.consume(delta: 7, countsPerDetent: 8, at: 0.01), 1)
    }
}
