import XCTest

@testable import Launcher

/// Markdown evidence splits into the blocks the preview draws. These tests
/// do not check how a block looks or how inline syntax renders.
final class MarkdownTests: XCTestCase {
  func testBlocksAreSplitByKind() {
    let source = """
      # Login fix

      The redirect now keeps
      the page you asked for.

      - web
      - api
      2. second
      > quoted

      ```
      $ web test
        120 passed
      ```
      ---
      """
    XCTAssertEqual(
      MarkdownBlock.parse(source),
      [
        .heading(level: 1, text: "Login fix"),
        .paragraph("The redirect now keeps the page you asked for."),
        .bullet("web"), .bullet("api"), .numbered(marker: "2.", text: "second"),
        .quote("quoted"), .code("$ web test\n  120 passed"), .rule,
      ])
  }

  func testAHashWithoutASpaceIsText() {
    XCTAssertEqual(MarkdownBlock.parse("#hashtag"), [.paragraph("#hashtag")])
  }

  func testAnUnclosedFenceKeepsItsCode() {
    XCTAssertEqual(MarkdownBlock.parse("```\nlet x = 1"), [.code("let x = 1")])
  }
}
