// What pairing a phone with a Mac decides: the code both screens show, and the
// line Board's allowed signers file gains for the phone's key.
import CryptoKit
import Foundation
import SSHSig

/// What a paired device may sign, chosen on the Mac at pairing.
public struct Scope: OptionSet, Codable, Hashable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  /// Pending effects a plugin asked for, signed in the approval namespace.
  public static let approvals = Scope(rawValue: 1 << 0)
  /// Orders, signed in the order namespace.
  public static let orders = Scope(rawValue: 1 << 1)

  /// What the pairing sheet ticks before the owner changes anything.
  public static let suggested: Scope = [.approvals, .orders]
}

/// A phone or tablet that asked to pair, named by an id it chose.
public struct Device: Equatable, Sendable {
  public let id: String
  public let name: String
  public let x963: Data

  public init(id: String, name: String, x963: Data) {
    self.id = id
    self.name = name
    self.x963 = x963
  }

  /// The comment that ends the device's line in an allowed signers file, so a
  /// later pairing finds and replaces that line alone.
  public var label: String { Device.labelPrefix + id }

  /// What every paired device's label starts with.
  public static let labelPrefix = "board-app/device/"

  /// `SHA256:…`, as OpenSSH prints a fingerprint.
  public var fingerprint: String { Device.fingerprint(x963: x963) }

  public static func fingerprint(x963: Data) -> String {
    let digest = Data(SHA256.hash(data: publicKeyBlob(x963: x963))).base64EncodedString()
    return "SHA256:" + digest.replacingOccurrences(of: "=", with: "")
  }
}

/// The six digits both screens show, from the phone's key, the phone's nonce
/// and the Mac's nonce. The phone commits to its key and nonce before it sees
/// the Mac's nonce, so a device that swaps in its own key cannot search for
/// one that shows the same digits: it guesses once, with odds of one in a
/// million.
public enum PairingCode {
  /// What the phone publishes first: a hash of the key and nonce it will reveal.
  public static func commitment(x963: Data, phoneNonce: Data) -> Data {
    Data(SHA256.hash(data: Data("board-app/commit/v1".utf8) + x963 + phoneNonce))
  }

  /// Whether a revealed key and nonce are the ones the phone committed to.
  public static func reveals(_ commitment: Data, x963: Data, phoneNonce: Data) -> Bool {
    Self.commitment(x963: x963, phoneNonce: phoneNonce) == commitment
  }

  public static func code(x963: Data, phoneNonce: Data, macNonce: Data) -> String {
    let digest = Array(
      SHA256.hash(data: Data("board-app/pair/v2".utf8) + x963 + phoneNonce + macNonce))
    let number = digest.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) } % 1_000_000
    let digits = unsafe String(format: "%06u", number)
    return "\(digits.prefix(3)) \(digits.suffix(3))"
  }
}

/// The phone's proof that it holds the key it revealed: a signature, made with
/// Face ID or Touch ID, of the pairing's key and both nonces.
public enum PairingProof {
  public static func transcript(x963: Data, phoneNonce: Data, macNonce: Data) -> Data {
    Data("board-app/proof/v1".utf8) + x963 + phoneNonce + macNonce
  }

  /// Whether `proof`, a raw r‖s P-256 signature, is the revealed key's
  /// signature of this pairing's transcript.
  public static func verifies(_ proof: Data, x963: Data, phoneNonce: Data, macNonce: Data) -> Bool {
    guard let key = try? P256.Signing.PublicKey(x963Representation: x963),
      let signature = try? P256.Signing.ECDSASignature(rawRepresentation: proof)
    else { return false }
    return key.isValidSignature(
      signature, for: transcript(x963: x963, phoneNonce: phoneNonce, macNonce: macNonce))
  }
}

/// What the Mac fixed when it sent a phone its challenge. Everything the phone
/// sends later is checked against this, never against the request as it is
/// read again from iCloud, which anyone who can write the zone may rewrite.
public struct Challenge: Equatable, Sendable {
  public let deviceID: String
  public let name: String
  public let commitment: Data
  public let created: Date
  public let macNonce: Data

  /// Nil when `deviceID` is not a UUID, so an id can never carry a newline or
  /// a space into an allowed signers line.
  public init?(deviceID: String, name: String, commitment: Data, created: Date, macNonce: Data) {
    guard UUID(uuidString: deviceID)?.uuidString == deviceID.uppercased() else { return nil }
    self.deviceID = deviceID
    self.name = name
    self.commitment = commitment
    self.created = created
    self.macNonce = macNonce
  }

  public enum Outcome: Equatable, Sendable {
    /// The phone has not revealed its key yet.
    case waiting
    /// The reveal matches the pinned commitment and its proof verifies.
    case offer(Device, code: String)
    /// The request changed since the challenge, or the reveal or proof is wrong.
    case refused
  }

  public func check(_ reveal: Reveal) -> Outcome {
    guard reveal.name == name, reveal.commitment == commitment, reveal.created == created else {
      return .refused
    }
    guard let x963 = reveal.x963, let phoneNonce = reveal.phoneNonce, let proof = reveal.proof
    else { return reveal.x963 == nil && reveal.phoneNonce == nil ? .waiting : .refused }
    guard PairingCode.reveals(commitment, x963: x963, phoneNonce: phoneNonce),
      PairingProof.verifies(proof, x963: x963, phoneNonce: phoneNonce, macNonce: macNonce)
    else { return .refused }
    return .offer(
      Device(id: deviceID, name: name, x963: x963),
      code: PairingCode.code(x963: x963, phoneNonce: phoneNonce, macNonce: macNonce))
  }
}

/// A phone's request as the Mac reads it after the challenge.
public struct Reveal: Sendable {
  public var name: String
  public var commitment: Data
  public var created: Date
  public var x963: Data?
  public var phoneNonce: Data?
  public var proof: Data?

  public init(
    name: String, commitment: Data, created: Date, x963: Data?, phoneNonce: Data?, proof: Data?
  ) {
    self.name = name
    self.commitment = commitment
    self.created = created
    self.x963 = x963
    self.phoneNonce = phoneNonce
    self.proof = proof
  }
}

/// A paired device's line, built by `SSHSig`'s `AllowedSigners` from the
/// device's key and label and the scope the owner chose.
extension AllowedSigners {
  /// The device's one line for Board's file, naming the approval namespace,
  /// the order namespace or both, or nil when it may sign nothing.
  public static func boardLine(_ device: Device, scope: Scope) -> String? {
    deviceBoardLine(
      x963: device.x963, label: device.label, approves: scope.contains(.approvals),
      signsOrders: scope.contains(.orders))
  }
}

/// One allowed signers file on disk, held to the rules Board applies to it.
public enum AllowedSignersFile {
  /// A file Board would not trust, with its path, its permission bits and
  /// its owner: "you" for the user, or the owner's account name.
  public enum Refusal: LocalizedError, Equatable {
    /// Board refuses a file that group or others may write.
    case writableByOthers(path: String, mode: Int, owner: String)
    /// Board refuses a file that neither the user nor root owns.
    case ownedByAnother(path: String, mode: Int, owner: String)

    public var path: String {
      switch self {
      case .writableByOthers(let path, _, _), .ownedByAnother(let path, _, _): path
      }
    }

    /// The refusal, which asks the owner to read the file's lines before
    /// fixing its permissions, since another program may have added a line.
    public var errorDescription: String? {
      let read = "Read its lines first: each line should be a key you added."
      switch self {
      case .writableByOthers(let path, let mode, let owner):
        return
          "\(path) has mode \(octal(mode)), owned by \(owner), so other users can write to it and Board will not trust it. \(read) Then run chmod 644 \(path)."
      case .ownedByAnother(let path, let mode, let owner):
        return
          "\(path) has mode \(octal(mode)), owned by \(owner), so another user can write to it and Board will not trust it. \(read) Then make it yours with sudo chown $USER \(path) and run chmod 644 \(path)."
      }
    }

    /// One line under the refusal, such as "mode 666 · owned by you · needs
    /// 644 or stricter".
    public var summary: String {
      switch self {
      case .writableByOthers(_, let mode, let owner):
        "mode \(octal(mode)) · owned by \(owner) · needs 644 or stricter"
      case .ownedByAnother(_, let mode, let owner):
        "mode \(octal(mode)) · owned by \(owner) · needs to be yours, 644 or stricter"
      }
    }

    private func octal(_ mode: Int) -> String { String(mode & 0o7777, radix: 8) }
  }

  /// Why Board would not trust a file with this mode and owner, or nil when
  /// it would. `user` is the account Board runs as; root may own the file.
  public static func refusal(
    path: String, mode: Int, ownerID: uid_t, ownerName: String?, user: uid_t
  ) -> Refusal? {
    let owner = ownerID == user ? "you" : ownerName ?? "user \(ownerID)"
    guard ownerID == user || ownerID == 0 else {
      return .ownedByAnother(path: path, mode: mode, owner: owner)
    }
    guard mode & 0o022 == 0 else {
      return .writableByOthers(path: path, mode: mode, owner: owner)
    }
    return nil
  }

  /// A removal that left the device's line in some files.
  public struct RemovalFailed: LocalizedError {
    /// Each file the line may still be in, and why it was not removed.
    public let failures: [(file: URL, error: any Error)]

    public var errorDescription: String? {
      failures.map { "\($0.file.path): \($0.error.localizedDescription)" }
        .joined(separator: " ")
    }
  }

  /// Removes every line that names the device from every file in `files`:
  /// a line with its label, and a line with the key of any labelled line,
  /// whatever its comment ([PairedDevice.removing]). It reads every file
  /// before it writes any, so a key found in one file is removed from all.
  /// It tries each file even when an earlier one fails, then throws
  /// RemovalFailed naming each file that failed. An id that is not a UUID
  /// removes nothing and throws.
  public static func remove(device id: String, from files: [URL]) throws {
    guard UUID(uuidString: id)?.uuidString == id.uppercased() else {
      throw RemovalFailed(failures: files.map { ($0, CocoaError(.fileWriteInvalidFileName)) })
    }
    var texts: [String] = []
    var failures: [(file: URL, error: any Error)] = []
    for file in files {
      do {
        texts.append(try read(file))
      } catch {
        failures.append((file, error))
      }
    }
    for file in files where !failures.contains(where: { $0.file == file }) {
      do {
        try rewrite(file) { PairedDevice.removing(id, keyedIn: texts, from: $0) }
      } catch {
        failures.append((file, error))
      }
    }
    if !failures.isEmpty { throw RemovalFailed(failures: failures) }
  }

  /// The file's text, or "" when it is missing.
  private static func read(_ file: URL) throws -> String {
    let target = file.resolvingSymlinksInPath()
    guard FileManager.default.fileExists(atPath: target.path) else { return "" }
    return try String(contentsOf: target, encoding: .utf8)
  }

  /// Replaces every line that names the device in `file` with `line`, or
  /// removes them when `line` is nil.
  public static func update(_ file: URL, device id: String, line: String?) throws {
    try rewrite(file) { PairedDevice.replacing(id, in: $0, with: line) }
  }

  /// Writes this Mac's own `line` to `file`: it replaces every line that
  /// holds `key`, where the first of them stood, or ends the file, and keeps
  /// every other line byte for byte. It returns the other lines it kept. A
  /// file Board would not trust is refused before anything is written.
  @discardableResult
  public static func setOwn(_ file: URL, key x963: Data, line: String) throws -> MacLine.Kept {
    var kept = MacLine.Kept(phones: 0, others: 0)
    try rewrite(file) { text in
      kept = MacLine.kept(in: text, key: x963)
      return MacLine.setting(line, key: x963, in: text)
    }
    return kept
  }

  /// Writes `change` of the file's text. A symlink is followed and kept. A
  /// missing file is made with mode 644; an existing one keeps its mode. The
  /// new text goes to a file beside it with that mode first, then replaces
  /// it in one rename, so no reader sees a partial file or a wider mode. A
  /// file that cannot be read is left as it was and the error is thrown, so
  /// a failed read never drops the other lines.
  private static func rewrite(_ file: URL, _ change: (String) -> String) throws {
    let manager = FileManager.default
    let target = file.resolvingSymlinksInPath()
    var existing = ""
    var mode = 0o644
    if (try? manager.destinationOfSymbolicLink(atPath: file.path)) != nil,
      !manager.fileExists(atPath: target.path)
    {
      throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: file.path])
    }
    if manager.fileExists(atPath: target.path) {
      let attributes = try manager.attributesOfItem(atPath: target.path)
      guard let read = (attributes[.posixPermissions] as? NSNumber)?.intValue else {
        throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: target.path])
      }
      mode = read
      guard let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value else {
        throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: target.path])
      }
      if let refusal = refusal(
        path: target.path, mode: mode, ownerID: owner,
        ownerName: attributes[.ownerAccountName] as? String, user: getuid())
      {
        throw refusal
      }
      existing = try String(contentsOf: target, encoding: .utf8)
    }
    let text = change(existing)
    guard text != existing else { return }
    let folder = target.deletingLastPathComponent()
    try manager.createDirectory(at: folder, withIntermediateDirectories: true)
    let temporary = folder.appendingPathComponent(
      ".\(target.lastPathComponent).\(UUID().uuidString)")
    // Made with the file's mode, refusing a link or an existing file there,
    // so no other user can open it before the rename.
    let descriptor = unsafe open(
      temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, mode_t(mode))
    guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    defer { try? manager.removeItem(at: temporary) }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    guard fchmod(descriptor, mode_t(mode)) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    try handle.write(contentsOf: Data(text.utf8))
    try handle.synchronize()
    try handle.close()
    guard unsafe rename(temporary.path, target.path) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }
}
