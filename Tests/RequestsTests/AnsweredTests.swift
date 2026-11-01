import Foundation
import Requests
import SSHSig
import XCTest

/// The Mac window's Answered list reads `board/seen/v1` records and the times
/// git committed them. These tests pin what it reads from each.
final class AnsweredTests: XCTestCase {
  let id = String(repeating: "a", count: 64)
  let other = String(repeating: "b", count: 64)

  func seen(_ fields: String) -> Data {
    Data(
      #"{"$type": "board/seen/v1", "effect": "/effects/answered/\#(id)", \#(fields)}"#.utf8)
  }

  func testARefusalCarriesItsReason() throws {
    let answer = try SeenAnswer(json: seen(#""answer": "refuse", "reason": "Nope""#))
    XCTAssertEqual(answer.effect, id)
    XCTAssertFalse(answer.approved)
    XCTAssertEqual(answer.reason, "Nope")
    XCTAssertNil(answer.signature)
  }

  func testAnApprovalCarriesItsSignature() throws {
    let answer = try SeenAnswer(json: seen(#""answer": "approve", "signature": "SIG""#))
    XCTAssertTrue(answer.approved)
    XCTAssertEqual(answer.signature, "SIG")
  }

  func testAnEmptyReasonIsNoReason() throws {
    XCTAssertNil(try SeenAnswer(json: seen(#""answer": "refuse", "reason": """#)).reason)
  }

  func testARecordOfAnotherTypeOrAnswerOrPathIsRefused() {
    XCTAssertThrowsError(try SeenAnswer(json: Data(#"{"$type": "x", "answer": "refuse"}"#.utf8)))
    XCTAssertThrowsError(try SeenAnswer(json: seen(#""answer": "maybe""#)))
    XCTAssertThrowsError(
      try SeenAnswer(
        json: Data(
          #"{"$type": "board/seen/v1", "answer": "refuse", "effect": "/effects/pending/\#(id)"}"#
            .utf8)))
  }

  func testTimesKeepEachRecordsNewestCommitAndSkipOtherFiles() {
    let log = """
      1762008000

      effects/seen/\(id).json
      effects/seen/README.md

      1762000000

      effects/seen/\(other).json
      effects/seen/\(id).json
      """
    let times = SeenAnswer.times(log)
    XCTAssertEqual(times.map(\.effect), [id, other])
    XCTAssertEqual(times.map(\.at.timeIntervalSince1970), [1_762_008_000, 1_762_000_000])
  }

  func testAnAnsweredRequestIsWordedInThePastTense() throws {
    XCTAssertEqual(
      try RequestTests.request(RequestTests.review).askedSentence, "review asked to post it")
    XCTAssertEqual(
      try RequestTests.request(RequestTests.task).askedSentence,
      "tasks wanted to change this task")
  }

  func testTheSummaryIsTheFirstLineAfterFrontMatter() throws {
    XCTAssertEqual(try RequestTests.request(RequestTests.task).summary, "Body")
    let review = try RequestTests.request(
      RequestTests.review + #", "text": "\nBoard.app schema test 3: approve this.\nMore\n""#)
    XCTAssertEqual(review.summary, "Board.app schema test 3: approve this.")
    XCTAssertNil(try RequestTests.request(RequestTests.control).summary)
  }
}
