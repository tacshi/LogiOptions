import Cocoa
import FlutterMacOS
import XCTest

class RunnerTests: XCTestCase {

  func testFirstInstalledVersionTransitionsDaemon() {
    XCTAssertTrue(
      DaemonInstallPolicy.shouldTransition(
        currentVersion: "0.2.3+1",
        lastHandledVersion: nil
      )
    )
  }

  func testNewInstalledVersionTransitionsDaemon() {
    XCTAssertTrue(
      DaemonInstallPolicy.shouldTransition(
        currentVersion: "0.2.3+1",
        lastHandledVersion: "0.2.2+1"
      )
    )
  }

  func testReopeningSameVersionKeepsDaemonRunning() {
    XCTAssertFalse(
      DaemonInstallPolicy.shouldTransition(
        currentVersion: "0.2.3+1",
        lastHandledVersion: "0.2.3+1"
      )
    )
  }

}
