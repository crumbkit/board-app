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
    let text = PairedDevice.replacing(phone.id, in: mac, with: "owner LINE \(phone.label)")
    #expect(text == mac + "owner LINE \(phone.label)\n")
  }

  @Test func pairing_the_same_phone_again_replaces_only_its_own_line() {
    let phone = device()
    let other = device()
    let before = mac + "owner OLD \(phone.label)\nowner OTHER \(other.label)\n"
    let text = PairedDevice.replacing(phone.id, in: before, with: "owner NEW \(phone.label)")
    #expect(text == mac + "owner OTHER \(other.label)\nowner NEW \(phone.label)\n")
  }

  @Test func unpairing_removes_only_the_phone_line() {
    let phone = device()
    let text = PairedDevice.replacing(phone.id, in: mac + "owner OLD \(phone.label)\n", with: nil)
    #expect(text == mac)
  }

  @Test func a_file_without_a_final_newline_keeps_its_last_line() {
    let phone = device()
    let text = PairedDevice.replacing(phone.id, in: "owner MAC", with: "owner NEW \(phone.label)")
    #expect(text == "owner MAC\nowner NEW \(phone.label)\n")
  }

  @Test func a_phone_with_no_scope_gets_no_line_and_one_with_orders_alone_gets_one() {
    let phone = device()
    #expect(AllowedSigners.boardLine(phone, scope: []) == nil)
    #expect(
      AllowedSigners.boardLine(phone, scope: [.orders])!.hasPrefix(
        "owner namespaces=\"attention/order/v1\" ecdsa-sha2-nistp256 "))
  }

  @Test func the_line_names_approvals_and_orders_and_never_the_owners_write() {
    let phone = device()
    #expect(
      AllowedSigners.boardLine(phone, scope: Scope(rawValue: ~0))!.hasPrefix(
        "owner namespaces=\"board/approve/v1,attention/order/v1\" ecdsa-sha2-nistp256 "))
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
    let line = AllowedSigners.boardLine(phone, scope: [.orders])!
    #expect(try verify(key, line: line, namespace: orderNamespace) == 0)
    #expect(try verify(key, line: line, namespace: "board/approve/v1") != 0)
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
    #expect(
      throws: AllowedSignersFile.Refusal.writableByOthers(
        path: file.path, mode: 0o664, owner: "you")
    ) {
      try AllowedSignersFile.update(file, device: phone.id, line: "owner NEW \(phone.label)")
    }
    #expect(try String(contentsOf: file, encoding: .utf8) == mac)
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
    #expect(
      throws: AllowedSignersFile.Refusal.writableByOthers(
        path: target.path, mode: 0o666, owner: "you")
    ) {
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

  @Test func a_phone_paired_with_both_scopes_lists_once_with_both_from_its_one_line() {
    let phone = device()
    let board = mac + AllowedSigners.boardLine(phone, scope: .suggested)! + "\n"
    let listed = PairedDevice.list(board: board)
    #expect(listed.map(\.id) == [phone.id])
    #expect(listed.first?.scope == .suggested)
    #expect(listed.first?.x963 == phone.x963)
    #expect(listed.first?.fingerprint == phone.fingerprint)
    #expect(listed.first?.line == AllowedSigners.boardLine(phone, scope: .suggested))
  }

  @Test func a_phone_whose_line_names_orders_alone_may_sign_orders_only() {
    let phone = device()
    let board = mac + AllowedSigners.boardLine(phone, scope: [.orders])! + "\n"
    #expect(PairedDevice.list(board: board).first?.scope == [.orders])
  }

  @Test func a_line_whose_namespaces_do_not_name_the_scope_grants_nothing() {
    let phone = device()
    let line = openSSHPublicKey(x963: phone.x963, comment: phone.label)
    let listed = PairedDevice.list(board: "owner namespaces=\"git\" \(line)\n")
    #expect(listed.first?.scope == [])
  }

  @Test func the_mac_line_and_labels_that_are_not_uuids_are_not_devices() {
    let text = mac + "owner ecdsa-sha2-nistp256 AAAA board-app/device/not-a-uuid\n"
    #expect(PairedDevice.list(board: text).isEmpty)
  }

  @Test func a_line_with_a_trailing_space_is_listed_and_removed() {
    let phone = device()
    let board =
      mac + AllowedSigners.boardLine(phone, scope: .suggested)! + "\n"
      + "owner AAAA \(phone.label) \n"
    let listed = PairedDevice.list(board: board)
    #expect(listed.count == 1)
    #expect(PairedDevice.removing(phone.id, keyedIn: [board], from: board) == mac)
  }

  @Test func every_line_ssh_keygen_would_read_as_the_phone_is_removed() {
    let phone = device()
    let line = AllowedSigners.boardLine(phone, scope: .suggested)!
    let key = openSSHPublicKey(x963: phone.x963, comment: "")
    for variant in [
      line + "\r", line + " ", line + "\t",
      line.replacingOccurrences(of: " \(phone.label)", with: "\t\(phone.label)"),
      line + " trailing words",
    ] {
      let text = mac + variant + "\n"
      #expect(PairedDevice.list(board: text).map(\.id) == [phone.id], "\(variant)")
      #expect(PairedDevice.removing(phone.id, keyedIn: [text], from: text) == mac, "\(variant)")
    }
    // A copy of the key goes too, found by the key wherever it sits.
    let blob = String(key.split(separator: " ")[1])
    for copy in [
      "owner \(key)copied by hand", "ssh-x,owner \(blob)",
      "ecdsa-a,owner namespaces=\"board/approve/v1\" \(blob)",
      "owner namespaces=\"board/approve/v1, ssh-y\" \(blob)",
    ] {
      let text = mac + line + "\n" + copy + "\n"
      #expect(PairedDevice.removing(phone.id, keyedIn: [text], from: text) == mac, "\(copy)")
    }
    // Copies OpenSSH reads but Swift splits differently go too: space
    // characters inside the base64, a combining mark after the key, and a
    // NUL that ends the line for OpenSSH.
    let half = blob.index(blob.startIndex, offsetBy: 40)
    for copy in [
      "owner ecdsa-sha2-nistp256 \(blob[..<half])\u{0B}\(blob[half...])",
      "owner ecdsa-sha2-nistp256 \(blob[..<half])\u{0C}\(blob[half...])",
      "owner ecdsa-sha2-nistp256 \(blob) \u{0301}", "owner ecdsa-sha2-nistp256 \(blob)\u{0}junk",
    ] {
      let text = mac + line + "\n" + copy + "\n"
      #expect(PairedDevice.removing(phone.id, keyedIn: [text], from: text) == mac, "\(copy)")
    }
    // The label in lower case names the same phone.
    let lower = mac + line.replacingOccurrences(of: phone.id, with: phone.id.lowercased()) + "\n"
    #expect(PairedDevice.list(board: lower).map(\.id) == [phone.id])
    #expect(PairedDevice.removing(phone.id, keyedIn: [lower], from: lower) == mac)
  }

  @Test func a_comment_naming_a_phone_is_neither_listed_nor_removed() {
    let phone = device()
    let text = mac + "# owner AAAA \(phone.label)\n"
    #expect(PairedDevice.list(board: text).isEmpty)
    #expect(PairedDevice.removing(phone.id, keyedIn: [text], from: text) == text)
  }

  @Test func a_key_that_does_not_read_leaves_no_fingerprint() {
    let id = UUID().uuidString
    let listed = PairedDevice.list(
      board: "owner ecdsa-sha2-nistp256 AAAA board-app/device/\(id)\n")
    #expect(listed.first?.fingerprint == nil)
  }

  @Test func a_device_without_a_stored_name_is_named_by_its_id() {
    let listed = PairedDevice.list(
      board: "owner AAAA board-app/device/32939622-2420-45C9-B0B9-060CB36DDED6\n")
    #expect(listed.first?.fallbackName == "iPhone 32939622")
  }

  @Test func namespaces_are_read_from_the_option() {
    #expect(
      PairedDevice.namespaces("owner namespaces=\"a/v1,b/v1\" ecdsa-sha2-nistp256 AAAA x")
        == ["a/v1", "b/v1"])
    #expect(PairedDevice.namespaces("owner ecdsa-sha2-nistp256 AAAA x") == [])
  }
}

struct RemovalTests {
  let mac = "owner ecdsa-sha2-nistp256 AAAAmac attention\n"

  @Test func removing_a_phone_deletes_its_line_from_both_files_and_keeps_the_rest() throws {
    let phone = device()
    let other = device()
    let board = try temporary(
      "board", mac + "owner A \(phone.label)\nowner B \(other.label)\n")
    let attention = try temporary("attention", mac + "owner C \(phone.label)\n")
    try AllowedSignersFile.remove(device: phone.id, from: [board, attention])
    #expect(try String(contentsOf: board, encoding: .utf8) == mac + "owner B \(other.label)\n")
    #expect(try String(contentsOf: attention, encoding: .utf8) == mac)
  }

  @Test func a_refused_file_does_not_stop_the_removal_from_the_other() throws {
    let phone = device()
    let board = try temporary("board", mac + "owner A \(phone.label)\n")
    let attention = try temporary("attention", mac + "owner C \(phone.label)\n")
    try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: board.path)
    #expect {
      try AllowedSignersFile.remove(device: phone.id, from: [board, attention])
    } throws: { error in
      (error as? AllowedSignersFile.RemovalFailed)?.failures.map(\.file) == [board]
    }
    #expect(try String(contentsOf: board, encoding: .utf8).contains(phone.label))
    #expect(try String(contentsOf: attention, encoding: .utf8) == mac)
  }

  @Test func a_missing_file_is_left_missing() throws {
    let phone = device()
    let missing = try directory().appendingPathComponent("absent")
    try AllowedSignersFile.remove(device: phone.id, from: [missing])
    #expect(!FileManager.default.fileExists(atPath: missing.path))
  }

  @Test func an_id_that_is_not_a_uuid_removes_nothing() throws {
    let text = mac + "owner A board-app/device/\n"
    let board = try temporary("board", text)
    #expect(throws: AllowedSignersFile.RemovalFailed.self) {
      try AllowedSignersFile.remove(device: "", from: [board])
    }
    #expect(try String(contentsOf: board, encoding: .utf8) == text)
  }
}

struct RemovalByKeyTests {
  let mac = "owner ecdsa-sha2-nistp256 AAAAmac attention\n"

  @Test func a_key_labelled_in_one_file_is_removed_from_the_other_under_any_comment() throws {
    let phone = device()
    let board = try temporary(
      "board", mac + AllowedSigners.boardLine(phone, scope: .suggested)! + "\n")
    let unlabelled = "owner " + openSSHPublicKey(x963: phone.x963, comment: "old")
    let attention = try temporary("attention", mac + unlabelled + "\n")
    try AllowedSignersFile.remove(device: phone.id, from: [board, attention])
    #expect(try String(contentsOf: board, encoding: .utf8) == mac)
    #expect(try String(contentsOf: attention, encoding: .utf8) == mac)
  }

  @Test func a_rewrite_keeps_the_files_mode() throws {
    let phone = device()
    let board = try temporary("board", mac + "owner A \(phone.label)\n")
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: board.path)
    try AllowedSignersFile.remove(device: phone.id, from: [board])
    let mode = try FileManager.default.attributesOfItem(atPath: board.path)[.posixPermissions]
    #expect((mode as? NSNumber)?.intValue == 0o600)
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: board.deletingLastPathComponent().path)
        == ["board"])
  }

  @Test func pairing_again_replaces_a_hand_edited_line_of_the_same_phone() throws {
    let phone = device()
    let board = try temporary("board", mac + "owner OLD \(phone.label)\r\n")
    try AllowedSignersFile.update(board, device: phone.id, line: "owner NEW \(phone.label)")
    #expect(try String(contentsOf: board, encoding: .utf8) == mac + "owner NEW \(phone.label)\n")
  }
}

/// This Mac's own line in Board's file, which the install sheet writes.
struct OwnLineTests {
  let phone = device()
  let macKey = key().x963Representation
  var line: String { AllowedSigners.macLine(x963: macKey, comment: "board") }
  var phoneLine: String { AllowedSigners.boardLine(phone, scope: .suggested)! }
  let otherMac = "owner " + openSSHPublicKey(x963: key().x963Representation, comment: "other")

  @Test func a_missing_file_is_made_with_the_line_and_mode_644() throws {
    let file = try directory().appendingPathComponent("config/board/allowed_signers")
    let kept = try AllowedSignersFile.setOwn(file, key: macKey, line: line)
    #expect(try String(contentsOf: file, encoding: .utf8) == line + "\n")
    #expect(try mode(file) == 0o644)
    #expect(kept == MacLine.Kept(phones: 0, others: 0))
  }

  @Test func the_line_is_added_and_every_other_line_kept_byte_for_byte() throws {
    let before = "# my keys\r\n\(otherMac)\r\n\n\(phoneLine)"
    let file = try temporary("allowed_signers", before)
    let kept = try AllowedSignersFile.setOwn(file, key: macKey, line: line)
    #expect(try String(contentsOf: file, encoding: .utf8) == before + "\n" + line + "\n")
    #expect(kept == MacLine.Kept(phones: 1, others: 1))
  }

  @Test func a_line_with_the_same_key_is_replaced_where_it_stood() throws {
    let older =
      "owner namespaces=\"board/approve/v1,board/write/v1\" "
      + openSSHPublicKey(x963: macKey, comment: "attention")
    let file = try temporary("allowed_signers", "\(otherMac)\n\(older)\n\(phoneLine)\n")
    try AllowedSignersFile.setOwn(file, key: macKey, line: line)
    #expect(
      try String(contentsOf: file, encoding: .utf8) == "\(otherMac)\n\(line)\n\(phoneLine)\n")
  }

  @Test func every_line_with_the_same_key_goes_and_the_line_is_written_once() throws {
    let copy = "owner " + openSSHPublicKey(x963: macKey, comment: "copy")
    let file = try temporary("allowed_signers", "\(copy)\n\(otherMac)\n\(copy)\n")
    try AllowedSignersFile.setOwn(file, key: macKey, line: line)
    #expect(try String(contentsOf: file, encoding: .utf8) == "\(line)\n\(otherMac)\n")
  }

  @Test func an_existing_file_keeps_its_mode() throws {
    let file = try temporary("allowed_signers", otherMac + "\n")
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    try AllowedSignersFile.setOwn(file, key: macKey, line: line)
    #expect(try mode(file) == 0o600)
  }

  @Test func a_group_writable_file_is_refused_and_left_as_it_was() throws {
    let file = try temporary("allowed_signers", otherMac + "\n")
    try FileManager.default.setAttributes([.posixPermissions: 0o664], ofItemAtPath: file.path)
    #expect(
      throws: AllowedSignersFile.Refusal.writableByOthers(
        path: file.path, mode: 0o664, owner: "you")
    ) {
      try AllowedSignersFile.setOwn(file, key: macKey, line: line)
    }
    #expect(try String(contentsOf: file, encoding: .utf8) == otherMac + "\n")
    #expect(try mode(file) == 0o664)
  }

  @Test func another_users_file_is_refused() {
    #expect(
      AllowedSignersFile.refusal(
        path: "/f", mode: 0o644, ownerID: getuid() + 1, ownerName: "ana", user: getuid())
        == .ownedByAnother(path: "/f", mode: 0o644, owner: "ana"))
    #expect(
      AllowedSignersFile.refusal(
        path: "/f", mode: 0o644, ownerID: 0, ownerName: "root", user: getuid()) == nil)
    #expect(
      AllowedSignersFile.refusal(
        path: "/f", mode: 0o644, ownerID: getuid(), ownerName: "me", user: getuid()) == nil)
  }

  @Test func a_file_reached_through_a_symlink_is_written_and_the_link_kept() throws {
    let target = try temporary("allowed_signers", otherMac + "\n")
    let link = try directory().appendingPathComponent("allowed_signers")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    try AllowedSignersFile.setOwn(link, key: macKey, line: line)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
    #expect(try String(contentsOf: target, encoding: .utf8) == "\(otherMac)\n\(line)\n")
  }

  @Test func ssh_keygen_admits_an_order_signed_by_the_mac_after_the_write() throws {
    let signer = P256.Signing.PrivateKey()
    let x963 = signer.publicKey.x963Representation
    let file = try temporary("allowed_signers", otherMac + "\n")
    try AllowedSignersFile.setOwn(
      file, key: x963, line: AllowedSigners.macLine(x963: x963, comment: "board"))
    let message = Data("statement\n".utf8)
    let armor = try sign(message: message, x963: x963, namespace: orderNamespace) {
      try signer.signature(for: $0).rawRepresentation
    }
    let signature = try temporary("statement.sig", armor)
    let status = try run(
      "/usr/bin/ssh-keygen",
      ["-Y", "verify", "-f", file.path, "-I", "owner", "-n", orderNamespace, "-s", signature.path],
      input: message
    ).status
    #expect(status == 0)
  }

  private func mode(_ file: URL) throws -> Int {
    (try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber)
      .intValue
  }
}

struct RefusalTests {
  @Test func a_writable_file_names_its_mode_owner_the_chmod_and_asks_to_read_its_lines() {
    let refusal = AllowedSignersFile.Refusal.writableByOthers(
      path: "/Users/ana/.config/board/allowed_signers", mode: 0o666, owner: "you")
    #expect(
      refusal.errorDescription
        == "/Users/ana/.config/board/allowed_signers has mode 666, owned by you, so other users can write to it and Board will not trust it. Read its lines first: each line should be a key you added. Then run chmod 644 /Users/ana/.config/board/allowed_signers."
    )
    #expect(refusal.summary == "mode 666 · owned by you · needs 644 or stricter")
  }

  @Test func another_users_file_names_its_owner_and_asks_to_read_its_lines() {
    let refusal = AllowedSignersFile.Refusal.ownedByAnother(
      path: "/f", mode: 0o644, owner: "bob")
    #expect(
      refusal.errorDescription
        == "/f has mode 644, owned by bob, so another user can write to it and Board will not trust it. Read its lines first: each line should be a key you added. Then make it yours with sudo chown $USER /f and run chmod 644 /f."
    )
    #expect(refusal.summary == "mode 644 · owned by bob · needs to be yours, 644 or stricter")
  }
}

struct MacLineTests {
  let macKey = key().x963Representation
  var line: String { AllowedSigners.macLine(x963: macKey, comment: "board") }
  let otherMac = "owner " + openSSHPublicKey(x963: key().x963Representation, comment: "other")

  @Test func a_file_without_the_key_is_missing_the_line() {
    #expect(MacLine.status(of: line, in: "") == .missing)
    #expect(MacLine.status(of: line, in: otherMac + "\n") == .missing)
    #expect(MacLine.status(of: line, in: "# \(line)\n") == .missing)
  }

  @Test func a_line_of_the_key_without_the_order_namespace_is_outdated() {
    let older =
      "owner namespaces=\"board/approve/v1,board/write/v1\" "
      + openSSHPublicKey(x963: macKey, comment: "attention")
    #expect(MacLine.status(of: line, in: "\(otherMac)\n\(older)\n") == .outdated)
  }

  @Test func the_exact_line_is_current() {
    #expect(MacLine.status(of: line, in: "\(otherMac)\n\(line)\n") == .current)
    #expect(MacLine.status(of: line, in: "\(line)\r\n") == .current)
    #expect(MacLine.status(of: line, in: line) == .current)
  }

  @Test func the_kept_lines_count_phones_and_other_keys_but_not_this_macs_own() {
    let phone = AllowedSigners.boardLine(device(), scope: .suggested)!
    let text = "# keys\n\n\(otherMac)\n\(phone)\n\(line)\n"
    #expect(MacLine.kept(in: text, key: macKey) == MacLine.Kept(phones: 1, others: 1))
  }

  @Test func the_kept_lines_read_as_the_sheet_says_them() {
    #expect(MacLine.Kept(phones: 0, others: 0).sentence == "Keeps no other lines")
    #expect(
      MacLine.Kept(phones: 1, others: 1).sentence == "Keeps 2 other lines: 1 iPhone, 1 other Mac")
    #expect(MacLine.Kept(phones: 2, others: 0).sentence == "Keeps 2 other lines: 2 iPhones")
    #expect(MacLine.Kept(phones: 0, others: 3).sentence == "Keeps 3 other lines: 3 other Macs")
    #expect(MacLine.Kept(phones: 1, others: 0).sentence == "Keeps 1 other line: 1 iPhone")
  }

  @Test func the_lines_a_write_kept_read_as_the_written_sheet_says_them() {
    #expect(MacLine.Kept(phones: 1, others: 1).past == "Kept 2 other lines")
    #expect(MacLine.Kept(phones: 0, others: 1).past == "Kept 1 other line")
    #expect(MacLine.Kept(phones: 0, others: 0).past == "Kept no other lines")
  }

  @Test func the_key_is_read_from_the_line() {
    #expect(MacLine.key(of: line) == macKey)
    #expect(MacLine.key(of: "not a line") == nil)
  }
}
