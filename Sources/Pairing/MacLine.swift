// This Mac's own line in Board's allowed signers file: whether the file has
// it, the file's text with it written, and the other lines the write keeps.
import Foundation

public enum MacLine {
  /// What Board's file holds for this Mac's key.
  public enum Status: Equatable, Sendable {
    /// No line holds the key.
    case missing
    /// A line holds the key but is not the line, such as one written before
    /// it named the order namespace.
    case outdated
    /// The file holds the line exactly.
    case current
  }

  /// The other lines a write keeps: phones' lines, which carry a device
  /// label, and every other key's, which the sheet calls other Macs.
  public struct Kept: Equatable, Sendable {
    public let phones: Int
    public let others: Int

    public init(phones: Int, others: Int) {
      self.phones = phones
      self.others = others
    }

    public var count: Int { phones + others }

    /// "Kept 2 other lines", once the line is written.
    public var past: String {
      count == 0 ? "Kept no other lines" : "Kept \(count) other line\(count == 1 ? "" : "s")"
    }

    /// "Keeps 2 other lines: 1 iPhone, 1 other Mac".
    public var sentence: String {
      guard count > 0 else { return "Keeps no other lines" }
      let parts = [
        phones > 0 ? "\(phones) iPhone\(phones == 1 ? "" : "s")" : nil,
        others > 0 ? "\(others) other Mac\(others == 1 ? "" : "s")" : nil,
      ].compactMap(\.self)
      return "Keeps \(count) other line\(count == 1 ? "" : "s"): \(parts.joined(separator: ", "))"
    }
  }

  /// The P-256 key `line` names, or nil.
  public static func key(of line: String) -> Data? { PairedDevice.keys(line).first }

  /// Whether `text` holds `line` exactly, holds another line with its key,
  /// or holds neither. A comment is not a line.
  public static func status(of line: String, in text: String) -> Status {
    let lines = raw(text).map(trimmed).filter { !PairedDevice.isComment($0) }
    if lines.contains(line) { return .current }
    guard let x963 = key(of: line) else { return .missing }
    let needle = PairedDevice.needle(x963)
    return lines.contains { PairedDevice.carries($0, needle) } ? .outdated : .missing
  }

  /// The lines of `text` other than comments, blank lines and those holding
  /// `key`.
  public static func kept(in text: String, key x963: Data) -> Kept {
    let needle = PairedDevice.needle(x963)
    let others = raw(text).map(trimmed).filter { line in
      !PairedDevice.isComment(line) && !PairedDevice.fields(line).isEmpty
        && !PairedDevice.carries(line, needle)
    }
    let phones = others.filter { PairedDevice.label(of: $0) != nil }.count
    return Kept(phones: phones, others: others.count - phones)
  }

  /// `text` with `line` in place of every line holding `key`, where the
  /// first of them stood, or at the end. Every other line, its ending among
  /// it, stays byte for byte.
  static func setting(_ line: String, key x963: Data, in text: String) -> String {
    let needle = PairedDevice.needle(x963)
    var written = ""
    var placed = false
    for raw in raw(text) {
      let body = trimmed(raw)
      guard !PairedDevice.isComment(body), PairedDevice.carries(body, needle) else {
        written += raw
        continue
      }
      if !placed { written += line + "\n" }
      placed = true
    }
    if !placed {
      if !written.isEmpty && !written.hasSuffix("\n") { written += "\n" }
      written += line + "\n"
    }
    return written
  }

  /// The lines of `text`, each with its own ending: LF, CRLF or none.
  private static func raw(_ text: String) -> [String] {
    var lines: [String] = []
    var start = text.utf8.startIndex
    for index in text.utf8.indices where text.utf8[index] == UInt8(ascii: "\n") {
      let next = text.utf8.index(after: index)
      lines.append(String(text[start..<next]))
      start = next
    }
    if start != text.utf8.endIndex { lines.append(String(text[start...])) }
    return lines
  }

  /// A line without its LF or CRLF ending.
  private static func trimmed(_ line: String) -> String {
    var line = Substring(line)
    if line.utf8.last == UInt8(ascii: "\n") { line = line.dropLast() }
    // "\r\n" is one Character, so dropLast above took both.
    if line.utf8.last == UInt8(ascii: "\r") { line = line.dropLast() }
    return String(line)
  }
}
