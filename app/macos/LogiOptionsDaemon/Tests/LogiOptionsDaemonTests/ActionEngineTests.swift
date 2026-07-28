@testable import LogiOptionsDaemon
import XCTest

final class ActionEngineTests: XCTestCase {
    func testFinderBackUsesHistoryShortcut() {
        XCTAssertEqual(
            ActionEngine.navigationAction(
                for: "back",
                frontmostBundleIdentifier: "com.apple.finder"
            ),
            .keystroke(["cmd", "["])
        )
    }

    func testFinderForwardUsesHistoryShortcut() {
        XCTAssertEqual(
            ActionEngine.navigationAction(
                for: "forward",
                frontmostBundleIdentifier: "com.apple.finder"
            ),
            .keystroke(["cmd", "]"])
        )
    }

    func testOtherAppsKeepAuxiliaryMouseNavigation() {
        XCTAssertEqual(
            ActionEngine.navigationAction(
                for: "back",
                frontmostBundleIdentifier: "com.apple.Safari"
            ),
            .auxiliaryMouseButton(3)
        )
        XCTAssertEqual(
            ActionEngine.navigationAction(
                for: "forward",
                frontmostBundleIdentifier: nil
            ),
            .auxiliaryMouseButton(4)
        )
    }

    func testPrimaryMouseAssignmentsPreservePressLifecycle() {
        XCTAssertEqual(
            ActionEngine.mousePress(
                for: "left",
                frontmostBundleIdentifier: "com.apple.finder"
            ),
            .standard("left")
        )
        XCTAssertEqual(
            ActionEngine.mousePress(
                for: "middle",
                frontmostBundleIdentifier: "com.apple.Safari"
            ),
            .standard("middle")
        )
    }

    func testFinderNavigationIsMomentaryRatherThanHeldMouseState() {
        XCTAssertEqual(
            ActionEngine.mousePress(
                for: "back",
                frontmostBundleIdentifier: "com.apple.finder"
            ),
            .momentaryKeystroke(["cmd", "["])
        )
    }
}
