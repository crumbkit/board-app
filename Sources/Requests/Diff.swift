// What a put changes, as the request screen shows it: a text file line by
// line, and a JSON record field by field, with the changed words marked.
import Foundation
import SSHSig

/// A line or value split around the words that changed.
public struct Marked: Equatable, Sendable {
  public let before: String
  public let changed: String
  public let after: String

  public init(_ before: String, _ changed: String = "", _ after: String = "") {
    self.before = before
    self.changed = changed
    self.after = after
  }

  public var text: String { before + changed + after }

  /// `old` and `new` with the words between their common first and last
  /// words marked. A word is a run of letters, digits, `-` and `_`, so a
  /// date or a number is marked whole.
  public static func pair(_ old: String, _ new: String) -> (old: Marked, new: Marked) {
    let a = words(old)
    let b = words(new)
    var head = 0
    while head < min(a.count, b.count), a[head] == b[head] { head += 1 }
    var tail = 0
    while tail < min(a.count, b.count) - head, a[a.count - 1 - tail] == b[b.count - 1 - tail] {
      tail += 1
    }
    func split(_ tokens: [String]) -> Marked {
      Marked(
        tokens[..<head].joined(), tokens[head..<(tokens.count - tail)].joined(),
        tokens[(tokens.count - tail)...].joined())
    }
    return (split(a), split(b))
  }

  private static func words(_ text: String) -> [String] {
    var tokens: [String] = []
    var word = ""
    for char in text {
      if char.isLetter || char.isNumber || char == "-" || char == "_" {
        word.append(char)
      } else {
        if !word.isEmpty { tokens.append(word) }
        word = ""
        tokens.append(String(char))
      }
    }
    if !word.isEmpty { tokens.append(word) }
    return tokens
  }
}

/// One row of a two-up diff: a line before, after, or both.
public struct DiffRow: Equatable, Sendable {
  public let old: (number: Int, text: Marked)?
  public let new: (number: Int, text: Marked)?

  public static func == (lhs: DiffRow, rhs: DiffRow) -> Bool {
    lhs.old?.number == rhs.old?.number && lhs.old?.text == rhs.old?.text
      && lhs.new?.number == rhs.new?.number && lhs.new?.text == rhs.new?.text
  }

  /// Whether the row's two sides are the same line.
  public var isSame: Bool { old != nil && new != nil && old?.text.text == new?.text.text }
}

public enum LineDiff {
  /// The lines of `text`, split at each `\n`, without the empty line after a
  /// final newline.
  public static func lines(_ text: String) -> [String] {
    var lines = text.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
      .map { String(decoding: $0, as: UTF8.self) }
    if lines.last == "" { lines.removeLast() }
    return lines
  }

  /// The rows of a two-up diff of `old` and `new`. Lines both share stay level;
  /// between them, each removed line sits beside the added line in its place,
  /// with the changed words marked. Each line has its hidden characters
  /// escaped, as the statement the owner signs escapes them. Past 4,000,000
  /// line pairs the files are shown as wholly replaced rather than compared.
  public static func rows(_ old: String, _ new: String) -> [DiffRow] {
    let a = lines(old).map(shown)
    let b = lines(new).map(shown)
    guard a.count * b.count <= 4_000_000 else { return pairUp(a, 0, b, 0) }
    // The length of the longest common subsequence of a[i...] and b[j...].
    var common = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in stride(from: a.count - 1, through: 0, by: -1) {
      for j in stride(from: b.count - 1, through: 0, by: -1) {
        common[i][j] =
          a[i] == b[j] ? common[i + 1][j + 1] + 1 : max(common[i + 1][j], common[i][j + 1])
      }
    }
    var rows: [DiffRow] = []
    var i = 0
    var j = 0
    var removed: [Int] = []
    var added: [Int] = []
    func flush() {
      rows += pairUp(
        removed.map { a[$0] }, removed.first ?? 0, added.map { b[$0] }, added.first ?? 0)
      removed = []
      added = []
    }
    while i < a.count || j < b.count {
      if i < a.count, j < b.count, a[i] == b[j] {
        flush()
        rows.append(DiffRow(old: (i + 1, Marked(a[i])), new: (j + 1, Marked(b[j]))))
        i += 1
        j += 1
      } else if j < b.count, i == a.count || common[i][j + 1] >= common[i + 1][j] {
        added.append(j)
        j += 1
      } else {
        removed.append(i)
        i += 1
      }
    }
    flush()
    return rows
  }

  /// What the tabletop pose says above its diff, such as "Lines 5 and 6
  /// change. The other 20 are the same; scroll to read them." A line is named
  /// by its number after the change, or before it when it is removed.
  public static func summary(_ rows: [DiffRow]) -> String {
    let numbers = rows.filter { !$0.isSame }.compactMap { $0.new?.number ?? $0.old?.number }
    let same = rows.filter(\.isSame).count
    let changes: String
    switch numbers.count {
    case 0: return "Nothing changes."
    case 1: changes = "Line \(numbers[0]) changes."
    case 2...4:
      changes =
        "Lines \(numbers.dropLast().map(String.init).joined(separator: ", ")) and \(numbers[numbers.count - 1]) change."
    default: changes = "\(numbers.count) lines change."
    }
    if same == 0 { return changes }
    return changes + " The other \(same) \(same == 1 ? "is" : "are") the same; scroll to read them."
  }

  /// Removed lines beside added ones, in order, with the words that changed
  /// marked; the longer side's extra lines stand alone.
  private static func pairUp(_ old: [String], _ oldStart: Int, _ new: [String], _ newStart: Int)
    -> [DiffRow]
  {
    (0..<max(old.count, new.count)).map { k in
      switch (k < old.count, k < new.count) {
      case (true, true):
        let marked = Marked.pair(old[k], new[k])
        return DiffRow(old: (oldStart + k + 1, marked.old), new: (newStart + k + 1, marked.new))
      case (true, false): return DiffRow(old: (oldStart + k + 1, Marked(old[k])), new: nil)
      default: return DiffRow(old: nil, new: (newStart + k + 1, Marked(new[k])))
      }
    }
  }
}

/// One field of a record, named by its key path, before and after.
public struct FieldRow: Equatable, Sendable {
  /// The key path, such as `rule › max`.
  public let key: String
  public let old: Marked?
  public let new: Marked?

  public init(key: String, old: Marked?, new: Marked?) {
    self.key = key
    self.old = old
    self.new = new
  }
}

public enum FieldDiff {
  /// The fields that differ between two records, by key path in sorted
  /// order, and the key paths of those that are the same. An array is one
  /// field. Values are compared as JSON, so a string and a number with the
  /// same digits differ. A string shows as its text, or quoted when the other
  /// side is not a string; any other value shows as JSON on one line.
  public static func compare(_ old: JSONValue, _ new: JSONValue) -> (
    changed: [FieldRow], same: [String]
  ) {
    let before = leaves(old)
    let after = leaves(new)
    let paths = Set(before.keys).union(after.keys).sorted {
      $0.lexicographicallyPrecedes($1) { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }
    var changed: [FieldRow] = []
    var same: [String] = []
    for path in paths {
      let key = path.map(shown).joined(separator: " › ")
      let a = before[path]
      let b = after[path]
      if a == b {
        same.append(key)
      } else if let a, let b {
        let quote = (a.string == nil) != (b.string == nil)
        let marked = Marked.pair(display(a, quote: quote), display(b, quote: quote))
        changed.append(FieldRow(key: key, old: marked.old, new: marked.new))
      } else {
        changed.append(
          FieldRow(
            key: key, old: a.map { Marked(display($0, quote: false)) },
            new: b.map { Marked(display($0, quote: false)) }))
      }
    }
    return (changed, same)
  }

  /// Each leaf by its key path. Object keys are unique, so paths are too.
  private static func leaves(_ value: JSONValue, _ path: [String] = []) -> [[String]: JSONValue] {
    guard case .object(let members) = value, !members.isEmpty else { return [path: value] }
    return members.reduce(into: [:]) { all, member in
      all.merge(leaves(member.value, path + [member.key])) { a, _ in a }
    }
  }

  private static func display(_ value: JSONValue, quote: Bool) -> String {
    if !quote, let text = value.string { return shown(text) }
    switch value {
    case .array(let items):
      return "[" + items.map { display($0, quote: true) }.joined(separator: ", ") + "]"
    case .object(let members):
      return "{"
        + members.map {
          shown(JSONValue.string($0.key).pretty) + ": " + display($0.value, quote: true)
        }
        .joined(separator: ", ") + "}"
    default: return shown(value.pretty)
    }
  }
}
