import AppKit
import Requests
import XCTest

/// The request and pairing screens name the device's biometry and show its
/// symbol. This pins each name and proves each symbol exists in SF Symbols
/// on this Mac. It does not prove which biometry a device reports, nor the
/// mapping from LocalAuthentication's type.
final class BiometryTests: XCTestCase {
  func testEachBiometryHasItsNameAndARealSymbol() {
    XCTAssertEqual(Biometry.allCases.map(\.name), ["Face ID", "Touch ID", "Optic ID"])
    for biometry in Biometry.allCases {
      XCTAssertNotNil(
        NSImage(systemSymbolName: biometry.symbol, accessibilityDescription: nil), biometry.symbol)
    }
  }
}
