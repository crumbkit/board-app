import CryptoKit
import Foundation
import Pairing
import SSHSig
import Testing

struct PairingCodeTests {
  let phoneNonce = Data(repeating: 1, count: 16)
  let macNonce = Data(repeating: 2, count: 16)

  @Test func the_code_is_six_digits_split_in_threes() {
    let code = PairingCode.code(
      x963: key().x963Representation, phoneNonce: phoneNonce, macNonce: macNonce)
    #expect(code.wholeMatch(of: /[0-9]{3} [0-9]{3}/) != nil, "\(code)")
  }

  @Test func both_devices_derive_the_same_code_from_the_same_key_and_nonces() {
    let x963 = key().x963Representation
    #expect(
      PairingCode.code(x963: x963, phoneNonce: phoneNonce, macNonce: macNonce)
        == PairingCode.code(x963: x963, phoneNonce: phoneNonce, macNonce: macNonce))
  }

  @Test func another_mac_nonce_gives_another_code() {
    let x963 = key().x963Representation
    let codes = Set(
      (0..<20).map { byte in
        PairingCode.code(
          x963: x963, phoneNonce: phoneNonce, macNonce: Data(repeating: UInt8(byte), count: 16))
      })
    #expect(codes.count > 1)
  }

  @Test func the_mac_admits_a_reveal_of_the_key_and_nonce_the_phone_committed_to() {
    let x963 = key().x963Representation
    let commitment = PairingCode.commitment(x963: x963, phoneNonce: phoneNonce)
    #expect(PairingCode.reveals(commitment, x963: x963, phoneNonce: phoneNonce))
  }

  @Test func the_mac_refuses_a_reveal_of_another_key() {
    let commitment = PairingCode.commitment(x963: key().x963Representation, phoneNonce: phoneNonce)
    #expect(
      !PairingCode.reveals(commitment, x963: key().x963Representation, phoneNonce: phoneNonce))
  }

  @Test func the_mac_refuses_a_reveal_of_another_nonce() {
    let x963 = key().x963Representation
    let commitment = PairingCode.commitment(x963: x963, phoneNonce: phoneNonce)
    #expect(!PairingCode.reveals(commitment, x963: x963, phoneNonce: macNonce))
  }

  @Test func the_fingerprint_is_the_one_ssh_keygen_prints() throws {
    let x963 = key().x963Representation
    let file = try temporary("key.pub", "\(openSSHPublicKey(x963: x963, comment: "phone"))\n")
    let printed = try run("/usr/bin/ssh-keygen", ["-l", "-E", "sha256", "-f", file.path]).output
    #expect(printed.contains(Device.fingerprint(x963: x963)), "\(printed)")
  }
}

struct AllowedSignersTests {
  let mac = "owner ecdsa-sha2-nistp256 AAAAmac attention\n"

  @Test func pairing_adds_the_phone_line_and_keeps_the_mac_line() {
    let phone = device()
    let text = AllowedSigners.replacing(phone.id, in: mac, with: "owner LINE \(phone.label)")
    #expect(text == mac + "owner LINE \(phone.label)\n")
  }

  @Test func pairing_the_same_phone_again_replaces_only_its_own_line() {
    let phone = device()
    let other = device()
    let before = mac + "owner OLD \(phone.label)\nowner OTHER \(other.label)\n"
    let text = AllowedSigners.replacing(phone.id, in: before, with: "owner NEW \(phone.label)")
    #expect(text == mac + "owner OTHER \(other.label)\nowner NEW \(phone.label)\n")
  }

  @Test func unpairing_removes_only_the_phone_line() {
    let phone = device()
    let text = AllowedSigners.replacing(phone.id, in: mac + "owner OLD \(phone.label)\n", with: nil)
    #expect(text == mac)
  }

  @Test func a_file_without_a_final_newline_keeps_its_last_line() {
    let phone = device()
    let text = AllowedSigners.replacing(phone.id, in: "owner MAC", with: "owner NEW \(phone.label)")
    #expect(text == "owner MAC\nowner NEW \(phone.label)\n")
  }

  @Test func a_phone_with_no_board_scope_gets_no_board_line_and_one_with_orders_gets_one() {
    let phone = device()
    #expect(AllowedSigners.boardLine(phone, scope: [.orders]) == nil)
    #expect(AllowedSigners.attentionLine(phone, scope: [.orders]) != nil)
    #expect(AllowedSigners.attentionLine(phone, scope: [.approvals]) == nil)
  }

  @Test func the_board_line_names_only_the_approval_namespace_whatever_the_scope() {
    let phone = device()
    #expect(
      AllowedSigners.boardLine(phone, scope: Scope(rawValue: ~0))!.hasPrefix(
        "owner namespaces=\"board/approve/v1\" ecdsa-sha2-nistp256 "))
  }

  @Test func ssh_keygen_admits_a_paired_phone_approval() throws {
    let (phone, key) = signingDevice()
    let line = AllowedSigners.boardLine(phone, scope: Scope(rawValue: ~0))!
    #expect(try verify(key, line: line, namespace: "board/approve/v1") == 0)
  }

  @Test func ssh_keygen_refuses_a_paired_phone_signature_of_an_owner_write() throws {
    let (phone, key) = signingDevice()
    let line = AllowedSigners.boardLine(phone, scope: Scope(rawValue: ~0))!
    #expect(try verify(key, line: line, namespace: "board/write/v1") != 0)
  }

  @Test func ssh_keygen_admits_an_order_signed_by_a_phone_granted_orders() throws {
    let (phone, key) = signingDevice()
    let line = AllowedSigners.attentionLine(phone, scope: [.orders])!
    #expect(try verify(key, line: line, namespace: orderNamespace) == 0)
  }

  private func verify(_ key: P256.Signing.PrivateKey, line: String, namespace: String) throws
    -> Int32
  {
    let message = Data("statement\n".utf8)
    let armor = try sign(
      message: message, x963: key.publicKey.x963Representation, namespace: namespace
    ) { try key.signature(for: $0).rawRepresentation }
    let signers = try temporary("allowed_signers", mac + line + "\n")
    let signature = try temporary("statement.sig", armor)
    return try run(
      "/usr/bin/ssh-keygen",
      ["-Y", "verify", "-f", signers.path, "-I", "owner", "-n", namespace, "-s", signature.path],
      input: message
    ).status
  }
}

private func key() -> P256.Signing.PublicKey { P256.Signing.PrivateKey().publicKey }

private func device() -> Device {
  Device(id: UUID().uuidString, name: "iPhone", x963: key().x963Representation)
}

private func signingDevice() -> (Device, P256.Signing.PrivateKey) {
  let key = P256.Signing.PrivateKey()
  return (
    Device(id: UUID().uuidString, name: "iPhone", x963: key.publicKey.x963Representation), key
  )
}

private func temporary(_ name: String, _ contents: String) throws -> URL {
  let file = try directory().appendingPathComponent(name)
  try contents.write(to: file, atomically: true, encoding: .utf8)
  return file
}

private func run(_ path: String, _ arguments: [String], input: Data = Data()) throws -> (
  status: Int32, output: String
) {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: path)
  process.arguments = arguments
  let stdin = Pipe()
  let stdout = Pipe()
  process.standardInput = stdin
  process.standardOutput = stdout
  process.standardError = Pipe()
  try process.run()
  stdin.fileHandleForWriting.write(input)
  try stdin.fileHandleForWriting.close()
  let output = stdout.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  return (process.terminationStatus, String(decoding: output, as: UTF8.self))
}

struct PairingProofTests {
  let phoneNonce = Data(repeating: 1, count: 16)
  let macNonce = Data(repeating: 2, count: 16)

  @Test func the_mac_admits_a_proof_signed_by_the_revealed_key() throws {
    let key = P256.Signing.PrivateKey()
    let x963 = key.publicKey.x963Representation
    let transcript = PairingProof.transcript(x963: x963, phoneNonce: phoneNonce, macNonce: macNonce)
    let proof = try key.signature(for: transcript).rawRepresentation
    #expect(PairingProof.verifies(proof, x963: x963, phoneNonce: phoneNonce, macNonce: macNonce))
  }

  @Test func the_mac_refuses_a_proof_signed_by_another_key() throws {
    let x963 = P256.Signing.PrivateKey().publicKey.x963Representation
    let transcript = PairingProof.transcript(x963: x963, phoneNonce: phoneNonce, macNonce: macNonce)
    let proof = try P256.Signing.PrivateKey().signature(for: transcript).rawRepresentation
    #expect(!PairingProof.verifies(proof, x963: x963, phoneNonce: phoneNonce, macNonce: macNonce))
  }

  @Test func the_mac_refuses_a_proof_of_another_challenge() throws {
    let key = P256.Signing.PrivateKey()
    let x963 = key.publicKey.x963Representation
    let transcript = PairingProof.transcript(
      x963: x963, phoneNonce: phoneNonce, macNonce: phoneNonce)
    let proof = try key.signature(for: transcript).rawRepresentation
    #expect(!PairingProof.verifies(proof, x963: x963, phoneNonce: phoneNonce, macNonce: macNonce))
  }
}

struct ChallengeTests {
  let phoneNonce = Data(repeating: 1, count: 16)
  let macNonce = Data(repeating: 2, count: 16)
  let created = Date(timeIntervalSince1970: 1_800_000_000)
  let id = UUID().uuidString

  /// The phone's key, its commitment, and the challenge the Mac pinned to it.
  private func pinned() -> (P256.Signing.PrivateKey, Challenge) {
    let key = P256.Signing.PrivateKey()
    let commitment = PairingCode.commitment(
      x963: key.publicKey.x963Representation, phoneNonce: phoneNonce)
    let challenge = Challenge(
      deviceID: id, name: "iPhone", commitment: commitment, created: created, macNonce: macNonce)!
    return (key, challenge)
  }

  private func reveal(_ key: P256.Signing.PrivateKey, nonce: Data) throws -> Reveal {
    let x963 = key.publicKey.x963Representation
    let proof = try key.signature(
      for: PairingProof.transcript(x963: x963, phoneNonce: nonce, macNonce: macNonce)
    ).rawRepresentation
    return Reveal(
      name: "iPhone", commitment: PairingCode.commitment(x963: x963, phoneNonce: nonce),
      created: created, x963: x963, phoneNonce: nonce, proof: proof)
  }

  @Test func the_mac_offers_the_phone_it_challenged() throws {
    let (key, challenge) = pinned()
    let outcome = challenge.check(try reveal(key, nonce: phoneNonce))
    guard case .offer(let device, let code) = outcome else {
      Issue.record("\(outcome)")
      return
    }
    #expect(device.x963 == key.publicKey.x963Representation)
    #expect(
      code
        == PairingCode.code(
          x963: key.publicKey.x963Representation, phoneNonce: phoneNonce, macNonce: macNonce))
  }

  @Test func the_mac_refuses_a_request_rewritten_after_its_challenge_even_with_a_valid_reveal()
    throws
  {
    let (_, challenge) = pinned()
    let attacker = P256.Signing.PrivateKey()
    #expect(challenge.check(try reveal(attacker, nonce: Data(repeating: 9, count: 16))) == .refused)
  }

  @Test func the_mac_refuses_a_reveal_whose_proof_does_not_verify() throws {
    let (key, challenge) = pinned()
    var bad = try reveal(key, nonce: phoneNonce)
    bad.proof = try P256.Signing.PrivateKey().signature(for: Data()).rawRepresentation
    #expect(challenge.check(bad) == .refused)
  }

  @Test func the_mac_waits_while_the_phone_has_not_revealed() throws {
    let (key, challenge) = pinned()
    var unrevealed = try reveal(key, nonce: phoneNonce)
    unrevealed.x963 = nil
    unrevealed.phoneNonce = nil
    unrevealed.proof = nil
    #expect(challenge.check(unrevealed) == .waiting)
  }

  @Test func a_device_id_that_is_not_a_uuid_is_refused_and_a_uuid_is_admitted() {
    let commitment = Data(repeating: 3, count: 32)
    #expect(
      Challenge(
        deviceID: "a\nowner ecdsa-sha2-nistp256 AAAA", name: "iPhone", commitment: commitment,
        created: created, macNonce: macNonce) == nil)
    #expect(
      Challenge(
        deviceID: id, name: "iPhone", commitment: commitment, created: created, macNonce: macNonce)
        != nil)
  }
}

struct AllowedSignersFileTests {
  let mac = "owner ecdsa-sha2-nistp256 AAAAmac attention\n"

  @Test func a_missing_file_is_made_with_the_phone_line_and_mode_644() throws {
    let phone = device()
    let file = try directory().appendingPathComponent("config/board/allowed_signers")
    try AllowedSignersFile.update(file, device: phone.id, line: "owner NEW \(phone.label)")
    #expect(try String(contentsOf: file, encoding: .utf8) == "owner NEW \(phone.label)\n")
    #expect(try mode(file) == 0o644)
  }

  @Test func an_existing_file_keeps_the_mac_line() throws {
    let phone = device()
    let file = try temporary("allowed_signers", mac)
    try AllowedSignersFile.update(file, device: phone.id, line: "owner NEW \(phone.label)")
    #expect(try String(contentsOf: file, encoding: .utf8) == mac + "owner NEW \(phone.label)\n")
  }

  @Test func an_unreadable_file_is_refused_and_left_as_it_was() throws {
    let phone = device()
    let file = try temporary("allowed_signers", mac)
    try FileManager.default.setAttributes([.posixPermissions: 0o200], ofItemAtPath: file.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
    }
    #expect(throws: CocoaError.self) {
      try AllowedSignersFile.update(file, device: phone.id, line: "owner NEW \(phone.label)")
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
    #expect(try String(contentsOf: file, encoding: .utf8) == mac)
  }

  @Test func a_file_others_may_write_is_refused() throws {
    let phone = device()
    let file = try temporary("allowed_signers", mac)
    try FileManager.default.setAttributes([.posixPermissions: 0o664], ofItemAtPath: file.path)
    #expect(throws: AllowedSignersFile.Refusal.writableByOthers(file.path)) {
      try AllowedSignersFile.update(file, device: phone.id, line: "owner NEW \(phone.label)")
    }
  }

  @Test func a_file_only_its_owner_may_write_is_admitted() throws {
    let phone = device()
    let file = try temporary("allowed_signers", mac)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
    try AllowedSignersFile.update(file, device: phone.id, line: "owner NEW \(phone.label)")
    #expect(try String(contentsOf: file, encoding: .utf8).hasSuffix("owner NEW \(phone.label)\n"))
  }

  @Test func a_file_reached_through_a_symlink_is_updated_and_the_link_kept() throws {
    let phone = device()
    let target = try temporary("allowed_signers", mac)
    let link = try directory().appendingPathComponent("allowed_signers")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    try AllowedSignersFile.update(link, device: phone.id, line: "owner NEW \(phone.label)")
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
    #expect(try String(contentsOf: target, encoding: .utf8) == mac + "owner NEW \(phone.label)\n")
  }

  @Test func a_symlink_to_nothing_is_refused_and_left_a_symlink() throws {
    let phone = device()
    let folder = try directory()
    let link = folder.appendingPathComponent("allowed_signers")
    try FileManager.default.createSymbolicLink(
      at: link, withDestinationURL: folder.appendingPathComponent("missing"))
    #expect(throws: CocoaError.self) {
      try AllowedSignersFile.update(link, device: phone.id, line: "owner NEW \(phone.label)")
    }
    #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil)
  }

  @Test func a_symlink_to_a_file_others_may_write_is_refused() throws {
    let phone = device()
    let target = try temporary("allowed_signers", mac)
    try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: target.path)
    let link = try directory().appendingPathComponent("allowed_signers")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    #expect(throws: AllowedSignersFile.Refusal.writableByOthers(target.path)) {
      try AllowedSignersFile.update(link, device: phone.id, line: "owner NEW \(phone.label)")
    }
  }

  @Test func a_file_only_its_owner_may_read_keeps_its_mode() throws {
    let phone = device()
    let file = try temporary("allowed_signers", mac)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    try AllowedSignersFile.update(file, device: phone.id, line: "owner NEW \(phone.label)")
    #expect(try mode(file) == 0o600)
  }

  private func mode(_ file: URL) throws -> Int {
    (try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber)
      .intValue
  }
}

private func directory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory
}

struct PairedDeviceTests {
  let mac = "owner ecdsa-sha2-nistp256 AAAAmac attention\n"

  @Test func a_phone_paired_with_both_scopes_lists_once_with_both() {
    let phone = device()
    let board = mac + AllowedSigners.boardLine(phone, scope: .suggested)! + "\n"
    let attention = mac + AllowedSigners.attentionLine(phone, scope: .suggested)! + "\n"
    let listed = PairedDevice.list(board: board, attention: attention)
    #expect(listed.map(\.id) == [phone.id])
    #expect(listed.first?.scope == .suggested)
    #expect(listed.first?.x963 == phone.x963)
    #expect(listed.first?.fingerprint == phone.fingerprint)
    #expect(listed.first?.boardLine == AllowedSigners.boardLine(phone, scope: .suggested))
    #expect(listed.first?.attentionLine == AllowedSigners.attentionLine(phone, scope: .suggested))
  }

  @Test func a_phone_with_a_line_in_attentions_file_alone_may_sign_orders_only() {
    let phone = device()
    let attention = AllowedSigners.attentionLine(phone, scope: [.orders])! + "\n"
    let listed = PairedDevice.list(board: mac, attention: attention)
    #expect(listed.first?.scope == [.orders])
    #expect(listed.first?.boardLine == nil)
  }

  @Test func a_line_whose_namespaces_do_not_name_the_scope_grants_nothing() {
    let phone = device()
    let line = openSSHPublicKey(x963: phone.x963, comment: phone.label)
    let listed = PairedDevice.list(board: "owner namespaces=\"git\" \(line)\n", attention: "")
    #expect(listed.first?.scope == [])
  }

  @Test func the_mac_line_and_labels_that_are_not_uuids_are_not_devices() {
    let text = mac + "owner ecdsa-sha2-nistp256 AAAA board-app/device/not-a-uuid\n"
    #expect(PairedDevice.list(board: text, attention: text).isEmpty)
  }

  @Test func each_listed_line_is_one_that_replacing_removes() {
    let phone = device()
    let board =
      mac + AllowedSigners.boardLine(phone, scope: .suggested)! + "\n"
      + "owner AAAA \(phone.label) \n"
    let listed = PairedDevice.list(board: board, attention: "")
    let removed = AllowedSigners.replacing(phone.id, in: board, with: nil)
    #expect(listed.count == 1)
    #expect(!removed.contains(listed.first!.boardLine!))
  }

  @Test func a_key_that_does_not_read_leaves_no_fingerprint() {
    let id = UUID().uuidString
    let listed = PairedDevice.list(
      board: "owner ecdsa-sha2-nistp256 AAAA board-app/device/\(id)\n", attention: "")
    #expect(listed.first?.fingerprint == nil)
  }

  @Test func a_device_without_a_stored_name_is_named_by_its_id() {
    let listed = PairedDevice.list(
      board: "owner AAAA board-app/device/32939622-2420-45C9-B0B9-060CB36DDED6\n", attention: "")
    #expect(listed.first?.fallbackName == "iPhone 32939622")
  }

  @Test func namespaces_are_read_from_the_option() {
    #expect(
      PairedDevice.namespaces("owner namespaces=\"a/v1,b/v1\" ecdsa-sha2-nistp256 AAAA x")
        == ["a/v1", "b/v1"])
    #expect(PairedDevice.namespaces("owner ecdsa-sha2-nistp256 AAAA x") == [])
  }
}
