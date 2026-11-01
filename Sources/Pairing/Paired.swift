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
  /// then attention's lists them. A line counts when one of its fields is a
  /// device label whose id is a UUID; the id is read in upper case.
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

  /// `text` without every line that names the device: a line with its
  /// label as a field, and a line from which OpenSSH could read the key of
  /// such a line in `files`, whatever its comment, principals or options.
  /// Comments, blank lines and every other line stay as they were.
  public static func removing(_ id: String, keyedIn files: [String], from text: String) -> String {
    let id = id.uppercased()
    let labelled = files.flatMap { lines($0) }.filter { label(of: $0) == id }
    let needles = Set(labelled.flatMap(Self.keys)).map(needle)
    // A kept CRLF line is written back with LF alone, which OpenSSH reads
    // the same.
    var kept = split(text, keepingEmpty: true)
    if kept.last == "" { kept.removeLast() }
    kept.removeAll { line in
      guard !isComment(line) else { return false }
      return label(of: line) == id || needles.contains { carries(line, $0) }
    }
    return kept.isEmpty ? "" : kept.joined(separator: "\n") + "\n"
  }

  /// `text` with every line that names the device replaced by `line` at the
  /// end, or removed when it is nil, as pairing again writes it.
  public static func replacing(_ id: String, in text: String, with line: String?) -> String {
    let kept = removing(id, keyedIn: [text], from: text)
    return line.map { kept + $0 + "\n" } ?? kept
  }

  /// The bytes that OpenSSH's base64 reading of a key must contain: the
  /// key's base64 without its last two characters, which alone could be
  /// written another way.
  private static func needle(_ x963: Data) -> [UInt8] {
    Array(publicKeyBlob(x963: x963).base64EncodedString().utf8.dropLast(2))
  }

  /// Whether `needle` is in the line as OpenSSH reads it: as bytes, up to
  /// any NUL, with every ASCII space character removed, since OpenSSH skips
  /// them inside base64. A match may span the key and its neighbours; it
  /// then removes a line OpenSSH might not read, never keeps one it would.
  private static func carries(_ line: String, _ needle: [UInt8]) -> Bool {
    let spaces: Set<UInt8> = [9, 10, 11, 12, 13, 32]
    let bytes = line.utf8.prefix { $0 != 0 }.filter { !spaces.contains($0) }
    return bytes.firstRange(of: needle) != nil
  }

  /// A line's fields as OpenSSH splits them: on spaces, tabs and CR.
  private static func fields(_ line: String) -> [Substring] {
    line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" })
  }

  private static func isComment(_ line: String) -> Bool { fields(line).first?.first == "#" }

  private static func lines(_ text: String) -> [String] {
    split(text, keepingEmpty: false).filter { !isComment($0) }
  }

  /// The lines of `text`, ended by LF or CRLF. Swift reads CRLF as one
  /// character, so splitting on LF alone would join such lines.
  private static func split(_ text: String, keepingEmpty: Bool) -> [String] {
    text.split(
      omittingEmptySubsequences: !keepingEmpty, whereSeparator: { $0 == "\n" || $0 == "\r\n" }
    ).map(String.init)
  }

  /// The id of the first field that is a device label with a UUID id, or nil.
  private static func label(of line: String) -> String? {
    for field in fields(line) where field.hasPrefix(Device.labelPrefix) {
      let id = String(field.dropFirst(Device.labelPrefix.count))
      if let uuid = UUID(uuidString: id), uuid.uuidString == id.uppercased() {
        return uuid.uuidString
      }
    }
    return nil
  }

  /// Each line that names a device label, with the label's id.
  private static func deviceLines(_ text: String) -> [(id: String, line: String)] {
    lines(text).compactMap { line in label(of: line).map { ($0, line) } }
  }

  /// The X9.63 bytes of every field that is an OpenSSH P-256 key, wherever
  /// it sits in the line.
  private static func keys(_ line: String) -> [Data] {
    fields(line).compactMap { field in
      guard let blob = Data(base64Encoded: String(field)), blob.count > 65 else { return nil }
      let x963 = Data(blob.suffix(65))
      return publicKeyBlob(x963: x963) == blob ? x963 : nil
    }
  }

  /// The key a line names, when it is an OpenSSH P-256 key.
  private static func key(_ line: String) -> Data? { keys(line).first }
}
