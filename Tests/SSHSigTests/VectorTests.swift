import CryptoKit
import Foundation
import SSHSig
import XCTest

/// The repository's copy of Board's `vectors/signing/v1`.
enum Vectors {
  static let directory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("vectors/signing/v1")

  static func data(_ name: String) throws -> Data {
    try Data(contentsOf: directory.appendingPathComponent(name))
  }

  static func text(_ name: String) throws -> String {
    String(decoding: try data(name), as: UTF8.self)
  }

  static func manifest() throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data("manifest.json")) as? [String: Any])
  }

  /// The namespace the manifest gives a layout, such as `order.statement`.
  static func namespace(of layout: String) throws -> String {
    let layouts = try XCTUnwrap(manifest()["layouts"] as? [String: [String: String]])
    return try XCTUnwrap(layouts[layout]?["namespace"])
  }

  /// The test owner's public key, as the X9.63 bytes at the end of `key.pub`'s blob.
  static func ownerKey() throws -> Data {
    let blob = try XCTUnwrap(Data(base64Encoded: String(text("key.pub").split(separator: " ")[1])))
    return blob.suffix(65)
  }
}

/// crumbkit/board, board-attention and this repository build, sign and verify the
/// same bytes, and Board's vectors fix them. These tests prove that this
/// repository's builders give the vectors' bytes and namespaces, and that the
/// lines it writes into allowed signers files admit the vectors' signatures
/// in the right namespace only. They use the vectors' test keys and temporary
/// files, never the owner's key or allowed signers files. They do not prove
/// the Secure Enclave signs as the test key does; SSHSigTests checks the
/// signing path with a software key.
final class VectorTests: XCTestCase {
  func testTheNamespacesAreTheOnesTheVectorsSignIn() throws {
    XCTAssertEqual(Approval.effect.namespace, try Vectors.namespace(of: "approval.statement"))
    XCTAssertEqual(Approval.write.namespace, try Vectors.namespace(of: "write.statement"))
    XCTAssertEqual(orderNamespace, try Vectors.namespace(of: "order.statement"))
  }

  func testEachStatementIsReadAsTheKindItsLayoutNames() throws {
    XCTAssertEqual(Approval(statement: try Vectors.text("approval.statement")), .effect)
    XCTAssertEqual(Approval(statement: try Vectors.text("write.statement")), .write)
    XCTAssertNil(Approval(statement: try Vectors.text("order.statement")))
    let order = try Vectors.text("order.statement")
    XCTAssertEqual(Statement.parse(order)?.text, order)
  }

  func testThePhoneBuildsTheApprovalStatementByteForByte() throws {
    let effect = try Effect(json: Vectors.data("approval.effect.json"))
    XCTAssertEqual(Data(effect.approval.utf8), try Vectors.data("approval.statement"))
  }

  func testThePublicKeyLineIsTheOneSshKeygenWrote() throws {
    let line = try Vectors.text("key.pub").trimmingCharacters(in: .newlines)
    XCTAssertEqual(openSSHPublicKey(x963: try Vectors.ownerKey(), comment: "vectors owner"), line)
  }

  func testTheArmorOfTheRawSignatureIsTheSignatureSshKeygenWrote() throws {
    let statement = try Vectors.data("approval.statement")
    let signed = signedData(message: statement, namespace: Approval.effect.namespace)
    XCTAssertEqual(signed.suffix(64), Data(SHA512.hash(data: statement)))
    XCTAssertEqual(
      armored(
        x963: try Vectors.ownerKey(), rawSignature: try Vectors.data("approval.raw"),
        namespace: Approval.effect.namespace),
      try Vectors.text("approval.sig"))
  }

  func testTheVectorsVerifyInTheirNamespaceAndTheCrossSignaturesDoNot() throws {
    let signers = try Vectors.text("allowed_signers")
    XCTAssertEqual(
      try verify("approval.sig", "approval.statement", "approval.statement", signers), 0)
    XCTAssertEqual(try verify("write.sig", "write.statement", "write.statement", signers), 0)
    XCTAssertEqual(try verify("order.sig", "order.statement", "order.statement", signers), 0)
    for cross in [
      "cross/approval-in-write.sig", "cross/write-in-approval.sig", "cross/approval-by-other.sig",
      "cross/order-in-directive.sig",
    ] {
      let statement = try XCTUnwrap(
        (Vectors.manifest()["signatures"] as? [String: [String: String]])?[cross]?["statement"])
      // Board checks a statement in its own layout's namespace, as owner.
      XCTAssertNotEqual(try verify(cross, statement, statement, signers), 0, cross)
    }
  }

  func testADevicesBoardLineAdmitsAnApprovalAndNeverTheOwnersWrite() throws {
    let line = try XCTUnwrap(
      AllowedSigners.deviceBoardLine(x963: Vectors.ownerKey(), label: "test", approves: true))
    XCTAssertEqual(try verify("approval.sig", "approval.statement", "approval.statement", line), 0)
    XCTAssertNotEqual(try verify("write.sig", "write.statement", "write.statement", line), 0)
    XCTAssertNil(
      AllowedSigners.deviceBoardLine(x963: try Vectors.ownerKey(), label: "test", approves: false))
  }

  func testADevicesAttentionLineAdmitsAnOrderAndNotAnApproval() throws {
    let line = try XCTUnwrap(
      AllowedSigners.deviceAttentionLine(x963: Vectors.ownerKey(), label: "test", signsOrders: true)
    )
    XCTAssertEqual(try verify("order.sig", "order.statement", "order.statement", line), 0)
    XCTAssertNotEqual(
      try verify("approval.sig", "approval.statement", "approval.statement", line), 0)
  }

  func testTheMacsLineAdmitsAnApprovalAndTheOwnersWriteButNotAnOrder() throws {
    let line = AllowedSigners.macLine(x963: try Vectors.ownerKey(), comment: "attention")
    // bin/setup finds an existing line by its exact text, so the text is pinned.
    let key = try Vectors.text("key.pub").split(separator: " ")[1]
    XCTAssertEqual(
      line,
      "owner namespaces=\"board/approve/v1,board/write/v1\" ecdsa-sha2-nistp256 \(key) attention")
    XCTAssertEqual(try verify("approval.sig", "approval.statement", "approval.statement", line), 0)
    XCTAssertEqual(try verify("write.sig", "write.statement", "write.statement", line), 0)
    XCTAssertNotEqual(try verify("order.sig", "order.statement", "order.statement", line), 0)
  }

  /// `ssh-keygen -Y verify`'s exit status for `signature` of `statement` by
  /// principal `owner`, in the namespace the manifest gives `layout`.
  private func verify(_ signature: String, _ statement: String, _ layout: String, _ signers: String)
    throws -> Int32
  {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("signers")
    try Data((signers.hasSuffix("\n") ? signers : signers + "\n").utf8).write(to: file)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
    process.arguments = [
      "-Y", "verify", "-f", file.path, "-I", "owner", "-n", try Vectors.namespace(of: layout),
      "-s", Vectors.directory.appendingPathComponent(signature).path,
    ]
    process.standardInput = try FileHandle(
      forReadingFrom: Vectors.directory.appendingPathComponent(statement))
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
  }
}
