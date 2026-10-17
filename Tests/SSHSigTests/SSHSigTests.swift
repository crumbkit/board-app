import CryptoKit
import Foundation
import SSHSig
import XCTest

/// Each test signs with a software P-256 key, which signs as the Secure Enclave
/// does, and asks the system's `ssh-keygen` whether the signature verifies.
final class SSHSigTests: XCTestCase {
  func testSsh_keygen_verifies_a_signed_message() throws {
    XCTAssertEqual(
      try verify(signing: "directive", checking: "directive", namespace: directiveNamespace), 0)
  }

  func testSsh_keygen_refuses_a_changed_message() throws {
    XCTAssertNotEqual(
      try verify(signing: "directive", checking: "directive!", namespace: directiveNamespace), 0)
  }

  func testSsh_keygen_refuses_a_signature_from_another_namespace() throws {
    XCTAssertNotEqual(try verify(signing: "directive", checking: "directive", namespace: "git"), 0)
  }

  func testMany_keys_verify_so_r_and_s_are_encoded_whatever_their_top_bits() throws {
    for _ in 0..<32 {
      XCTAssertEqual(
        try verify(signing: "directive", checking: "directive", namespace: directiveNamespace), 0)
    }
  }

  private func verify(signing signed: String, checking checked: String, namespace: String) throws
    -> Int32
  {
    let key = P256.Signing.PrivateKey()
    let x963 = key.publicKey.x963Representation
    let armor = try sign(message: Data(signed.utf8), x963: x963, namespace: namespace) { data in
      try key.signature(for: data).rawRepresentation
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let signers = directory.appendingPathComponent("allowed_signers")
    let signature = directory.appendingPathComponent("directive.sig")
    try "owner \(openSSHPublicKey(x963: x963, comment: "test"))\n".write(
      to: signers, atomically: true, encoding: .utf8)
    try armor.write(to: signature, atomically: true, encoding: .utf8)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
    process.arguments = [
      "-Y", "verify", "-f", signers.path, "-I", "owner", "-n", directiveNamespace, "-s",
      signature.path,
    ]
    let input = Pipe()
    process.standardInput = input
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    input.fileHandleForWriting.write(Data(checked.utf8))
    try input.fileHandleForWriting.close()
    process.waitUntilExit()
    return process.terminationStatus
  }
}
