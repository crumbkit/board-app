import CryptoKit
import Foundation
import SSHSig
import XCTest

/// Each test signs with a software P-256 key, which signs as the Secure Enclave
/// does, and asks the system's `ssh-keygen` whether the signature verifies.
final class SSHSigTests: XCTestCase {
  func testSsh_keygen_verifies_a_signed_message() throws {
    XCTAssertEqual(
      try verify(signing: "order", checking: "order", namespace: orderNamespace), 0)
  }

  func testSsh_keygen_refuses_a_changed_message() throws {
    XCTAssertNotEqual(
      try verify(signing: "order", checking: "order!", namespace: orderNamespace), 0)
  }

  func testSsh_keygen_refuses_a_signature_from_another_namespace() throws {
    XCTAssertNotEqual(try verify(signing: "order", checking: "order", namespace: "git"), 0)
  }

  func testAn_approval_does_not_verify_as_an_order_and_an_order_signature_does() throws {
    XCTAssertNotEqual(
      try verify(
        signing: "board/approve/v1\n", checking: "board/approve/v1\n", namespace: approvalNamespace),
      0)
    XCTAssertEqual(
      try verify(
        signing: "board/approve/v1\n", checking: "board/approve/v1\n", namespace: orderNamespace
      ), 0)
  }

  func testMany_keys_verify_so_r_and_s_are_encoded_whatever_their_top_bits() throws {
    for _ in 0..<32 {
      XCTAssertEqual(
        try verify(signing: "order", checking: "order", namespace: orderNamespace), 0)
    }
  }
  func testThe_signing_key_is_read_back_from_an_armored_signature() throws {
    let key = P256.Signing.PrivateKey()
    let x963 = key.publicKey.x963Representation
    let armor = try sign(message: Data("order".utf8), x963: x963, namespace: orderNamespace) {
      try key.signature(for: $0).rawRepresentation
    }
    XCTAssertEqual(signingKey(armored: armor), x963)
  }

  func testA_signature_that_is_not_armored_names_no_key() {
    XCTAssertNil(signingKey(armored: "not a signature"))
    XCTAssertNil(
      signingKey(armored: "-----BEGIN SSH SIGNATURE-----\nAAAA\n-----END SSH SIGNATURE-----\n"))
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
    let signature = directory.appendingPathComponent("order.sig")
    try "owner \(openSSHPublicKey(x963: x963, comment: "test"))\n".write(
      to: signers, atomically: true, encoding: .utf8)
    try armor.write(to: signature, atomically: true, encoding: .utf8)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
    process.arguments = [
      "-Y", "verify", "-f", signers.path, "-I", "owner", "-n", orderNamespace, "-s",
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
