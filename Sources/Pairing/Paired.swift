// The devices the two allowed signers files admit, read back from the lines
// pairing wrote, so the Mac window can list each phone and what it may sign.
import Foundation
import SSHSig

/// A paired device as the two allowed signers files list it: the lines that
/// end in its label.
public struct PairedDevice: Identifiable, Equatable, Sendable {
  public let id: String
  /// Its key from the first of its lines whose key reads as P-256, or nil.
  public let x963: Data?
  /// What its lines admit: approvals when its line in Board's file names the
  /// approval namespace, orders when its line in attention's names the order
  /// namespace.
  public let scope: Scope
  /// Its line in Board's file, or nil.
  public let boardLine: String?
  /// Its line in attention's file, or nil.
  public let attentionLine: String?

  /// `SHA256:…`, or nil when no line's key reads.
  public var fingerprint: String? { x963.map(Device.fingerprint(x963:)) }

  /// The name shown for a device paired before the Mac kept names:
  /// "iPhone" and the first 8 characters of its id.
  public var fallbackName: String { "iPhone \(id.prefix(8))" }

  /// Every device with a line in either file, in the order Board's file and
  /// then attention's lists them. A line counts only when its last field is
  /// a device label whose id is a UUID.
  public static func list(board: String, attention: String) -> [PairedDevice] {
    let boardLines = deviceLines(board)
    let attentionLines = deviceLines(attention)
    var ids: [String] = []
    for (id, _) in boardLines + attentionLines where !ids.contains(id) { ids.append(id) }
    return ids.map { id in
      let boardLine = boardLines.first { $0.id == id }?.line
      let attentionLine = attentionLines.first { $0.id == id }?.line
      var scope: Scope = []
      if let boardLine, namespaces(boardLine).contains(approvalNamespace) {
        scope.insert(.approvals)
      }
      if let attentionLine, namespaces(attentionLine).contains(orderNamespace) {
        scope.insert(.orders)
      }
      return PairedDevice(
        id: id, x963: [boardLine, attentionLine].lazy.compactMap { $0.flatMap(key) }.first,
        scope: scope, boardLine: boardLine, attentionLine: attentionLine)
    }
  }

  /// The namespaces a line's `namespaces="…"` option lists, or none.
  public static func namespaces(_ line: String) -> [String] {
    guard let match = line.firstMatch(of: /namespaces="([^"]*)"/) else { return [] }
    return match.1.split(separator: ",").map(String.init)
  }

  /// Each line that ends in a space and a device label, with the label's id:
  /// the lines `AllowedSigners.replacing` finds for that id.
  private static func deviceLines(_ text: String) -> [(id: String, line: String)] {
    text.split(separator: "\n").compactMap { line in
      let fields = line.split(separator: " ", omittingEmptySubsequences: false)
      guard fields.count > 1, let last = fields.last, last.hasPrefix(Device.labelPrefix)
      else { return nil }
      let id = String(last.dropFirst(Device.labelPrefix.count))
      guard UUID(uuidString: id)?.uuidString == id.uppercased() else { return nil }
      return (id, String(line))
    }
  }

  /// The key a line names, when it is an OpenSSH P-256 key.
  private static func key(_ line: String) -> Data? {
    let fields = line.split(separator: " ")
    guard let type = fields.firstIndex(of: "ecdsa-sha2-nistp256"), type + 1 < fields.count,
      let blob = Data(base64Encoded: String(fields[type + 1])), blob.count > 65
    else { return nil }
    let x963 = Data(blob.suffix(65))
    return publicKeyBlob(x963: x963) == blob ? x963 : nil
  }
}
