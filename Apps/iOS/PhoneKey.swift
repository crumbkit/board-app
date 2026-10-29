// The phone's Secure Enclave key. Signing with it needs Face ID or Touch ID,
// whichever the device has, and the key cannot leave this phone: the stored blob is useless on any other chip.
import CryptoKit
import Foundation
import LocalAuthentication
import Requests
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
    let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access())
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

  /// Who may use the key: the owner, by the biometry enrolled when it was made.
  private static func access() throws -> SecAccessControl {
    var error: Unmanaged<CFError>?
    guard
      let access = SecAccessControlCreateWithFlags(
        nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .biometryCurrentSet],
        &error)
    else { throw error!.takeRetainedValue() as Error }
    return access
  }

  /// The armored SSH signature of the effect's approval statement, in the
  /// namespace Board checks it in.
  static func approve(_ effect: Effect) async throws -> String {
    let key = try load()
    let signer = try await unlocked(key, reason: "approve what you just read")
    return try sign(
      message: Data(effect.approval.utf8), x963: key.publicKey.x963Representation,
      namespace: Approval.effect.namespace
    ) { try signer.signature(for: $0).rawRepresentation }
  }

  /// The key's public half, as the X9.63 bytes pairing reveals.
  static func publicKey() throws -> Data { try load().publicKey.x963Representation }

  /// The raw r‖s signature of a pairing transcript, which proves to the Mac
  /// that this phone holds the key it revealed as `x963`. It throws when the
  /// key changed since then, since the Mac would refuse a proof by another key.
  static func proof(for transcript: Data, revealed x963: Data) async throws -> Data {
    let key = try load()
    guard key.publicKey.x963Representation == x963 else { throw KeyChanged() }
    let signer = try await unlocked(key, reason: "prove this iPhone holds its new Board key")
    return try signer.signature(for: transcript).rawRepresentation
  }

  struct KeyChanged: LocalizedError {
    var errorDescription: String? { "This iPhone's key changed while it paired. Pair again." }
  }

  /// `key` with the owner's biometry checked, so it signs without asking
  /// again. A cancel is LocalAuthentication's own error.
  private static func unlocked(_ key: SecureEnclave.P256.Signing.PrivateKey, reason: String)
    async throws -> SecureEnclave.P256.Signing.PrivateKey
  {
    let context = LAContext()
    _ = try await context.evaluateAccessControl(
      access(), operation: .useKeySign, localizedReason: reason)
    return try SecureEnclave.P256.Signing.PrivateKey(
      dataRepresentation: key.dataRepresentation, authenticationContext: context)
  }

  /// Whether this device has a Secure Enclave to hold the key.
  static var isAvailable: Bool { SecureEnclave.isAvailable }

  /// Whether `error` came from the biometry check.
  static func isBiometryError(_ error: Error) -> Bool { error is LAError }

  /// The biometry this device signs with, read once from LocalAuthentication.
  static let biometry: Biometry = {
    let context = LAContext()
    _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    switch context.biometryType {
    case .touchID: return .touchID
    case .opticID: return .opticID
    // biometryType is set once canEvaluatePolicy returns, even when it fails
    // because nothing is enrolled. Only a device without the hardware reports
    // none; it is named as Face ID, and signing fails with LocalAuthentication's
    // own message.
    default: return .faceID
    }
  }()

  /// Whether `error` is the owner or the system cancelling biometry, which
  /// needs no message.
  static func isCancel(_ error: Error) -> Bool {
    let error = error as NSError
    return error.domain == LAErrorDomain
      && [LAError.userCancel, .appCancel, .systemCancel].map(\.rawValue).contains(error.code)
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
