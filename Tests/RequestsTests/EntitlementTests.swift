import Requests
import XCTest

/// The test runner has no iCloud entitlements, as an unsigned build of the
/// Mac app has none, so the check must say it may not use iCloud. This proves the
/// check refuses a process with no entitlements. It does not prove the check
/// admits a signed build; only the signed app can show that.
final class EntitlementTests: XCTestCase {
  func testAnUnsignedProcessIsNotEntitledToCloudKit() {
    XCTAssertFalse(entitledToCloudKit())
  }
}
