// The SSH signature format (OpenSSH's PROTOCOL.sshsig) for a P-256 key, so
// `ssh-keygen -Y verify` checks what the Secure Enclave signs.
import CryptoKit
import Foundation

// The namespaces have package access: the apps reach one only through
// `Approval.namespace` or an `AllowedSigners` line, never by name.

/// The namespace every order signature carries. A signature made for another
/// namespace, such as git's, does not verify as an order.
package let orderNamespace = "attention/order/v1"

/// The namespace of a Board approval, so an approval and an order never
/// verify as each other.
package let approvalNamespace = "board/approve/v1"

/// The namespace of the owner's own write under `effects/`, so an approvals
/// key that may not make one cannot sign one.
package let writeNamespace = "board/write/v1"

/// What a Board statement asks the owner to approve, named by its first line.
public enum Approval: Equatable, Sendable {
  /// `board/approve/v1`: a pending effect a plugin asked for.
  case effect
  /// `board/write/v1`: the owner's own write under `effects/`.
  case write

  /// The kind of approval `statement` is, or nil when its first line names none.
  public init?(statement: String) {
    switch statement.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first {
    case "board/approve/v1": self = .effect
    case "board/write/v1": self = .write
    default: return nil
    }
  }

  /// The namespace the statement is signed in, which Board checks it against.
  public var namespace: String {
    switch self {
    case .effect: approvalNamespace
    case .write: writeNamespace
    }
  }

  /// The window's heading.
  public var title: String {
    switch self {
    case .effect: "Approve a pending effect"
    case .write: "Approve your own protected write"
    }
  }
}

private let keyType = "ecdsa-sha2-nistp256"
private let magic = Data("SSHSIG".utf8)

/// A P-256 public key as OpenSSH writes it, from its uncompressed X9.63 bytes.
public func publicKeyBlob(x963: Data) -> Data {
  string(Data(keyType.utf8)) + string(Data("nistp256".utf8)) + string(x963)
}

/// The `ecdsa-sha2-nistp256 AAAA… comment` line for an allowed signers file.
public func openSSHPublicKey(x963: Data, comment: String) -> String {
  "\(keyType) \(publicKeyBlob(x963: x963).base64EncodedString()) \(comment)"
}

/// The bytes the key signs for `message` in `namespace`.
public func signedData(message: Data, namespace: String) -> Data {
  let digest = Data(SHA512.hash(data: message))
  return magic + string(Data(namespace.utf8)) + string(Data()) + string(Data("sha512".utf8))
    + string(digest)
}

/// The armored signature, given the public key and the raw r‖s signature of `signedData`.
public func armored(x963: Data, rawSignature: Data, namespace: String) -> String {
  precondition(rawSignature.count == 64, "a P-256 signature is 64 bytes of r and s")
  let inner = mpint(rawSignature.prefix(32)) + mpint(rawSignature.suffix(32))
  let signature = string(Data(keyType.utf8)) + string(inner)
  var blob = magic + uint32(1) + string(publicKeyBlob(x963: x963))
  blob +=
    string(Data(namespace.utf8)) + string(Data()) + string(Data("sha512".utf8)) + string(signature)
  let base64 = blob.base64EncodedString()
  let lines = stride(from: 0, to: base64.count, by: 70).map { start in
    let from = base64.index(base64.startIndex, offsetBy: start)
    return String(
      base64[
        from..<(base64.index(from, offsetBy: 70, limitedBy: base64.endIndex) ?? base64.endIndex)])
  }
  return (["-----BEGIN SSH SIGNATURE-----"] + lines + ["-----END SSH SIGNATURE-----"]).joined(
    separator: "\n") + "\n"
}

/// Signs `message` with `sign`, which returns the raw r‖s P-256 signature of the bytes it is given.
public func sign(message: Data, x963: Data, namespace: String, with sign: (Data) throws -> Data)
  rethrows -> String
{
  armored(
    x963: x963, rawSignature: try sign(signedData(message: message, namespace: namespace)),
    namespace: namespace)
}

/// The X9.63 bytes of the P-256 key an armored signature names, or nil when
/// the text is not a P-256 SSH signature. It checks no signature: it says
/// which key claims to have signed, so a screen can name the device.
public func signingKey(armored: String) -> Data? {
  let lines = armored.split(whereSeparator: \.isNewline).map(String.init)
  guard lines.first == "-----BEGIN SSH SIGNATURE-----",
    lines.last == "-----END SSH SIGNATURE-----",
    let blob = Data(base64Encoded: lines.dropFirst().dropLast().joined())
  else { return nil }
  var reader = blob[...]
  guard reader.prefix(magic.count) == magic else { return nil }
  reader = reader.dropFirst(magic.count)
  guard reader.prefix(4) == uint32(1) else { return nil }
  reader = reader.dropFirst(4)
  guard var key = readString(&reader) else { return nil }
  guard readString(&key) == Data(keyType.utf8), readString(&key) == Data("nistp256".utf8),
    let x963 = readString(&key), key.isEmpty, x963.count == 65, x963.first == 4
  else { return nil }
  return x963
}

/// Reads one SSH string from the front of `bytes`, or nil when it runs short.
private func readString(_ bytes: inout Data) -> Data? {
  guard bytes.count >= 4 else { return nil }
  let length = bytes.prefix(4).reduce(0) { $0 << 8 | Int($1) }
  bytes = bytes.dropFirst(4)
  guard bytes.count >= length else { return nil }
  defer { bytes = bytes.dropFirst(length) }
  return Data(bytes.prefix(length))
}

private func uint32(_ value: UInt32) -> Data {
  withUnsafeBytes(of: value.bigEndian) { unsafe Data($0) }
}

private func string(_ bytes: Data) -> Data {
  uint32(UInt32(bytes.count)) + bytes
}

/// An SSH mpint: no leading zero bytes, and one zero byte when the top bit is set.
private func mpint(_ bytes: Data) -> Data {
  var trimmed = Data(bytes.drop { $0 == 0 })
  if let first = trimmed.first, first & 0x80 != 0 { trimmed.insert(0, at: 0) }
  return string(trimmed)
}
