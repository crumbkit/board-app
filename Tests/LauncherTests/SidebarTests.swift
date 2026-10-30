import Foundation
import XCTest

@testable import Launcher

/// The sidebar choice persists. The test uses its own defaults suite, not
/// the app's.
final class SidebarTests: XCTestCase {
  func testTheChoiceIsRememberedByTheNextReader() throws {
    let suite = "launcher-sidebar-\(UUID().uuidString)"
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    XCTAssertFalse(defaults.launcherSidebarHidden)
    defaults.launcherSidebarHidden = true
    XCTAssertTrue(try XCTUnwrap(UserDefaults(suiteName: suite)).launcherSidebarHidden)
  }
}
