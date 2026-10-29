// The phone's Secure Enclave key. Signing with it needs Face ID, and the key
// cannot leave this phone: the stored blob is useless on any other chip.
import CryptoKit
import Foundation
import LocalAuthentication
import SSHSig

enum PhoneKey {
  private static var file: URL {
    URL.applicationSupportDirectory.appendingPathComponent("secure-enclave-key")
  }

  /// The key, made on first use. A blob that does not load, such as one
  /// restored from a backup onto another phone, is replaced by a new key, which
  /// the owner then pairs again.
  static func load() throws -> SecureEnclave.P256.Signing.PrivateKey {
    if FileManager.default.fileExists(atPath: file.path) {
      // A read that fails is thrown, so a passing failure never replaces a
      // paired key. Only a blob that this chip cannot use is replaced.
      let blob = try Data(contentsOf: file)
      if let key = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob) {
        return key
      }
      try FileManager.default.removeItem(at: file)
    }
    var error: Unmanaged<CFError>?
    guard
      let access = SecAccessControlCreateWithFlags(
        nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .biometryCurrentSet],
        &error)
    else { throw error!.takeRetainedValue() as Error }
    let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try key.dataRepresentation.write(
      to: file, options: [.withoutOverwriting, .completeFileProtection])
    // The blob is useless on any other phone, so a backup has no use for it.
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var excluded = file
    try excluded.setResourceValues(values)
    return key
  }

  /// The armored SSH signature of the effect's approval statement, in the
  /// namespace Board checks it in. The Secure Enclave asks for Face ID.
  static func approve(_ effect: Effect) throws -> String {
    let key = try load()
    let context = LAContext()
    context.localizedReason = "approve what you just read"
    let signer = try SecureEnclave.P256.Signing.PrivateKey(
      dataRepresentation: key.dataRepresentation, authenticationContext: context)
    return try sign(
      message: Data(effect.approval.utf8), x963: key.publicKey.x963Representation,
      namespace: Approval.effect.namespace
    ) { try signer.signature(for: $0).rawRepresentation }
  }

  /// The id this phone pairs under. It stays the same across pairings, so
  /// pairing again replaces the phone's line instead of adding another.
  static var deviceID: String {
    if let id = UserDefaults.standard.string(forKey: "deviceID") { return id }
    let id = UUID().uuidString
    UserDefaults.standard.set(id, forKey: "deviceID")
    return id
  }
}
