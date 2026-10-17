// attention-sign: shows the owner a directive statement and signs exactly those
// bytes with a Secure Enclave key, which asks for Touch ID on every signature.
//
//   attention-sign key               print the public key, making it on first use
//   attention-sign sign <statement>  show the statement, sign it, print the signature
//
// When the owner requests changes instead, `sign` prints their feedback and exits 3.
import CryptoKit
import Foundation
import LocalAuthentication
import SSHSig

let keyFile = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent(".config/attention/secure-enclave-key")

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("attention-sign: \(message)\n".utf8))
  exit(1)
}

/// The key, from the Secure Enclave blob in `keyFile`. The blob is useless off this Mac's chip.
func loadKey(context: LAContext? = nil) throws -> SecureEnclave.P256.Signing.PrivateKey {
  let blob = try Data(contentsOf: keyFile)
  return try SecureEnclave.P256.Signing.PrivateKey(
    dataRepresentation: blob, authenticationContext: context)
}

func makeKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
  var error: Unmanaged<CFError>?
  guard
    let access = SecAccessControlCreateWithFlags(
      nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .biometryCurrentSet],
      &error
    )
  else { fail("cannot describe the key's access: \(String(describing: error))") }
  let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
  try FileManager.default.createDirectory(
    at: keyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
  try key.dataRepresentation.write(to: keyFile, options: [.withoutOverwriting])
  return key
}

MainActor.assumeIsolated {
  let arguments = CommandLine.arguments.dropFirst()
  do {
    switch arguments.first {
    case "key":
      let key = FileManager.default.fileExists(atPath: keyFile.path) ? try loadKey() : try makeKey()
      print(openSSHPublicKey(x963: key.publicKey.x963Representation, comment: "attention"))
    case "sign" where arguments.count == 2:
      let message = try Data(contentsOf: URL(fileURLWithPath: arguments.last!))
      guard let statement = String(data: message, encoding: .utf8) else {
        fail("the statement is not UTF-8")
      }
      switch choose(statement) {
      case .sign: break
      case .cancel: fail("the owner cancelled, so nothing was signed")
      case .changes(let feedback):
        print(feedback)
        exit(3)
      }
      let context = LAContext()
      context.localizedReason = "sign the directive you just read"
      let key = try loadKey(context: context)
      let armor = try sign(
        message: message, x963: key.publicKey.x963Representation, namespace: directiveNamespace
      ) {
        try key.signature(for: $0).rawRepresentation
      }
      print(armor, terminator: "")
    default:
      fail("usage: attention-sign key | attention-sign sign <statement-file>")
    }
  } catch {
    fail("\(error)")
  }
}
