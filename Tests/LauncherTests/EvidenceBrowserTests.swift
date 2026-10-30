import Foundation
import XCTest

@testable import Launcher

/// The preview window's model: moving between files, the name search and
/// the metadata comparison. These tests do not render a file.
final class EvidenceBrowserTests: XCTestCase {
  private func browser(at index: Int = 1) throws -> EvidenceBrowser {
    let files = try Fixtures.listing("parts.json").items.compactMap(\.evidenceFile)
    return EvidenceBrowser(files: files, index: index)
  }

  func testArrowsMoveBetweenFilesAndStopAtTheEnds() throws {
    var browser = try browser(at: 0)
    XCTAssertEqual(browser.position, "1 of 3")
    XCTAssertFalse(browser.hasPrevious)
    browser.move(-1)
    XCTAssertEqual(browser.current.name, "report.md")
    browser.move(1)
    browser.move(1)
    XCTAssertEqual(browser.position, "3 of 3")
    XCTAssertFalse(browser.hasNext)
  }

  func testTheComparisonShowsThePreviousCurrentAndNextFile() throws {
    let rows = try browser().comparison
    XCTAssertEqual(
      rows.map(\.label),
      ["Kind", "Size (reported)", "Added", "Task record", "SHA-256 (reported)"])
    XCTAssertEqual(rows[0].previous, "Markdown")
    XCTAssertEqual(rows[0].current, "PNG image")
    XCTAssertEqual(rows[0].next, "Log")
    XCTAssertEqual(rows[2].current, "2026-10-29 11:30")
    XCTAssertEqual(rows[3].current, "—")
    XCTAssertEqual(rows[4].current, "fedcba987654")
  }

  func testTheFirstFileHasNoPreviousColumn() throws {
    let rows = try browser(at: 0).comparison
    XCTAssertNil(rows[0].previous)
    XCTAssertEqual(rows[0].next, "PNG image")
  }

  func testSearchFiltersByNameAndEnterShowsTheChoice() throws {
    var browser = try browser(at: 0)
    browser.openSearch()
    XCTAssertTrue(browser.searching)
    XCTAssertEqual(browser.matches.count, 3)
    browser.query = "LOG"
    XCTAssertEqual(browser.matches.map(\.name), ["run.log"])
    browser.closeSearch(choosing: true)
    XCTAssertFalse(browser.searching)
    XCTAssertEqual(browser.current.name, "run.log")
  }

  func testEscLeavesTheSearchWithoutChanging() throws {
    var browser = try browser(at: 0)
    browser.openSearch()
    browser.moveSearch(2)
    browser.closeSearch(choosing: false)
    XCTAssertEqual(browser.current.name, "report.md")
  }

  func testEachFileIsDrawnByItsKind() {
    XCTAssertEqual(PreviewKind.of(path: "/a/report.MD"), .markdown)
    XCTAssertEqual(PreviewKind.of(path: "/a/screen.png"), .image)
    XCTAssertEqual(PreviewKind.of(path: "/a/run.log"), .text)
    XCTAssertEqual(PreviewKind.of(path: "/a/Makefile"), .text)
    XCTAssertEqual(PreviewKind.of(path: "/a/talk.pdf"), .other)
  }
}
