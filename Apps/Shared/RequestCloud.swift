// Pending effects and their answers in the owner's private iCloud database,
// zone `Requests` (docs/sync.md). The Mac shares what waits in the personal
// board; the phone reads it and writes answers; the Mac hands each answer to
// `board answer` and removes both records.
import CloudKit
import Foundation
import Requests
import SSHSig

/// A pending effect as the Mac shares it, with what the phone needs to show it.
struct SharedRequest: Sendable {
  /// The `board/effect/v1` record's bytes, from which the phone builds what it
  /// shows and what it signs.
  let effect: Data
  /// The board's git remote, such as `owner/board`.
  let boardName: String
  /// When the pending effect was committed.
  let asked: Date
  /// The bytes of the blob a put replaces, when the Mac could read it.
  let prior: Data?
  /// The blob at the effect's path now, or nil when there is no file there.
  let current: String?

  /// The effect, or nil when the bytes are not one. A request whose effect
  /// does not hash to its record's name is never shown.
  var parsed: Effect? { try? Effect(json: effect) }

  /// The prior blob, only when git would give it the id the effect names, so
  /// the zone cannot show the owner some other old version.
  var verifiedPrior: Data? {
    guard let prior, let named = parsed?.prior?.lowercased(), named.count >= 7,
      gitBlobID(prior).hasPrefix(named)
    else { return nil }
    return prior
  }

  /// The request as the screens show it, or nil when the effect does not parse.
  var request: Request? {
    parsed.map {
      Request(
        effect: $0, boardName: boardName, asked: asked, priorContent: verifiedPrior,
        current: current)
    }
  }
}

/// The owner's answer to one request. An approval carries the armored SSH
/// signature of the effect's statement; a refusal carries none.
struct RequestAnswer: Sendable, Equatable {
  let id: String
  let approve: Bool
  let reason: String?
  let signature: String?
}

struct RequestCloud: Sendable {
  private let database = CKContainer(identifier: "iCloud.com.stemmacorp.board")
    .privateCloudDatabase
  private let zone = CKRecordZone.ID(zoneName: "Requests")
  /// The record the Mac rewrites each time it shares, so the phone can say how
  /// old its list is.
  private let sharedName = "mac"

  func prepare() async throws {
    _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zone)], deleting: [])
  }

  /// Every record in the zone, by name, reading every batch.
  private func all() async throws -> [String: CKRecord] {
    var records: [String: CKRecord] = [:]
    var token: CKServerChangeToken?
    while true {
      let changes = try await database.recordZoneChanges(inZoneWith: zone, since: token)
      for result in changes.modificationResultsByID.values {
        if let record = try? result.get().record { records[record.recordID.recordName] = record }
      }
      for deletion in changes.deletions { records[deletion.recordID.recordName] = nil }
      guard changes.moreComing else { return records }
      token = changes.changeToken
    }
  }

  /// Saves and deletes each record on its own, so one record CloudKit refuses
  /// does not hold back the others, then throws the first refusal.
  private func modify(saving: [CKRecord], deleting: [CKRecord.ID]) async throws {
    let results = try await database.modifyRecords(
      saving: saving, deleting: deleting, savePolicy: .allKeys, atomically: false)
    for result in results.saveResults.values { _ = try result.get() }
    for result in results.deleteResults.values {
      do { try result.get() } catch let error as CKError where error.code == .unknownItem {}
    }
  }

  /// Makes the zone hold exactly `requests`, by effect id, and stamps the time.
  /// A request whose current blob is unchanged is not saved again. The effect
  /// and prior blob travel as assets, since a record holds at most 1 MB.
  func share(_ requests: [String: SharedRequest], now: Date = Date()) async throws {
    let existing = try await all()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    func asset(_ data: Data?, _ name: String) throws -> CKAsset? {
      guard let data else { return nil }
      let file = folder.appendingPathComponent(name)
      try data.write(to: file)
      return CKAsset(fileURL: file)
    }
    var saving: [CKRecord] = []
    for (id, request) in requests {
      if let record = existing[id], record["current"] as? String == request.current { continue }
      let record = CKRecord(recordType: "Request", recordID: name(id))
      record["effect"] = try asset(request.effect, id + ".effect")
      record["board"] = request.boardName
      record["asked"] = request.asked
      record["prior"] = try asset(request.prior, id + ".prior")
      record["current"] = request.current
      saving.append(record)
    }
    let shared = CKRecord(recordType: "Shared", recordID: name(sharedName))
    shared["at"] = now
    saving.append(shared)
    let stale = existing.values.filter { $0.recordType == "Request" }
      .map(\.recordID).filter { requests[$0.recordName] == nil }
    try await modify(saving: saving, deleting: stale)
  }

  /// Every answer the phone wrote, whether or not its request is still shared.
  func answers() async throws -> [RequestAnswer] {
    try await all().values.compactMap { record in
      guard record.recordType == "Answer", let id = record["effect"] as? String,
        record.recordID.recordName == "answer-" + id,
        let answer = record["answer"] as? String, answer == "approve" || answer == "refuse"
      else { return nil }
      return RequestAnswer(
        id: id, approve: answer == "approve", reason: record["reason"] as? String,
        signature: record["signature"] as? String)
    }
  }

  /// Removes a request and its answer once Board has the answer, or the
  /// answer alone when Board refused it or its request is gone, so an old
  /// answer is never delivered to a later request with the same id.
  func finish(_ id: String, answered: Bool) async throws {
    let ids = answered ? [name(id), name("answer-" + id)] : [name("answer-" + id)]
    try await modify(saving: [], deleting: ids)
  }

  /// The requests the Mac shared, by effect id, and when it last shared.
  /// Each request is checked against its record's name, so a record cannot
  /// show one effect and be answered as another.
  func requests() async throws -> (requests: [String: SharedRequest], shared: Date?) {
    let records = try await all()
    var requests: [String: SharedRequest] = [:]
    func read(_ value: Any?) -> Data? {
      (value as? CKAsset)?.fileURL.flatMap { try? Data(contentsOf: $0) }
    }
    for record in records.values where record.recordType == "Request" {
      guard let effect = read(record["effect"]), let board = record["board"] as? String,
        let asked = record["asked"] as? Date
      else { continue }
      let request = SharedRequest(
        effect: effect, boardName: board, asked: asked, prior: read(record["prior"]),
        current: record["current"] as? String)
      guard let parsed = request.parsed, parsed.id == record.recordID.recordName else { continue }
      requests[parsed.id] = request
    }
    return (requests, records[sharedName]?["at"] as? Date)
  }

  func answer(_ answer: RequestAnswer) async throws {
    let record = CKRecord(recordType: "Answer", recordID: name("answer-" + answer.id))
    record["effect"] = answer.id
    record["answer"] = answer.approve ? "approve" : "refuse"
    record["reason"] = answer.reason
    record["signature"] = answer.signature
    try await modify(saving: [record], deleting: [])
  }

  private func name(_ name: String) -> CKRecord.ID {
    CKRecord.ID(recordName: name, zoneID: zone)
  }
}
