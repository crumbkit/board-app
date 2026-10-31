import Foundation
import Requests
import SSHSig
import XCTest

/// The request screen's thread: which versions it shows in which order, which
/// one is latest and approvable, where replies fall, and how a reply travels
/// from the phone to the Mac. The fixture is real `requests.thread` output.
/// These tests do not run Board, CloudKit or the screens.
final class ThreadTests: XCTestCase {
  static let latestID = "c35d89f0221216a257c5f866a581c5f03b0e8595835f5976f7323c3f636897b2"
  static let replacedID = "049eb3272814da0f1d406118988aa42eaf3da16161647d544d4bbad03ff1a1bf"
  static let refusedID = "ea84b7cdce63e1cdf6ebb237297a9f3559bdd24546e10a608f92fe238dbaf125"

  func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/thread"))
    return try Data(contentsOf: url)
  }

  func request(_ name: String) throws -> Request {
    Request(
      effect: try Effect(json: fixture(name)), boardName: "owner/board",
      asked: Date(timeIntervalSince1970: 0), priorContent: nil, current: nil)
  }

  func thread(for name: String = "latest.effect.json") throws -> RequestThread {
    try RequestThread(report: fixture("thread.json"), request: request(name))
  }

  /// Proves the fixture's effects hash to the ids Board gave them, so the
  /// other tests compare real ids. It does not prove anything about threads.
  func testTheFixtureEffectsHashToBoardsIDs() throws {
    XCTAssertEqual(try request("latest.effect.json").id, Self.latestID)
    XCTAssertEqual(try request("replaced.effect.json").id, Self.replacedID)
  }

  /// Proves Board's report maps to numbered versions in Board's order, with
  /// times, answers and each version's own content. It does not prove Board
  /// orders them; Board's own tests do.
  func testTheReportMapsToNumberedVersionsOldestFirst() throws {
    let thread = try thread()
    XCTAssertEqual(thread.versions.map(\.id), [Self.refusedID, Self.replacedID, Self.latestID])
    XCTAssertEqual(thread.versions.map(\.number), [1, 2, 3])
    XCTAssertEqual(
      thread.versions.first?.answer, RequestThread.Answer(approved: false, reason: "Not Friday"))
    XCTAssertNil(thread.versions.last?.answer)
    XCTAssertEqual(
      thread.versions.first?.asked, ISO8601DateFormatter().date(from: "2026-10-30T18:40:02Z"))
    XCTAssertTrue(thread.versions[0].request.effect.text?.contains("2026-10-30") == true)
    XCTAssertTrue(thread.versions[1].request.effect.text?.contains("2026-11-02") == true)
  }

  /// Proves the latest version is the shared request itself, byte for byte,
  /// so Approve signs what the Mac read. It does not check the signature.
  func testTheLatestVersionIsTheRequestThePhoneSigns() throws {
    let request = try request("latest.effect.json")
    let thread = try RequestThread(report: fixture("thread.json"), request: request)
    XCTAssertEqual(thread.latest?.id, Self.latestID)
    XCTAssertEqual(thread.latest?.request.effect, request.effect)
    XCTAssertEqual(thread.versions.filter(\.isLatest).count, 1)
  }

  /// Proves each older version names the version that replaced it, and the
  /// latest names none.
  func testOlderVersionsAreReplacedByTheNextVersion() throws {
    XCTAssertEqual(try thread().versions.map(\.replacedBy), [2, 3, nil])
  }

  /// Proves only the latest version can be approved: the latest is admitted
  /// and its replaced twin, from the same report, is refused.
  func testOnlyTheLatestVersionIsApprovable() throws {
    XCTAssertTrue(try thread().isApprovable(request("latest.effect.json")))
    let fromReplaced = try thread(for: "replaced.effect.json")
    XCTAssertFalse(fromReplaced.isApprovable(try request("replaced.effect.json")))
    XCTAssertEqual(fromReplaced.latest?.id, Self.latestID)
  }

  /// Proves a report about another path is refused with the field named, and
  /// the same report with the request's own path is admitted.
  func testAReportForAnotherPathIsRefused() throws {
    let report = String(decoding: try fixture("thread.json"), as: UTF8.self)
    let moved = report.replacingOccurrences(
      of: #""path":"/tasks/write-the-release-notes.md""#, with: #""path":"/tasks/other.md""#)
    XCTAssertNotEqual(moved, report)
    XCTAssertThrowsError(
      try RequestThread(report: Data(moved.utf8), request: request("latest.effect.json"))
    ) { XCTAssertEqual($0 as? RequestThread.Mismatch, RequestThread.Mismatch(field: "path")) }
    XCTAssertNoThrow(
      try RequestThread(report: Data(report.utf8), request: request("latest.effect.json")))
  }

  /// Proves a report that lacks the request's own version is refused, and the
  /// same report with it is admitted.
  func testAReportWithoutTheRequestsVersionIsRefused() throws {
    let report = String(decoding: try fixture("thread.json"), as: UTF8.self)
    let other = report.replacingOccurrences(
      of: Self.latestID, with: String(repeating: "0", count: 64))
    XCTAssertThrowsError(
      try RequestThread(report: Data(other.utf8), request: request("latest.effect.json"))
    ) { XCTAssertEqual($0 as? RequestThread.Mismatch, RequestThread.Mismatch(field: "versions")) }
    XCTAssertNoThrow(
      try RequestThread(report: Data(report.utf8), request: request("latest.effect.json")))
  }

  /// Proves replies fall between versions by time: each reply after the
  /// version it answers and before the version that followed.
  func testRepliesFallBetweenVersionsByTime() throws {
    let order = try thread().items.map { item -> String in
      switch item {
      case .version(let version): "v\(version.number)"
      case .reply(let reply): "reply \(reply.text)"
      }
    }
    XCTAssertEqual(
      order,
      [
        "v1", "reply Not Friday. Next week.", "v2",
        "reply Monday's full. Defer it to Tuesday instead.", "v3",
      ])
  }

  /// Proves a request the Mac shared without a thread is a thread of one,
  /// latest and approvable.
  func testARequestWithoutAThreadIsItsOwnLatestVersion() throws {
    let request = try request("latest.effect.json")
    let thread = RequestThread(request: request)
    XCTAssertEqual(thread.versions.map(\.id), [request.id])
    XCTAssertTrue(thread.isApprovable(request))
  }

  /// Proves the inbox drops a replaced version while its latest version waits
  /// too, and keeps it when the latest is not among the shared requests.
  func testTheInboxShowsAThreadOnceByItsLatestVersion() throws {
    let latest = try request("latest.effect.json")
    let replaced = try request("replaced.effect.json")
    let threads = [
      latest.id: try thread(),
      replaced.id: try thread(for: "replaced.effect.json"),
    ]
    XCTAssertEqual(
      RequestThread.latestOnly([latest, replaced], threads: threads).map(\.id), [latest.id])
    XCTAssertEqual(RequestThread.latestOnly([replaced], threads: threads).map(\.id), [replaced.id])
  }

  /// Proves a thread whose latest version names a waiting request for another
  /// path does not hide the version from the inbox. Its twin above, with the
  /// same path, does.
  func testTheInboxKeepsAVersionWhoseLatestIsForAnotherPath() throws {
    let latest = try JSONValue.parse(fixture("latest.effect.json"))
    guard case .object(let members) = latest else { return XCTFail("not an object") }
    let moved = JSONValue.object(
      members.map { $0.key == "path" ? ("path", .string("/tasks/other.md")) : $0 })
    let other = Request(
      effect: try Effect(json: Data(moved.pretty.utf8)), boardName: "owner/board",
      asked: Date(timeIntervalSince1970: 0), priorContent: nil, current: nil)
    let replaced = try request("replaced.effect.json")
    let report = String(decoding: try fixture("thread.json"), as: UTF8.self)
      .replacingOccurrences(of: Self.latestID, with: other.id)
    let thread = try RequestThread(report: Data(report.utf8), request: replaced)
    XCTAssertEqual(thread.latest?.id, other.id)
    XCTAssertEqual(
      RequestThread.latestOnly([other, replaced], threads: [replaced.id: thread]).map(\.id),
      [other.id, replaced.id])
  }

  // MARK: Replies

  static let sent = Date(timeIntervalSince1970: 1_793_041_200.75)

  /// Proves a reply survives the relay's encoding: the phone's zone fields
  /// read back as the same reply on the Mac, which puts a `requests/reply/v1`
  /// record at the path Board's thread reads. It does not run CloudKit or
  /// `board put`.
  func testAReplyRoundTripsThroughTheZoneToTheBoardRecord() throws {
    let phone = try XCTUnwrap(
      PhoneReply(effect: Self.latestID, text: "  Tuesday works.\n", sent: Self.sent))
    let mac = try XCTUnwrap(PhoneReply(name: phone.name, fields: phone.fields))
    XCTAssertEqual(mac, phone)
    XCTAssertEqual(mac.text, "Tuesday works.")
    XCTAssertEqual(mac.stamp, "20261026T190000Z")
    XCTAssertEqual(mac.path, "/requests/replies/\(Self.latestID)/20261026T190000Z")
    let record = try JSONValue.parse(mac.record)
    XCTAssertEqual(record["$type"], .string("requests/reply/v1"))
    XCTAssertEqual(record["effect"], .string(Self.latestID))
    XCTAssertEqual(record["text"], .string("Tuesday works."))
    if case .object(let members) = record {
      XCTAssertEqual(members.count, 3)
    } else {
      XCTFail("the record is not an object")
    }
  }

  /// Proves a zone record whose name does not match its fields is refused,
  /// and its twin with the right name is admitted.
  func testAZoneReplyNamedForAnotherReplyIsRefused() throws {
    let phone = try XCTUnwrap(PhoneReply(effect: Self.latestID, text: "Yes", sent: Self.sent))
    let renamed = "reply-\(Self.replacedID)-\(phone.stamp)"
    XCTAssertNil(PhoneReply(name: renamed, fields: phone.fields))
    XCTAssertNotNil(PhoneReply(name: phone.name, fields: phone.fields))
  }

  /// Proves a blank reply and one to a malformed id are refused, each beside
  /// an admitted twin.
  func testABlankReplyOrAMalformedIDIsRefused() {
    XCTAssertNil(PhoneReply(effect: Self.latestID, text: " \n ", sent: Self.sent))
    XCTAssertNotNil(PhoneReply(effect: Self.latestID, text: "a", sent: Self.sent))
    XCTAssertNil(PhoneReply(effect: Self.latestID.uppercased(), text: "a", sent: Self.sent))
    XCTAssertNotNil(PhoneReply(effect: Self.latestID.lowercased(), text: "a", sent: Self.sent))
  }

  /// Proves a reply sent from the phone shows in the thread until Board holds
  /// it, and shows once after. It does not prove the Mac wrote it.
  func testASentReplyShowsOnceWhetherOrNotBoardHoldsIt() throws {
    let thread = try thread()
    let sent = try XCTUnwrap(
      PhoneReply(
        effect: Self.replacedID, text: "Monday's full. Defer it to Tuesday instead.",
        sent: ISO8601DateFormatter().date(from: "2026-10-30T18:55:00Z")!))
    XCTAssertEqual(thread.adding([sent]).replies.count, thread.replies.count)
    let later = try XCTUnwrap(PhoneReply(effect: Self.latestID, text: "Thanks", sent: Self.sent))
    XCTAssertEqual(thread.adding([later]).replies.last?.text, "Thanks")
    XCTAssertEqual(thread.adding([later]).replies.count, thread.replies.count + 1)
  }
}
