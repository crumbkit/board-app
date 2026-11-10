// attention-sign: shows the owner an order statement and signs exactly those
// bytes with a Secure Enclave key, which asks for Touch ID on every signature.
//
//   attention-sign key               print the public key, making it on first use
//   attention-sign line              print this Mac's line for Board's allowed signers file
//   attention-sign sign <statement>  show the statement, sign it, print the signature
//   attention-sign approve <statement>  the same for a Board approval, in the namespace its first line names
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
    let access = unsafe SecAccessControlCreateWithFlags(
      nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .biometryCurrentSet],
      &error
    )
  else { fail("cannot describe the key's access: \(unsafe String(describing: error))") }
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
    case "line":
      let key = FileManager.default.fileExists(atPath: keyFile.path) ? try loadKey() : try makeKey()
      print(AllowedSigners.macLine(x963: key.publicKey.x963Representation, comment: "attention"))
    case let command where (command == "sign" || command == "approve") && arguments.count == 2:
      guard let file = arguments.last else {
        preconditionFailure("this case matches only when there are two arguments")
      }
      let message = try Data(contentsOf: URL(fileURLWithPath: file))
      guard let statement = String(data: message, encoding: .utf8) else {
        fail("the statement is not UTF-8")
      }
      // An order is signed in its namespace and an approval in Board's, so the
      // owner's signature of one never stands for the other.
      let approval = Approval(statement: statement)
      if command == "approve" && approval == nil {
        fail(
          "the statement is not a Board approval: its first line names no approval namespace"
        )
      }
      if command == "sign" && approval != nil {
        fail("the statement is a Board approval: sign it with `attention-sign approve`")
      }
      switch choose(statement, approval: approval) {
      case .sign: break
      case .cancel: fail("the owner cancelled, so nothing was signed")
      case .changes(let feedback):
        print(feedback)
        exit(3)
      }
      let context = LAContext()
      context.localizedReason =
        approval == nil ? "sign the order you just read" : "approve what you just read"
      let key = try loadKey(context: context)
      let armor = try sign(
        message: message, x963: key.publicKey.x963Representation,
        namespace: approval?.namespace ?? orderNamespace
      ) {
        try key.signature(for: $0).rawRepresentation
      }
      print(armor, terminator: "")
    default:
      fail(
        "usage: attention-sign key | attention-sign line | attention-sign sign <statement-file> | attention-sign approve <statement-file>"
      )
    }
  } catch {
    fail("\(error)")
  }
}
