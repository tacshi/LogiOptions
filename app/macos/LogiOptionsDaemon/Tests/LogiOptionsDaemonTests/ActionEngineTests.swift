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

    func testBrowsersUseHistoryShortcut() {
        for bundleId in ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox",
                         "com.microsoft.edgemac", "company.thebrowser.Browser"] {
            XCTAssertEqual(
                ActionEngine.navigationAction(
                    for: "back",
                    frontmostBundleIdentifier: bundleId
                ),
                .keystroke(["cmd", "["]),
                "back in \(bundleId)"
            )
            XCTAssertEqual(
                ActionEngine.navigationAction(
                    for: "forward",
                    frontmostBundleIdentifier: bundleId
                ),
                .keystroke(["cmd", "]"]),
                "forward in \(bundleId)"
            )
        }
    }

    func testBrowserNavigationIsMomentaryRatherThanHeldMouseState() {
        XCTAssertEqual(
            ActionEngine.mousePress(
                for: "back",
                frontmostBundleIdentifier: "com.google.Chrome"
            ),
            .momentaryKeystroke(["cmd", "["])
        )
    }

    func testOtherAppsKeepAuxiliaryMouseNavigation() {
        XCTAssertEqual(
            ActionEngine.navigationAction(
                for: "back",
                frontmostBundleIdentifier: "com.apple.dt.Xcode"
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
