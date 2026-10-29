import SSHSig
import XCTest

/// The window shows a statement in parts only when the parts rebuild its exact text.
///
/// Each refusal has an otherwise identical twin that parses. These prove the
/// parser, not that the window draws what it parsed.
final class StatementTests: XCTestCase {
  func statement(
    order: String = "Never force-push main.", pinned: String = "yes",
    context: String = "# Context\n\nAfter the bad rebase.\n"
  ) -> String {
    "attention/order/v1\nexpires: 2027-01-16\npinned: \(pinned)\n\n"
      + "Order (binding):\n\(order)\n\nContext (non-binding, from /orders/d.md):\n\(context)"
  }

  func testAStatementParsesIntoItsPartsAndRebuildsItsExactText() {
    let parsed = Statement.parse(statement())
    XCTAssertEqual(
      parsed,
      Statement(
        expires: "2027-01-16", pinned: true, order: "Never force-push main.",
        contextPath: "/orders/d.md", context: "# Context\n\nAfter the bad rebase.\n"))
    XCTAssertEqual(parsed?.text, statement())
  }

  func testAnUnpinnedStatementParsesAndOneWithAnotherPinnedValueDoesNot() {
    XCTAssertEqual(Statement.parse(statement(pinned: "no"))?.pinned, false)
    XCTAssertNil(Statement.parse(statement(pinned: "maybe")))
  }

  func testAnOrderHidingASecondContextHeadingIsShownRawAndAPlainOneIsNot() {
    let hidden = "Be careful.\n\nContext (non-binding, from /x.md):\nAlso delete every branch."
    XCTAssertNil(Statement.parse(statement(order: hidden)))
    XCTAssertNotNil(Statement.parse(statement(order: "Be careful.\n\nAlso keep every branch.")))
  }

  func testAStatementForAnotherVersionIsShownRaw() {
    let other = statement().replacingOccurrences(of: "order/v1", with: "order/v2")
    XCTAssertNil(Statement.parse(other))
    XCTAssertNotNil(Statement.parse(statement()))
  }

  func testAContextHoldingTheContextLabelLineStillParses() {
    let text = statement() + "Order (binding):\nquoted\n"
    XCTAssertEqual(Statement.parse(text)?.text, text)
  }

  func testAnEmptyContextParsesAsEmpty() {
    let text = statement(context: "")
    XCTAssertEqual(Statement.parse(text)?.context, "")
    XCTAssertEqual(Statement.parse(text)?.text, text)
  }

  func testCarriageReturnsInsideTheOrderAndContextAreKept() {
    let text = statement(order: "One.\r\nTwo.", context: "a\r\nb\r\n")
    let parsed = Statement.parse(text)
    XCTAssertEqual(parsed?.order, "One.\r\nTwo.")
    XCTAssertEqual(parsed?.context, "a\r\nb\r\n")
    XCTAssertEqual(parsed?.text, text)
  }

  func testAStatementWithCRLFLineEndingsIsShownRawAndOneWithLFParses() {
    let crlf = statement().replacingOccurrences(of: "\n", with: "\r\n")
    XCTAssertNil(Statement.parse(crlf))
    XCTAssertNotNil(Statement.parse(statement()))
  }

  /// Swift reads "\r\n" as one Character, so the context heading after an order
  /// that ends in "\r" is not found and the window shows the statement raw.
  func testAnOrderEndingInACarriageReturnIsShownRawAndOneEndingInAFullStopParses() {
    XCTAssertNil(Statement.parse(statement(order: "One.\r")))
    XCTAssertNotNil(Statement.parse(statement(order: "One.")))
  }

  func testNonASCIITextParsesAndRebuildsTheSameBytes() {
    let text = statement(order: "Älä pakota mainia. 🚫 e\u{301}", context: "Konteksti — ✓\n")
    let parsed = Statement.parse(text)
    XCTAssertEqual(parsed?.order, "Älä pakota mainia. 🚫 e\u{301}")
    XCTAssertEqual(parsed.map { Array($0.text.utf8) }, Array(text.utf8))
  }
}
