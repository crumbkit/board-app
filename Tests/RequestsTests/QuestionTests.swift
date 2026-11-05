import Foundation
import Requests
import SSHSig
import XCTest

/// Questions from agents, as the phone lists and answers them. The fixtures
/// are real `plans.open` output for questions under `/projects/` in the
/// personal board. These tests do not run Board, CloudKit or the screens.
final class QuestionTests: XCTestCase {
  static let merge = "/projects/board/questions/20261025T1248Z-5f31"
  static let review = "/projects/board/questions/20261024T1830Z-1213"
  static let listings = "/projects/crumbkit-go/questions/20261024T1830Z-d653"

  func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/questions"))
    return try Data(contentsOf: url)
  }

  func questions(_ name: String = "open.json") throws -> [Question] {
    try Question.open(report: fixture(name))
  }

  func question(_ path: String) throws -> Question {
    try XCTUnwrap(questions().first { $0.path == path })
  }

  // MARK: Reading plans.open

  /// Proves every field `plans.open` prints is read, including the four a
  /// Board with `plans.answer` adds.
  func testPlansOpenIsReadWithEveryField() throws {
    let all = try questions()
    XCTAssertEqual(all.count, 4)
    let merge = try question(Self.merge)
    XCTAssertTrue(merge.question.hasPrefix("May crumbkit/board#294"))
    XCTAssertEqual(merge.asked, "2026-10-25T12:48:00Z")
    XCTAssertEqual(merge.askedDate, Date(timeIntervalSince1970: 1_792_932_480))
    XCTAssertEqual(merge.session, "local_31dd8fcd-6180-489e-80e9-e63391b9ac05")
    XCTAssertEqual(merge.options.map(\.id), ["merge", "hold"])
    XCTAssertEqual(merge.options[1].text, "Hold them; I want to look first")
    XCTAssertEqual(merge.recommendation, "merge")
    XCTAssertEqual(merge.blocks?.hasPrefix("Tasks v2 PRs 3 to 5"), true)
    XCTAssertEqual(merge.why?.hasPrefix("Two clean-context Opus reviews"), true)
    XCTAssertNil(merge.note)
    XCTAssertEqual(merge.mount, "/repos/board")
    XCTAssertNil(merge.contextPath)
    let review = try question(Self.review)
    XCTAssertEqual(review.note?.hasPrefix("The design is at"), true)
    XCTAssertNil(review.blocks)
    XCTAssertNil(review.mount)
  }

  /// Proves a Board without `plans.answer`, whose `plans.open` lacks the four
  /// new fields, still gives every question, with those fields absent.
  func testPlansOpenWithoutTheNewFieldsReadsThemAsAbsent() throws {
    let all = try questions("open-before-answer.json")
    XCTAssertEqual(all.count, 4)
    for question in all {
      XCTAssertNil(question.why)
      XCTAssertNil(question.note)
      XCTAssertNil(question.mount)
      XCTAssertNil(question.contextPath)
    }
  }

  func testAReportThatIsNotPlansOpenIsRefused() throws {
    XCTAssertThrowsError(try Question.open(report: Data(#"{"schema":"other"}"#.utf8)))
    XCTAssertThrowsError(try Question.open(report: fixture("refused.json")))
  }

  /// A question with no path or no text is left out; the others stay.
  func testAQuestionWithoutAPathIsLeftOut() throws {
    let report = #"""
      {"schema":"board/call-report/v2","data":{"capability":"open","plugin":"plans","output":
      {"questions":[{"question":"No path"},{"path":"/projects/board/questions/x","question":"Kept",
      "options":[{"id":"a","text":"A"},{"text":"no id"}]}],"total":2,"truncated":false,"unreadable":0}}}
      """#
    let all = try Question.open(report: Data(report.utf8))
    XCTAssertEqual(all.map(\.question), ["Kept"])
    XCTAssertEqual(all[0].options.map(\.id), ["a"])
  }

  // MARK: Naming

  /// The record name is a hash of the path, so a path of any length or
  /// character makes a valid CloudKit name, and the same path the same name.
  func testTheRecordIsNamedByAHashOfItsPath() throws {
    let merge = try question(Self.merge)
    XCTAssertEqual(merge.id, gitBlobID(Data(Self.merge.utf8)))
    XCTAssertEqual(merge.id.count, 40)
    XCTAssertNotEqual(merge.id, try question(Self.review).id)
  }

  /// The Mac shares a question as a record of its fields, and the phone reads
  /// the same question back. A record named for another path is not read.
  func testAQuestionTravelsAsARecordOfItsFields() throws {
    for path in [Self.merge, Self.review, Self.listings] {
      var question = try question(path)
      question.boardName = "crumbkit/board"
      XCTAssertEqual(Question(name: question.id, fields: question.fields), question)
      XCTAssertNil(Question(name: Question.recordName("/other"), fields: question.fields))
    }
    XCTAssertNil(try question(Self.review).fields["blocks"])
  }

  // MARK: The inbox row

  func testTheRowNamesTheRecommendedOptionsText() throws {
    XCTAssertEqual(
      try question(Self.review).recommendationLine,
      "Recommended: review.run also writes a runs/run/v1 in the author's board, one suite per repository and kind, with tokens and cost as measures."
    )
    XCTAssertEqual(try question(Self.listings).recommendationLine, "No recommendation")
  }

  func testTheRowSaysAnAnswerIsOnItsWayWhileItIsSending() throws {
    let review = try question(Self.review)
    XCTAssertEqual(review.rowLine(sending: true), "Sending your answer…")
    XCTAssertEqual(review.rowLine(sending: false), review.recommendationLine)
  }

  /// A recommendation that names no option is not shown as one.
  func testARecommendationThatNamesNoOptionIsNone() throws {
    let report = #"""
      {"schema":"board/call-report/v2","data":{"output":{"questions":[{"path":"/p/questions/x",
      "question":"Q","options":[{"id":"a","text":"A"}],"recommendation":"z"}]}}}
      """#
    let question = try XCTUnwrap(Question.open(report: Data(report.utf8)).first)
    XCTAssertNil(question.recommended)
    XCTAssertEqual(question.recommendationLine, "No recommendation")
  }

  // MARK: The inbox

  /// Questions are newest first, by path when two were asked together, and the board counts and the total count
  /// both kinds.
  func testTheInboxListsQuestionsNewestFirstAndCountsBothKinds() throws {
    var all = try questions()
    for index in all.indices {
      all[index].boardName = all[index].mount == nil ? "owner/board" : "crumbkit/board"
    }
    let request = try RequestTests.request(RequestTests.review, board: "crumbkit/board")
    let inbox = Inbox([request], questions: all)
    XCTAssertEqual(
      inbox.questions.map(\.path),
      [
        "/projects/board/questions/20261025T1443Z-9c62", Self.merge, Self.review, Self.listings,
      ])
    XCTAssertEqual(inbox.count(in: nil), 5)
    XCTAssertEqual(inbox.count(in: "crumbkit/board"), 3)
    XCTAssertEqual(inbox.questions(in: "owner/board").count, 2)
    XCTAssertEqual(inbox.boards.map(\.name), ["crumbkit/board", "owner/board"])
    XCTAssertEqual(inbox.boards.map(\.count), [3, 2])
    XCTAssertTrue(Inbox([]).questions.isEmpty)
  }

  // MARK: Answering

  func testAnswerIsOffUntilAnOptionIsChosen() throws {
    let review = try question(Self.review)
    XCTAssertFalse(review.canAnswer(nil, note: "words"))
    XCTAssertTrue(review.canAnswer(.option("b"), note: ""))
    XCTAssertFalse(review.canAnswer(.option("z"), note: ""))
  }

  func testSomethingElseNeedsWordsInTheNote() throws {
    let review = try question(Self.review)
    XCTAssertFalse(review.canAnswer(.other, note: ""))
    XCTAssertFalse(review.canAnswer(.other, note: "  \n "))
    XCTAssertTrue(review.canAnswer(.other, note: "Neither; ask me tomorrow."))
  }

  func testAnAnswerTravelsAsARecordNamedForItsQuestion() throws {
    let review = try question(Self.review)
    let answer = try XCTUnwrap(QuestionAnswer(question: review, choice: .option("b"), note: " "))
    XCTAssertEqual(answer.name, "qanswer-" + review.id)
    XCTAssertEqual(answer.fields, ["path": Self.review, "option": "b", "note": ""])
    XCTAssertEqual(QuestionAnswer(name: answer.name, fields: answer.fields), answer)
    XCTAssertNil(QuestionAnswer(name: "qanswer-other", fields: answer.fields))
    XCTAssertNil(QuestionAnswer(question: review, choice: nil, note: "x"))
    XCTAssertNil(QuestionAnswer(question: review, choice: .other, note: ""))
  }

  func testSomethingElseIsOptionNone() throws {
    let review = try question(Self.review)
    let answer = try XCTUnwrap(
      QuestionAnswer(question: review, choice: .other, note: " Ask me tomorrow. "))
    XCTAssertEqual(answer.option, "none")
    XCTAssertEqual(answer.note, "Ask me tomorrow.")
  }

  /// The Mac passes the answer to Board as arguments, with the note as words
  /// only when it has some.
  func testTheMacAnswersThroughPlansAnswer() throws {
    let review = try question(Self.review)
    let bare = try XCTUnwrap(QuestionAnswer(question: review, choice: .option("b"), note: ""))
    XCTAssertEqual(
      bare.arguments,
      [
        "--personal", "call", "plans.answer", "--path", Self.review, "--option", "b",
        "--written_by", "board-app/phone", "--json",
      ])
    let noted = try XCTUnwrap(
      QuestionAnswer(question: review, choice: .option("b"), note: "--and add cost"))
    XCTAssertEqual(
      noted.arguments,
      [
        "--personal", "call", "plans.answer", "--path", Self.review, "--option", "b",
        "--written_by", "board-app/phone", "--words", "--and add cost", "--json",
      ])
  }

  // MARK: Refusals

  func testBoardsFailureIsRead() throws {
    let failure = try BoardFailure(json: fixture("refused.json"))
    XCTAssertEqual(failure.code, "plans::answer::already_answered")
    XCTAssertTrue(failure.message.hasSuffix("so nothing was recorded"))
    XCTAssertThrowsError(try BoardFailure(json: Data("Error: not JSON".utf8)))
    XCTAssertThrowsError(try BoardFailure(json: fixture("open.json")))
  }

  func testOnlyPlansAnswersOwnRefusalsAreFinal() throws {
    let refused = try BoardFailure(json: fixture("refused.json"))
    XCTAssertTrue(refused.isFinal)
    let locked = try BoardFailure(
      json: Data(
        #"{"schema":"board/failure/v1","code":"plans::board::refused","message":"`board put --batch` refused with board::put::locked"}"#
          .utf8))
    XCTAssertFalse(locked.isFinal)
  }

  func testARefusalTravelsBackAsARecordNamedForItsQuestion() throws {
    let review = try question(Self.review)
    let answer = try XCTUnwrap(QuestionAnswer(question: review, choice: .option("b"), note: ""))
    let refused = QuestionRefused(
      answer: answer, failure: try BoardFailure(json: fixture("refused.json")))
    XCTAssertEqual(refused.name, "qrefused-" + review.id)
    XCTAssertEqual(refused.fields["code"], "plans::answer::already_answered")
    XCTAssertEqual(QuestionRefused(name: refused.name, fields: refused.fields), refused)
    XCTAssertNil(QuestionRefused(name: "qrefused-x", fields: ["code": "c"]))
  }

  func testAnAnswerFromElsewhereFirstIsWordedAsAlreadyAnswered() throws {
    let refused = QuestionRefused(
      question: "q", code: "plans::answer::already_answered", message: "Board's words")
    XCTAssertEqual(refused.title, "Already Answered")
    XCTAssertEqual(
      refused.text,
      "This question was answered from another place before your answer reached Board, so Board kept the first answer. Yours was not recorded."
    )
    let other = QuestionRefused(question: "q", code: "plans::answer::not_open", message: "Closed.")
    XCTAssertEqual(other.title, "Board Did Not Record Your Answer")
    XCTAssertEqual(other.text, "Closed.")
  }

  // MARK: Board names

  /// A question in a mounted board is named by that mount's repository. The
  /// Mac reads the mount's record, whose file is the mount path with `.json`.
  func testAMountIsReadFromItsRecord() throws {
    XCTAssertEqual(Mount.file("/repos/board"), "repos/board.json")
    XCTAssertNil(Mount.file("/repos/../secret"))
    XCTAssertNil(Mount.file("repos/board"))
    let record = #"""
      {"$type": "board/mount/v1", "commit": "e82f8da9", "follow": "origin/main",
       "repo": "/Users/ana/Code/crumbverse/board"}
      """#
    XCTAssertEqual(Mount.repository(Data(record.utf8)), "/Users/ana/Code/crumbverse/board")
    XCTAssertNil(Mount.repository(Data(#"{"$type": "board/mount/v1", "path": "/x"}"#.utf8)))
    XCTAssertEqual(Mount.fallbackName("/repos/board"), "board")
  }
}
