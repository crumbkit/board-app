import Requests
import XCTest

/// A zone's copy, read from a fake change feed. The feed's tokens are
/// integers, and each read records the token it was asked for.
final class ZoneCopyTests: XCTestCase {
  typealias Copy = ZoneCopy<String, Int>

  struct Expired: Error {}
  struct Offline: Error {}

  /// Batches served in order, each answering the token it expects. A batch
  /// may instead be an error to throw.
  actor Feed {
    var batches: [Int?: Result<Copy.Batch, Error>] = [:]
    private(set) var asked: [Int?] = []

    func serve(_ token: Int?, _ batch: Copy.Batch) { batches[token] = .success(batch) }
    func fail(_ token: Int?, _ error: Error) { batches[token] = .failure(error) }

    func changes(since token: Int?) throws -> Copy.Batch {
      asked.append(token)
      guard let batch = batches[token] else {
        return Copy.Batch(modified: [:], deleted: [], token: token ?? 0, moreComing: false)
      }
      return try batch.get()
    }
  }

  private func read(_ copy: inout Copy, _ feed: Feed) async throws {
    try await copy.read(
      changes: { try await feed.changes(since: $0) }, isExpired: { $0 is Expired })
  }

  func testTheFirstReadWalksEveryBatchFromNoToken() async throws {
    let feed = Feed()
    await feed.serve(nil, .init(modified: ["a": "A"], deleted: [], token: 1, moreComing: true))
    await feed.serve(1, .init(modified: ["b": "B"], deleted: [], token: 2, moreComing: false))
    var copy = Copy()
    try await read(&copy, feed)
    XCTAssertEqual(copy.records, ["a": "A", "b": "B"])
    XCTAssertEqual(copy.token, 2)
    let asked = await feed.asked
    XCTAssertEqual(asked, [nil, 1])
  }

  func testALaterReadStartsFromTheLastTokenAndMergesOnlyNewChanges() async throws {
    let feed = Feed()
    await feed.serve(
      nil, .init(modified: ["a": "A", "b": "B"], deleted: [], token: 1, moreComing: false))
    var copy = Copy()
    try await read(&copy, feed)
    await feed.serve(
      1, .init(modified: ["b": "B2", "c": "C"], deleted: [], token: 2, moreComing: false))
    try await read(&copy, feed)
    XCTAssertEqual(copy.records, ["a": "A", "b": "B2", "c": "C"])
    XCTAssertEqual(copy.token, 2)
    let asked = await feed.asked
    XCTAssertEqual(asked, [nil, 1])
  }

  func testADeletionRemovesTheRecord() async throws {
    let feed = Feed()
    await feed.serve(
      nil, .init(modified: ["a": "A", "b": "B"], deleted: [], token: 1, moreComing: false))
    await feed.serve(1, .init(modified: [:], deleted: ["a"], token: 2, moreComing: false))
    var copy = Copy()
    try await read(&copy, feed)
    try await read(&copy, feed)
    XCTAssertEqual(copy.records, ["b": "B"])
  }

  func testAnExpiredTokenEmptiesTheCopyAndReadsAgainFromNoToken() async throws {
    let feed = Feed()
    await feed.serve(
      nil, .init(modified: ["a": "A", "b": "B"], deleted: [], token: 1, moreComing: false))
    var copy = Copy()
    try await read(&copy, feed)
    await feed.fail(1, Expired())
    await feed.serve(nil, .init(modified: ["c": "C"], deleted: [], token: 5, moreComing: false))
    try await read(&copy, feed)
    XCTAssertEqual(copy.records, ["c": "C"])
    XCTAssertEqual(copy.token, 5)
    let asked = await feed.asked
    XCTAssertEqual(asked, [nil, 1, nil])
  }

  func testAnExpiredTokenFromScratchIsThrownAfterOneMoreTry() async throws {
    let feed = Feed()
    await feed.fail(nil, Expired())
    var copy = Copy()
    do {
      try await read(&copy, feed)
      XCTFail("the read should throw")
    } catch is Expired {}
    let asked = await feed.asked
    XCTAssertEqual(asked, [nil, nil])
  }

  func testAFailureMidReadKeepsTheAppliedBatchesAndTheNextReadResumes() async throws {
    let feed = Feed()
    await feed.serve(nil, .init(modified: ["a": "A"], deleted: [], token: 1, moreComing: true))
    await feed.fail(1, Offline())
    var copy = Copy()
    do {
      try await read(&copy, feed)
      XCTFail("the read should throw")
    } catch is Offline {}
    XCTAssertEqual(copy.records, ["a": "A"])
    XCTAssertEqual(copy.token, 1)
    await feed.serve(1, .init(modified: ["b": "B"], deleted: [], token: 2, moreComing: false))
    try await read(&copy, feed)
    XCTAssertEqual(copy.records, ["a": "A", "b": "B"])
    let asked = await feed.asked
    XCTAssertEqual(asked, [nil, 1, 1])
  }
}
