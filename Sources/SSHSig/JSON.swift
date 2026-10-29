// JSON as Board reads and prints it, so a statement built here matches the
// bytes board's `Effect::approval` builds. Board prints JSON with
// `serde_json`: keys sorted by their UTF-8 bytes, two-space indentation, and
// numbers in serde_json's own form.
import Foundation

/// A JSON value. An object keeps its members as pairs, because Swift compares
/// strings by canonical equivalence and Board compares keys by their bytes:
/// `é` and `e` with a combining accent are two keys to Board.
public enum JSONValue: Equatable, Sendable {
  case null
  case bool(Bool)
  /// The number as serde_json prints it.
  case number(String)
  case string(String)
  case array([JSONValue])
  case object([(key: String, value: JSONValue)])

  public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
    switch (lhs, rhs) {
    case (.null, .null): true
    case (.bool(let a), .bool(let b)): a == b
    case (.number(let a), .number(let b)): a == b
    case (.string(let a), .string(let b)): Array(a.utf8) == Array(b.utf8)
    case (.array(let a), .array(let b)): a == b
    case (.object(let a), .object(let b)):
      a.count == b.count
        && zip(a, b).allSatisfy { Array($0.key.utf8) == Array($1.key.utf8) && $0.value == $1.value }
    default: false
    }
  }

  public struct Malformed: Error, Equatable {
    public let offset: Int
  }

  /// Parses one JSON document. A duplicate key, a number that no `Double`
  /// holds, and anything after the document are refused, as Board refuses
  /// them. A number Board refuses as lossy, such as `0.30000000000000001`, is
  /// read here; Board never commits one, so no effect holds one.
  public static func parse(_ data: Data) throws -> JSONValue {
    var parser = Parser(bytes: Array(data))
    let value = try parser.value(depth: 0)
    parser.skipSpace()
    guard parser.at == parser.bytes.count else { throw Malformed(offset: parser.at) }
    return value
  }

  /// The member named `key`, compared by bytes.
  public subscript(key: String) -> JSONValue? {
    guard case .object(let members) = self else { return nil }
    return members.first { Array($0.key.utf8) == Array(key.utf8) }?.value
  }

  public var string: String? {
    if case .string(let text) = self { text } else { nil }
  }

  /// The value as `serde_json::to_string_pretty` prints it, keys sorted.
  public var pretty: String {
    var out = ""
    write(to: &out, indent: "")
    return out
  }

  private func write(to out: inout String, indent: String) {
    switch self {
    case .null: out += "null"
    case .bool(let value): out += value ? "true" : "false"
    case .number(let text): out += text
    case .string(let text): out += JSONValue.quoted(text)
    case .array(let items):
      guard !items.isEmpty else {
        out += "[]"
        return
      }
      out += "[\n"
      for (index, item) in items.enumerated() {
        out += indent + "  "
        item.write(to: &out, indent: indent + "  ")
        out += index == items.count - 1 ? "\n" : ",\n"
      }
      out += indent + "]"
    case .object(let members):
      guard !members.isEmpty else {
        out += "{}"
        return
      }
      out += "{\n"
      let sorted = members.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
      for (index, member) in sorted.enumerated() {
        out += indent + "  " + JSONValue.quoted(member.key) + ": "
        member.value.write(to: &out, indent: indent + "  ")
        out += index == sorted.count - 1 ? "\n" : ",\n"
      }
      out += indent + "}"
    }
  }

  /// A string as serde_json quotes it: `"`, `\` and the C0 controls escaped,
  /// every other character as it is.
  static func quoted(_ text: String) -> String {
    var out = "\""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      case "\u{08}": out += "\\b"
      case "\u{0C}": out += "\\f"
      case let control where control.value < 0x20:
        out += "\\u00" + String(format: "%02x", control.value)
      default: out.unicodeScalars.append(scalar)
      }
    }
    return out + "\""
  }

  /// A number lexeme as serde_json prints the value it reads: an integer that
  /// fits 64 bits as it is, anything else as the shortest `Double` that reads
  /// back the same, in decimal when its point falls within 16 digits of the
  /// first digit and in `1.5e+20` form otherwise. `-0` reads as a float.
  static func number(_ lexeme: String) -> String? {
    let integer = !lexeme.contains { "eE.".contains($0) }
    if integer, lexeme != "-0", Int64(lexeme) != nil || UInt64(lexeme) != nil { return lexeme }
    guard let value = Double(lexeme), value.isFinite else { return nil }
    let negative = value.sign == .minus ? "-" : ""
    guard value != 0 else { return negative + "0.0" }
    // Swift's description is the shortest form that reads back the same.
    let shown = "\(abs(value))".lowercased()
    let parts = shown.split(separator: "e")
    let mantissa = parts[0]
    let exponent = parts.count > 1 ? Int(parts[1].replacingOccurrences(of: "+", with: ""))! : 0
    let point =
      mantissa.firstIndex(of: ".").map { mantissa.distance(from: mantissa.startIndex, to: $0) }
      ?? mantissa.count
    var digits = mantissa.replacingOccurrences(of: ".", with: "")
    var place = point + exponent
    while digits.hasPrefix("0") {
      digits.removeFirst()
      place -= 1
    }
    while digits.hasSuffix("0") { digits.removeLast() }
    let count = digits.count
    if 0 < place && place <= 16 {
      if count <= place {
        return negative + digits + String(repeating: "0", count: place - count) + ".0"
      }
      return negative + digits.prefix(place) + "." + digits.dropFirst(place)
    }
    if -5 < place && place <= 0 {
      return negative + "0." + String(repeating: "0", count: -place) + digits
    }
    let scientific = place - 1
    let fraction = count > 1 ? "." + digits.dropFirst() : ""
    return negative + digits.prefix(1) + fraction + "e" + (scientific < 0 ? "-" : "+")
      + String(abs(scientific))
  }
}

private struct Parser {
  let bytes: [UInt8]
  var at = 0

  mutating func skipSpace() {
    while at < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[at]) { at += 1 }
  }

  func fail() -> JSONValue.Malformed { JSONValue.Malformed(offset: at) }

  mutating func value(depth: Int) throws -> JSONValue {
    guard depth < 128 else { throw fail() }
    skipSpace()
    guard at < bytes.count else { throw fail() }
    switch bytes[at] {
    case UInt8(ascii: "{"):
      at += 1
      var members: [(key: String, value: JSONValue)] = []
      var seen = Set<[UInt8]>()
      skipSpace()
      if at < bytes.count, bytes[at] == UInt8(ascii: "}") {
        at += 1
        return .object(members)
      }
      while true {
        skipSpace()
        let key = try string()
        guard seen.insert(Array(key.utf8)).inserted else { throw fail() }
        skipSpace()
        try expect(":")
        members.append((key, try value(depth: depth + 1)))
        skipSpace()
        if try separator(close: "}") { return .object(members) }
      }
    case UInt8(ascii: "["):
      at += 1
      var items: [JSONValue] = []
      skipSpace()
      if at < bytes.count, bytes[at] == UInt8(ascii: "]") {
        at += 1
        return .array(items)
      }
      while true {
        items.append(try value(depth: depth + 1))
        skipSpace()
        if try separator(close: "]") { return .array(items) }
      }
    case UInt8(ascii: "\""): return .string(try string())
    case UInt8(ascii: "t"): return try word("true", .bool(true))
    case UInt8(ascii: "f"): return try word("false", .bool(false))
    case UInt8(ascii: "n"): return try word("null", .null)
    default: return try number()
    }
  }

  mutating func expect(_ char: Unicode.Scalar) throws {
    guard at < bytes.count, bytes[at] == UInt8(char.value) else { throw fail() }
    at += 1
  }

  /// True after the closing bracket, false after a comma.
  mutating func separator(close: Unicode.Scalar) throws -> Bool {
    guard at < bytes.count else { throw fail() }
    if bytes[at] == UInt8(ascii: ",") {
      at += 1
      return false
    }
    try expect(close)
    return true
  }

  mutating func word(_ text: String, _ value: JSONValue) throws -> JSONValue {
    let word = Array(text.utf8)
    guard bytes.count - at >= word.count, Array(bytes[at..<at + word.count]) == word else {
      throw fail()
    }
    at += word.count
    return value
  }

  mutating func number() throws -> JSONValue {
    let start = at
    func digits() -> Int {
      let from = at
      while at < bytes.count, (0x30...0x39).contains(bytes[at]) { at += 1 }
      return at - from
    }
    if at < bytes.count, bytes[at] == UInt8(ascii: "-") { at += 1 }
    let first = at < bytes.count ? bytes[at] : 0
    let whole = digits()
    guard whole > 0, first != UInt8(ascii: "0") || whole == 1 else { throw fail() }
    if at < bytes.count, bytes[at] == UInt8(ascii: ".") {
      at += 1
      guard digits() > 0 else { throw fail() }
    }
    if at < bytes.count, bytes[at] | 0x20 == UInt8(ascii: "e") {
      at += 1
      if at < bytes.count, bytes[at] == UInt8(ascii: "+") || bytes[at] == UInt8(ascii: "-") {
        at += 1
      }
      guard digits() > 0 else { throw fail() }
    }
    let lexeme = String(decoding: bytes[start..<at], as: UTF8.self)
    guard let shown = JSONValue.number(lexeme) else { throw JSONValue.Malformed(offset: start) }
    return .number(shown)
  }

  mutating func string() throws -> String {
    try expect("\"")
    var scalars = String.UnicodeScalarView()
    var run: [UInt8] = []
    func flush() throws {
      // Validate first: `String(bytes:encoding:)` drops a leading U+FEFF,
      // which Board keeps, so the text itself is decoded without it.
      guard String(bytes: run, encoding: .utf8) != nil else { throw fail() }
      scalars.append(contentsOf: String(decoding: run, as: UTF8.self).unicodeScalars)
      run.removeAll()
    }
    while true {
      guard at < bytes.count else { throw fail() }
      let byte = bytes[at]
      at += 1
      switch byte {
      case UInt8(ascii: "\""):
        try flush()
        return String(scalars)
      case UInt8(ascii: "\\"):
        try flush()
        guard at < bytes.count else { throw fail() }
        let escape = bytes[at]
        at += 1
        switch escape {
        case UInt8(ascii: "\""): scalars.append("\"")
        case UInt8(ascii: "\\"): scalars.append("\\")
        case UInt8(ascii: "/"): scalars.append("/")
        case UInt8(ascii: "b"): scalars.append("\u{08}")
        case UInt8(ascii: "f"): scalars.append("\u{0C}")
        case UInt8(ascii: "n"): scalars.append("\n")
        case UInt8(ascii: "r"): scalars.append("\r")
        case UInt8(ascii: "t"): scalars.append("\t")
        case UInt8(ascii: "u"):
          var code = try hex4()
          if (0xD800..<0xDC00).contains(code) {
            try expect("\\")
            try expect("u")
            let low = try hex4()
            guard (0xDC00..<0xE000).contains(low) else { throw fail() }
            code = 0x10000 + (code - 0xD800) << 10 + (low - 0xDC00)
          }
          guard let scalar = Unicode.Scalar(code) else { throw fail() }
          scalars.append(scalar)
        default: throw fail()
        }
      case 0..<0x20: throw fail()
      default: run.append(byte)
      }
    }
  }

  mutating func hex4() throws -> UInt32 {
    guard bytes.count - at >= 4,
      bytes[at..<at + 4].allSatisfy(isASCIIHex),
      let code = UInt32(String(decoding: bytes[at..<at + 4], as: UTF8.self), radix: 16)
    else { throw fail() }
    at += 4
    return code
  }
}

/// Whether `byte` is 0-9, a-f or A-F.
func isASCIIHex(_ byte: UInt8) -> Bool {
  (0x30...0x39).contains(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte)
}
