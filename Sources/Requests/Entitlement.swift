// Whether this build may use Board's iCloud container. CloudKit stops the app
// when a build without the iCloud entitlement makes a container, as an
// unsigned build does, so the apps ask this first.
import Foundation

#if os(macOS)
  import Security
#endif

/// The container the phone and the Mac share requests and pairings through.
public let boardContainerID = "iCloud.com.stemmacorp.board"

/// True when this process is entitled to `container` through CloudKit.
/// An iOS app cannot read its own entitlements, and runs only when signed
/// with them, so on iOS this is always true.
public func entitledToCloudKit(_ container: String = boardContainerID) -> Bool {
  #if os(macOS)
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    func strings(_ name: String) -> [String] {
      SecTaskCopyValueForEntitlement(task, name as CFString, nil) as? [String] ?? []
    }
    return strings("com.apple.developer.icloud-services").contains("CloudKit")
      && strings("com.apple.developer.icloud-container-identifiers").contains(container)
  #else
    return true
  #endif
}
