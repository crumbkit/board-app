import Foundation
import Requests
import SSHSig
import XCTest

/// The request screen's diff: which lines and fields it shows as changed, and
/// which words inside them it marks. These tests prove the rows for the
/// design's two examples and the edge cases named; they do not prove the
/// diff is minimal for every input.
final class DiffTests: XCTestCase {
  func testAChangedLineSitsBesideItsOldVersionWithTheDateMarkedWhole() {
    let rows = LineDiff.rows("a\ndefer: \"2026-10-29\"\nb\n", "a\ndefer: \"2026-11-02\"\nb\n")
    XCTAssertEqual(rows.count, 3)
    XCTAssertTrue(rows[0].isSame)
    XCTAssertEqual(rows[1].old?.number, 2)
    XCTAssertEqual(rows[1].old?.text, Marked("defer: \"", "2026-10-29", "\""))
    XCTAssertEqual(rows[1].new?.text, Marked("defer: \"", "2026-11-02", "\""))
    XCTAssertTrue(rows[2].isSame)
  }

  func testAnInsertedLineStandsAloneAndLaterLinesStayLevel() {
    let rows = LineDiff.rows("a\nb\n", "a\nnew\nb\n")
    XCTAssertEqual(rows.map { $0.old?.number }, [1, nil, 2])
    XCTAssertEqual(rows.map { $0.new?.number }, [1, 2, 3])
  }

  func testANewFileIsEveryLineAdded() {
    let rows = LineDiff.rows("", "x\ny")
    XCTAssertEqual(rows.map { $0.new?.text.text }, ["x", "y"])
    XCTAssertTrue(rows.allSatisfy { $0.old == nil })
  }

  func testCarriageReturnsStayOnTheirLine() {
    XCTAssertEqual(LineDiff.lines("a\r\nb\r\n"), ["a\r", "b\r"])
  }

  func testARecordIsComparedFieldByFieldWithTheNumberMarked() throws {
    let old = try JSONValue.parse(
      Data(
        #"{"requirement": "at most 400 words", "rule": {"max": 400, "budget": "words"}, "paths": ["a"]}"#
          .utf8))
    let new = try JSONValue.parse(
      Data(
        #"{"requirement": "at most 450 words", "rule": {"max": 450, "budget": "words"}, "paths": ["a"], "note": "x"}"#
          .utf8))
    let diff = FieldDiff.compare(old, new)
    XCTAssertEqual(diff.changed.map(\.key), ["note", "requirement", "rule › max"])
    XCTAssertNil(diff.changed[0].old)
    XCTAssertEqual(diff.changed[1].new, Marked("at most ", "450", " words"))
    XCTAssertEqual(diff.changed[2].old, Marked("", "400", ""))
    XCTAssertEqual(diff.same, ["paths", "rule › budget"])
  }

  func testARequestShowsNoDiffWhenItsOldVersionCouldNotBeRead() throws {
    let request = try RequestTests.request(RequestTests.task)
    XCTAssertNil(request.lineRows)
    let read = try RequestTests.request(RequestTests.task, prior: "---\n")
    XCTAssertNotNil(read.lineRows)
    XCTAssertNil(try RequestTests.request(RequestTests.review).lineRows)
  }

  func testARemovalShowsEveryOldLineRemoved() throws {
    let removal = try RequestTests.request(
      #""plugin": "tasks", "op": "rm", "path": "/tasks/a.md""#, prior: "x\ny\n")
    XCTAssertEqual(removal.lineRows?.map { $0.old?.text.text }, ["x", "y"])
    XCTAssertTrue(removal.lineRows?.allSatisfy { $0.new == nil } ?? false)
  }

  func testThePlainWordsSayWhatAnApprovalAllowsAndWhatItDoesNotCover() throws {
    let review = try RequestTests.request(RequestTests.review)
    XCTAssertEqual(review.allows, "Approving lets review post from this report whenever it runs.")
    XCTAssertEqual(
      review.limits,
      "Your approval names the report, not its words. If the report changes, review can post the new words."
    )
    let task = try RequestTests.request(RequestTests.task)
    XCTAssertEqual(task.allows, "Approving lets tasks write exactly this version.")
    XCTAssertEqual(
      task.limits,
      "If the task changes first, this approval no longer fits and tasks has to ask again.")
  }

  func testAFieldThatChangesTypeIsShownAsChangedWithTheStringQuoted() throws {
    let diff = FieldDiff.compare(
      try JSONValue.parse(Data(#"{"max": "400", "tags": ["a  b"]}"#.utf8)),
      try JSONValue.parse(Data(#"{"max": 400, "tags": ["ab"]}"#.utf8)))
    XCTAssertEqual(diff.changed.map(\.key), ["max", "tags"])
    XCTAssertEqual(diff.changed[0].old?.text, "\"400\"")
    XCTAssertEqual(diff.changed[0].new?.text, "400")
    XCTAssertEqual(diff.changed[1].old?.text, "[\"a  b\"]")
    XCTAssertTrue(diff.same.isEmpty)
  }

  func testAKeyThatLooksLikeAPathIsKeptApartFromThePath() throws {
    let diff = FieldDiff.compare(
      try JSONValue.parse(Data(#"{"a › b": 1, "a": {"b": 1}}"#.utf8)),
      try JSONValue.parse(Data(#"{"a › b": 2, "a": {"b": 1}}"#.utf8)))
    XCTAssertEqual(diff.changed.map(\.key), ["a › b"])
    XCTAssertEqual(diff.changed[0].new?.text, "2")
    XCTAssertEqual(diff.same, ["a › b"])
  }

  func testHiddenCharactersShowEscapedAsTheStatementShowsThem() {
    let rows = LineDiff.rows("", "pay \u{202E}eno\n")
    XCTAssertEqual(rows.map { $0.new?.text.text }, ["pay \\u{202e}eno"])
  }

  func testTwoChangesFarApartAreTwoRowsWithTheSameLinesBetween() {
    let rows = LineDiff.rows("a\nb\nc\nd\ne\n", "A\nb\nc\nd\nE\n")
    XCTAssertEqual(rows.map(\.isSame), [false, true, true, true, false])
    XCTAssertEqual(rows.map { $0.new?.number }, [1, 2, 3, 4, 5])
    XCTAssertEqual(
      LineDiff.summary(rows), "Lines 1 and 5 change. The other 3 are the same; scroll to read them."
    )
  }

  func testAWordThatRepeatsIsMarkedOnlyWhereItChanges() {
    let marked = Marked.pair("a b a", "a c a")
    XCTAssertEqual(marked.old, Marked("a ", "b", " a"))
    XCTAssertEqual(marked.new, Marked("a ", "c", " a"))
  }

  func testTheSummaryNamesOneLineOrCountsMany() {
    XCTAssertEqual(LineDiff.summary(LineDiff.rows("a\n", "b\n")), "Line 1 changes.")
    XCTAssertEqual(LineDiff.summary(LineDiff.rows("", "1\n2\n3\n4\n5\n")), "5 lines change.")
  }

  func testARecordIsComparedAsBoardPrintsItSoFormattingIsNoChange() throws {
    let control = try RequestTests.request(
      RequestTests.control, prior: #"{"rule":{"max":400},"$type":"controls/control/v1"}"#)
    XCTAssertEqual(control.lineRows?.filter { !$0.isSame }.count, 1)
  }
}
