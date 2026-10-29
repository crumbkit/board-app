// A Board pending effect and the statement the owner signs to approve it. The
// statement must equal board's `Effect::approval` byte for byte, or Board
// refuses the signature; Tests/SSHSigTests/EffectTests.swift pins it.
import CryptoKit
import Foundation

/// A `board/effect/v1` record: a request a plugin made, waiting for the owner.
public struct Effect: Equatable, Sendable {
  /// The root of the board the effect targets.
  public let board: String
  public let plugin: String
  public let op: String
  public let path: String
  /// `sha256:` and 64 lowercase hex digits: what a put writes.
  public let digest: String?
  /// The git blob a put replaces, in hex, or nil for a new file.
  public let prior: String?
  public let record: JSONValue?
  public let text: String?

  public struct Malformed: Error, Equatable {
    public let field: String
  }

  /// The effect in `json`, or `Malformed` naming the first field Board would
  /// refuse. Unknown fields are refused, as Board refuses them.
  public init(json: Data) throws {
    guard case .object(let members) = try JSONValue.parse(json) else {
      throw Malformed(field: "$type")
    }
    let known = ["$type", "board", "plugin", "op", "path", "digest", "prior", "record", "text"]
    if let unknown = members.first(where: { member in
      !known.contains { $0.utf8.elementsEqual(member.key.utf8) }
    }) {
      throw Malformed(field: unknown.key)
    }
    let object = JSONValue.object(members)
    func required(_ key: String) throws -> String {
      guard let text = object[key]?.string else { throw Malformed(field: key) }
      return text
    }
    func optional(_ key: String) throws -> String? {
      switch object[key] {
      case nil, .null?: return nil
      case .string(let text)?: return text
      default: throw Malformed(field: key)
      }
    }
    guard try required("$type") == "board/effect/v1" else { throw Malformed(field: "$type") }
    board = try required("board")
    plugin = try required("plugin")
    op = try required("op")
    path = try required("path")
    prior = try optional("prior")
    text = try optional("text")
    record = object["record"].flatMap { $0 == .null ? nil : $0 }
    if let digest = try optional("digest") {
      let hex = digest.dropFirst("sha256:".count)
      guard digest.hasPrefix("sha256:"), hex.utf8.count == 64, hex.utf8.allSatisfy(isASCIIHex)
      else {
        throw Malformed(field: "digest")
      }
      self.digest = "sha256:" + hex.lowercased()
    } else {
      digest = nil
    }
  }

  /// The SHA-256 of the canonical JSON of the request, in hex: its board,
  /// plugin, op, path, digest and prior. An answer is filed under this id.
  public var id: String {
    let request = JSONValue.object([
      ("board", .string(board)), ("plugin", .string(plugin)), ("op", .string(op)),
      ("path", .string(path)), ("digest", digest.map(JSONValue.string) ?? .null),
      ("prior", prior.map(JSONValue.string) ?? .null),
    ])
    return SHA256.hash(data: Data((request.pretty + "\n").utf8))
      .map { String(format: "%02x", $0) }.joined()
  }

  /// What a put writes, as the statement shows it before escaping: the record
  /// pretty-printed with its keys sorted, or the text. Nil for a plain action.
  public var content: String? {
    record?.pretty ?? text
  }

  /// The exact statement the owner signs to approve this effect, which Board
  /// rebuilds and checks the signature against.
  public var approval: String {
    var statement =
      "board/approve/v1\neffect: \(id)\nplugin: \(shown(plugin))\nop: \(shown(op))\n"
      + "path: \(shown(path))\nboard: \(shown(board))\n"
    if let content {
      let lines = content.utf8.split(
        separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
      statement += "content: \(content.utf8.count) bytes in \(lines.count) lines\n"
      for line in lines { statement += shown(String(decoding: line, as: UTF8.self)) + "\n" }
    }
    return statement
  }
}

/// The id git gives `bytes` as a blob: the SHA-1 of `blob <size>\0` and the
/// bytes, in hex. The phone checks a prior blob the Mac shares against it.
public func gitBlobID(_ bytes: Data) -> String {
  Insecure.SHA1.hash(data: Data("blob \(bytes.count)\0".utf8) + bytes)
    .map { String(format: "%02x", $0) }.joined()
}

/// `text` with each character that could hide or reorder what it says escaped
/// as Rust's `char::escape_default` writes it: the controls, format characters
/// and line and paragraph separators, and the Hangul fillers, but not the
/// zero-width joiner and non-joiner.
public func shown(_ text: String) -> String {
  var out = ""
  for scalar in text.unicodeScalars {
    guard hidden(scalar) else {
      out.unicodeScalars.append(scalar)
      continue
    }
    switch scalar {
    case "\t": out += "\\t"
    case "\r": out += "\\r"
    case "\n": out += "\\n"
    default: out += "\\u{" + String(scalar.value, radix: 16) + "}"
    }
  }
  return out
}

private func hidden(_ scalar: Unicode.Scalar) -> Bool {
  switch scalar.value {
  case 0x200C, 0x200D: return false
  case 0x115F, 0x1160, 0x3164, 0xFFA0: return true
  default:
    return [.control, .format, .lineSeparator, .paragraphSeparator].contains(
      scalar.properties.generalCategory)
  }
}
