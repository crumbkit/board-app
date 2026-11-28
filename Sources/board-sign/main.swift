// board-sign: shows the owner an order statement and signs exactly those
// bytes with a Secure Enclave key, which asks for Touch ID on every signature.
//
//   board-sign key               print the public key, making it when there is none
//   board-sign line              print this Mac's line for Board's allowed signers file
//   board-sign sign <statement>  show the statement, sign it, print the signature
//   board-sign approve <statement>  the same for a Board approval, in the namespace its first line names
//
// When the owner requests changes instead, `sign` prints their feedback and exits 3.
// The key is in ~/.config/board; KeyFile moves attention-sign's key there.
import CryptoKit
import Foundation
import LocalAuthentication
import SSHSig

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("board-sign: \(message)\n".utf8))
  exit(1)
}

/// Where the key is, after moving attention-sign's key when only it exists.
/// A failed move is named on stderr, and the key is used where it is.
let located = KeyFile(home: FileManager.default.homeDirectoryForCurrentUser).locate()
let keyFile: URL
switch located {
case .found(let file), .none(let file):
  keyFile = file
case .unmoved(let file, let problem):
  FileHandle.standardError.write(Data("board-sign: \(problem)\n".utf8))
  keyFile = file
}

/// The key, from the Secure Enclave blob in `keyFile`. The blob is useless off this Mac's chip.
func loadKey(context: LAContext? = nil) throws -> SecureEnclave.P256.Signing.PrivateKey {
  let blob = try Data(contentsOf: keyFile)
  return try SecureEnclave.P256.Signing.PrivateKey(
    dataRepresentation: blob, authenticationContext: context)
}

/// The key, made in the Secure Enclave only when no key file exists.
func keyMakingOne() throws -> SecureEnclave.P256.Signing.PrivateKey {
  if case .none = located { return try makeKey() }
  return try loadKey()
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
      let key = try keyMakingOne()
      print(openSSHPublicKey(x963: key.publicKey.x963Representation, comment: "board"))
    case "line":
      let key = try keyMakingOne()
      print(AllowedSigners.macLine(x963: key.publicKey.x963Representation, comment: "board"))
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
        fail("the statement is a Board approval: sign it with `board-sign approve`")
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
        "usage: board-sign key | board-sign line | board-sign sign <statement-file> | board-sign approve <statement-file>"
      )
    }
  } catch {
    fail("\(error)")
  }
}
