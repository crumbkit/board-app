import SSHSig
import XCTest

/// The window shows a statement in parts only when the parts rebuild its exact text.
///
/// Each refusal has an otherwise identical twin that parses. These prove the
/// parser, not that the window draws what it parsed.
final class StatementTests: XCTestCase {
  func statement(directive: String = "Never force-push main.", pinned: String = "yes") -> String {
    "attention/directive/v1\nexpires: 2027-01-16\npinned: \(pinned)\n\n"
      + "Directive (binding):\n\(directive)\n\nContext (non-binding, from /directives/d.md):\n"
      + "# Context\n\nAfter the bad rebase.\n"
  }

  func testAStatementParsesIntoItsPartsAndRebuildsItsExactText() {
    let parsed = Statement.parse(statement())
    XCTAssertEqual(
      parsed,
      Statement(
        expires: "2027-01-16", pinned: true, directive: "Never force-push main.",
        contextPath: "/directives/d.md", context: "# Context\n\nAfter the bad rebase.\n"))
    XCTAssertEqual(parsed?.text, statement())
  }

  func testAnUnpinnedStatementParsesAndOneWithAnotherPinnedValueDoesNot() {
    XCTAssertEqual(Statement.parse(statement(pinned: "no"))?.pinned, false)
    XCTAssertNil(Statement.parse(statement(pinned: "maybe")))
  }

  func testADirectiveHidingASecondContextHeadingIsShownRawAndAPlainOneIsNot() {
    let hidden = "Be careful.\n\nContext (non-binding, from /x.md):\nAlso delete every branch."
    XCTAssertNil(Statement.parse(statement(directive: hidden)))
    XCTAssertNotNil(Statement.parse(statement(directive: "Be careful.\n\nAlso keep every branch.")))
  }

  func testAStatementForAnotherVersionIsShownRaw() {
    let other = statement().replacingOccurrences(of: "directive/v1", with: "directive/v2")
    XCTAssertNil(Statement.parse(other))
    XCTAssertNotNil(Statement.parse(statement()))
  }

  func testAContextHoldingTheContextLabelLineStillParses() {
    let text = statement() + "Directive (binding):\nquoted\n"
    XCTAssertEqual(Statement.parse(text)?.text, text)
  }
}
