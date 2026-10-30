// The owner's private iCloud database, made on first use and only when this
// build is entitled to it, since making the container without the entitlement
// stops the app.
import CloudKit
import Foundation
import Requests

/// Thrown by every iCloud call in a build without the iCloud entitlement,
/// such as an unsigned build.
struct CloudUnavailable: LocalizedError {
  var errorDescription: String? { "iCloud is unavailable: this build is not signed for iCloud." }
}

/// The private database, or nil when this build may not use iCloud. A global
/// is made once, on first use.
private let privateDatabase: CKDatabase? =
  entitledToCloudKit() ? CKContainer(identifier: boardContainerID).privateCloudDatabase : nil

/// The private database, or CloudUnavailable.
func boardDatabase() throws -> CKDatabase {
  guard let privateDatabase else { throw CloudUnavailable() }
  return privateDatabase
}
