import Foundation
import Requests
import SSHSig
import XCTest

/// The inbox and the request screen word each request from its record alone.
/// These tests pin the wording the signed-off designs show for a task, a
/// control and a review, and the order and board counts of the inbox. They do
/// not check how the screens lay the words out.
final class RequestTests: XCTestCase {
  static func request(
    _ fields: String, board: String = "owner/board", asked: TimeInterval = 0,
    prior: String? = nil, current: String? = nil
  ) throws -> Request {
    let json = #"{"$type": "board/effect/v1", "board": "/Users/ana/Code/board", "#
    return Request(
      effect: try Effect(json: Data((json + fields + "}").utf8)), boardName: board,
      asked: Date(timeIntervalSince1970: asked), priorContent: prior.map { Data($0.utf8) },
      current: current)
  }

  static let task = #"""
    "plugin": "tasks", "op": "put", "path": "/tasks/write-the-release-notes.md",
    "prior": "aaaa", "text": "---\n$type: \"tasks/task/v2\"\ntitle: \"Write the release notes\"\n---\n\nBody\n"
    """#
  static let control = #"""
    "plugin": "controls", "op": "put", "path": "/controls/board-app/docs-map-budget",
    "prior": "bbbb", "record": {"$type": "controls/control/v1", "rule": {"max": 450}}
    """#
  static let review =
    #""plugin": "review", "op": "review.post", "path": "/reviews/fix-sync/report""#

  func testATaskIsNamedByItsTitleAndWordedAsAChange() throws {
    let task = try Self.request(Self.task)
    XCTAssertEqual(task.name, "Write the release notes")
    XCTAssertEqual(task.heading, "Change a Task")
    XCTAssertEqual(task.sentence, "tasks wants to change this task")
  }

  func testARecordWithNoTitleIsNamedByItsFileNameInWords() throws {
    let control = try Self.request(Self.control)
    XCTAssertEqual(control.name, "Docs map budget")
    XCTAssertEqual(control.heading, "Change a Control")
    XCTAssertEqual(control.sentence, "controls wants to change this control")
  }

  func testAPlainActionIsNamedByItsPathAndWordedByItsOp() throws {
    let review = try Self.request(Self.review)
    XCTAssertEqual(review.name, "fix-sync report")
    XCTAssertEqual(review.heading, "Post a Review")
    XCTAssertEqual(review.sentence, "review asks to post it")
    XCTAssertFalse(review.isStale)
  }

  func testAPutWithNoPriorAddsAFile() throws {
    let note = try Self.request(
      #""plugin": "notes", "op": "put", "path": "/notes/v1.2-a-b.md", "text": "x""#)
    XCTAssertEqual(note.heading, "Add a File")
    XCTAssertEqual(note.sentence, "notes wants to add this file")
    XCTAssertEqual(note.name, "V1.2 a b")
    XCTAssertFalse(note.isStale)
    XCTAssertTrue(
      try Self.request(#""plugin": "notes", "op": "put", "path": "/n", "text": "x""#, current: "cc")
        .isStale, "a file appeared where the put adds one")
  }

  func testAPutIsStaleOnlyWhenTheBlobThereIsNotTheOneItReplaces() throws {
    XCTAssertFalse(try Self.request(Self.task, prior: "x", current: "AAAA").isStale)
    XCTAssertTrue(try Self.request(Self.task, prior: "x", current: "cccc").isStale)
    XCTAssertTrue(try Self.request(Self.task, prior: "x", current: nil).isStale)
    XCTAssertTrue(try Self.request(Self.task, current: "aaaa").isPriorMissing)
    XCTAssertFalse(try Self.request(Self.task, prior: "x", current: "aaaa").isPriorMissing)
  }

  func testTheInboxListsNewestFirstAndCountsEachBoard() throws {
    let inbox = Inbox([
      try Self.request(Self.task, asked: 1),
      try Self.request(Self.review, board: "owner/board-src", asked: 3),
      try Self.request(Self.control, asked: 2),
    ])
    XCTAssertEqual(inbox.requests.map(\.plugin), ["review", "controls", "tasks"])
    XCTAssertEqual(inbox.boards.map(\.name), ["owner/board", "owner/board-src"])
    XCTAssertEqual(inbox.boards.map(\.count), [2, 1])
    XCTAssertEqual(inbox.requests(in: "owner/board-src").map(\.plugin), ["review"])
    XCTAssertEqual(inbox.requests(in: nil).count, 3)
  }

  func testARowSaysTheTimeTodayYesterdayOrTheDate() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_GB")
    let now = Date(timeIntervalSince1970: 1_793_300_000)  // 29 Oct 2026, 18:53 UTC
    XCTAssertEqual(askedLabel(now.addingTimeInterval(-60), now: now, calendar: calendar), "18:52")
    XCTAssertEqual(
      askedLabel(now.addingTimeInterval(-86_400), now: now, calendar: calendar), "Yesterday")
    XCTAssertEqual(
      askedLabel(now.addingTimeInterval(-5 * 86_400), now: now, calendar: calendar), "24 Oct 2026")
  }

  func testARemovalIsWordedFromTheRecordItRemoves() throws {
    let removal = try Self.request(
      #""plugin": "tasks", "op": "rm", "path": "/tasks/a.md""#,
      prior: "---\n$type: \"tasks/task/v2\"\ntitle: \"Old task\"\n---\n")
    XCTAssertEqual(removal.heading, "Remove a Task")
    XCTAssertEqual(removal.sentence, "tasks wants to remove this task")
    XCTAssertEqual(removal.name, "Old task")
  }

  func testAnActionOfAPluralPluginIsHeadedByOneThing() throws {
    let close = try Self.request(#""plugin": "tasks", "op": "tasks.close", "path": "/tasks/a""#)
    XCTAssertEqual(close.heading, "Close a Task")
    XCTAssertEqual(close.sentence, "tasks asks to close it")
  }

  func testRequestsAskedTogetherKeepOneOrder() throws {
    let a = try Self.request(Self.task, asked: 5)
    let b = try Self.request(Self.control, asked: 5)
    XCTAssertEqual(Inbox([a, b]).requests.map(\.id), Inbox([b, a]).requests.map(\.id))
  }

  func testARemovalIsStaleWhenTheFileChangedAfterItWasAsked() throws {
    let rm = #""plugin": "tasks", "op": "rm", "path": "/tasks/a.md", "prior": "aaaa""#
    XCTAssertFalse(try Self.request(rm, current: "aaaa").isStale)
    XCTAssertTrue(try Self.request(rm, current: "bbbb").isStale)
  }
}
