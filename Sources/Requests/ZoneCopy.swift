// A copy of an iCloud zone's records, kept up to date by reading only the
// changes since the last read. It knows nothing of CloudKit: the caller
// supplies the read of one batch of changes.
import Foundation

public struct ZoneCopy<Record: Sendable, Token: Sendable>: Sendable {
  /// One batch of changes, as a read of the zone returns it.
  public struct Batch: Sendable {
    /// The records saved since the token the batch was asked for, by name.
    public let modified: [String: Record]
    /// The names of the records deleted since that token.
    public let deleted: [String]
    /// The token to ask for the next batch with.
    public let token: Token
    /// Whether more changes wait after this batch.
    public let moreComing: Bool

    public init(modified: [String: Record], deleted: [String], token: Token, moreComing: Bool) {
      self.modified = modified
      self.deleted = deleted
      self.token = token
      self.moreComing = moreComing
    }
  }

  /// Every record in the copy, by name.
  public private(set) var records: [String: Record] = [:]
  /// The token of the last batch applied, or nil before any batch.
  public private(set) var token: Token?

  public init() {}

  /// Reads the changes since the last token, batch by batch, and applies
  /// each batch as it arrives. A read that throws keeps the batches it
  /// applied, so the next read resumes from the last token. When
  /// `isExpired` says an error means the token no longer works, the copy
  /// empties itself and reads once more from no token.
  public mutating func read(
    changes: @Sendable (Token?) async throws -> Batch,
    isExpired: @Sendable (Error) -> Bool
  ) async throws {
    do {
      try await walk(changes)
    } catch let error where isExpired(error) {
      records = [:]
      token = nil
      try await walk(changes)
    }
  }

  private mutating func walk(_ changes: @Sendable (Token?) async throws -> Batch) async throws {
    while true {
      let batch = try await changes(token)
      apply(batch)
      guard batch.moreComing else { return }
    }
  }

  /// Saved records overwrite the copy's; deleted ones leave it.
  private mutating func apply(_ batch: Batch) {
    records.merge(batch.modified) { _, new in new }
    for name in batch.deleted { records[name] = nil }
    token = batch.token
  }
}
