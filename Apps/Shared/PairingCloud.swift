// Pairing records in the owner's private iCloud database, so the phone and the
// Mac find each other without a server or the same network. The exchange is
// commit, challenge, reveal, grant (docs/devices.md).
import CloudKit
import Foundation
import Pairing

/// A phone's request to pair. It holds only a commitment until the phone has
/// seen the Mac's challenge; then it also holds the revealed key and nonce, and
/// the key's signature of the pairing (`PairingProof`).
struct PairingRequest: Sendable {
  let id: String
  let name: String
  let commitment: Data
  let created: Date
  var x963: Data?
  var phoneNonce: Data?
  var proof: Data?

  /// The request as the Mac checks it against the challenge it pinned.
  var reveal: Reveal {
    Reveal(
      name: name, commitment: commitment, created: created, x963: x963, phoneNonce: phoneNonce,
      proof: proof)
  }

  var hasReveal: Bool { x963 != nil }
}

/// What the Mac granted a phone.
struct PairingGrant: Sendable {
  let scope: Scope
  let macName: String
}

/// A request the Mac has not answered within this time is ignored, and the
/// phone starts again with a new key commitment.
let requestLifetime: TimeInterval = 10 * 60

/// 16 random bytes.
func randomNonce() -> Data {
  Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
}

struct PairingCloud: Sendable {
  private let database = CKContainer(identifier: "iCloud.com.stemmacorp.board")
    .privateCloudDatabase
  private let zone = CKRecordZone.ID(zoneName: "Pairing")

  /// Creates the zone the records live in. Doing it again changes nothing.
  func prepare() async throws {
    _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zone)], deleting: [])
  }

  /// Publishes or updates the request, and removes the challenge and grant of
  /// an earlier pairing when `fresh` is set.
  func publish(_ request: PairingRequest, fresh: Bool) async throws {
    let record = CKRecord(recordType: "PairingRequest", recordID: id("", request.id))
    record["name"] = request.name
    record["commitment"] = request.commitment
    record["created"] = request.created
    record["publicKey"] = request.x963
    record["nonce"] = request.phoneNonce
    record["proof"] = request.proof
    let stale = fresh ? [id("challenge-", request.id), id("grant-", request.id)] : []
    _ = try await database.modifyRecords(saving: [record], deleting: stale, savePolicy: .allKeys)
  }

  /// The Mac's nonce for the device, or nil while the Mac has not sent one.
  func challenge(for deviceID: String) async throws -> Data? {
    try await fetch(id("challenge-", deviceID))?["nonce"] as? Data
  }

  func challenge(_ deviceID: String, nonce: Data) async throws {
    let record = CKRecord(recordType: "PairingChallenge", recordID: id("challenge-", deviceID))
    record["nonce"] = nonce
    _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
  }

  /// The grant for the device, or nil while the Mac has not answered.
  func grant(for deviceID: String) async throws -> PairingGrant? {
    guard let record = try await fetch(id("grant-", deviceID)) else { return nil }
    return PairingGrant(
      scope: Scope(rawValue: record["scope"] as? Int ?? 0),
      macName: record["macName"] as? String ?? "your Mac")
  }

  /// Requests younger than `requestLifetime` with no grant yet, newest first.
  func pendingRequests(now: Date = Date()) async throws -> [PairingRequest] {
    let changes = try await database.recordZoneChanges(inZoneWith: zone, since: nil)
    let records = changes.modificationResultsByID.values.compactMap { try? $0.get().record }
    let names = Set(records.map(\.recordID.recordName))
    return records.compactMap { record -> PairingRequest? in
      guard record.recordType == "PairingRequest",
        !names.contains("grant-" + record.recordID.recordName),
        let name = record["name"] as? String,
        let commitment = record["commitment"] as? Data,
        let created = record["created"] as? Date,
        now.timeIntervalSince(created) < requestLifetime
      else { return nil }
      return PairingRequest(
        id: record.recordID.recordName, name: name, commitment: commitment, created: created,
        x963: record["publicKey"] as? Data, phoneNonce: record["nonce"] as? Data,
        proof: record["proof"] as? Data)
    }.sorted { $0.created > $1.created }
  }

  func answer(_ deviceID: String, scope: Scope, macName: String) async throws {
    let record = CKRecord(recordType: "PairingGrant", recordID: id("grant-", deviceID))
    record["scope"] = scope.rawValue
    record["macName"] = macName
    _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
  }

  /// Removes the request and its challenge. With `grant`, removes the grant too.
  func withdraw(_ deviceID: String, grant: Bool = false) async throws {
    let ids =
      [id("", deviceID), id("challenge-", deviceID)] + (grant ? [id("grant-", deviceID)] : [])
    _ = try await database.modifyRecords(saving: [], deleting: ids)
  }

  private func fetch(_ id: CKRecord.ID) async throws -> CKRecord? {
    do {
      return try await database.record(for: id)
    } catch let error as CKError where error.code == .unknownItem {
      return nil
    }
  }

  private func id(_ prefix: String, _ deviceID: String) -> CKRecord.ID {
    CKRecord.ID(recordName: prefix + deviceID, zoneID: zone)
  }
}
