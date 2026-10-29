// A pending effect as the inbox and the request screen show it: the words
// Board builds from the record, since plugins supply no sentences of their own.
import Foundation
import SSHSig

/// One pending effect, with what the Mac read about it from the board.
public struct Request: Identifiable, Sendable {
  public let effect: Effect
  /// The board's git remote, such as `owner/board`.
  public let boardName: String
  /// When the pending effect was committed.
  public let asked: Date
  /// The bytes of the blob a put replaces, when the Mac could read them.
  public let priorContent: Data?
  /// The blob at the effect's path now, or nil when no file is there.
  public let current: String?

  public init(effect: Effect, boardName: String, asked: Date, priorContent: Data?, current: String?)
  {
    self.effect = effect
    self.boardName = boardName
    self.asked = asked
    self.priorContent = priorContent
    self.current = current
  }

  public var id: String { effect.id }
  public var plugin: String { effect.plugin }

  /// What the plugin asks to do.
  public enum Kind: Equatable, Sendable {
    /// A put that replaces the file at `prior`.
    case change
    /// A put where no file was.
    case add
    case remove
    /// A plugin's own op, named without the plugin, such as `post`.
    case action(String)
  }

  public var kind: Kind {
    switch effect.op {
    case "put": effect.prior == nil ? .add : .change
    case "rm": .remove
    default: .action(String(effect.op.split(separator: ".", maxSplits: 1).last ?? ""))
    }
  }

  /// The kind of thing at the path, from its `$type`: `tasks/task/v2` is a
  /// task. A file with no type is a file.
  public var noun: String {
    let type = record?["$type"]?.string ?? frontMatter["$type"]
    let parts = type?.split(separator: "/") ?? []
    return parts.count == 3 ? String(parts[1]) : "file"
  }

  /// The thing's name: its title, or else its file name in words. A plain
  /// action names the last two segments of its path, such as `fix-sync report`.
  public var name: String {
    let segments = effect.path.split(separator: "/").map(String.init)
    if case .action = kind { return segments.suffix(2).joined(separator: " ") }
    if let title = record?["title"]?.string ?? frontMatter["title"] { return title }
    let stem = ((segments.last ?? "") as NSString).deletingPathExtension
    let words = stem.replacingOccurrences(of: "-", with: " ").replacingOccurrences(
      of: "_", with: " ")
    return words.prefix(1).uppercased() + words.dropFirst()
  }

  /// The request screen's heading, such as "Change a task" or "Post a review".
  public var heading: String {
    switch kind {
    case .change: "Change a \(noun)"
    case .add: "Add a \(noun)"
    case .remove: "Remove a \(noun)"
    case .action(let verb): "\(verb.prefix(1).uppercased() + verb.dropFirst()) a \(singular)"
    }
  }

  /// The inbox row's sentence, such as "tasks wants to change this task".
  public var sentence: String {
    switch kind {
    case .change: "\(plugin) wants to change this \(noun)"
    case .add: "\(plugin) wants to add this \(noun)"
    case .remove: "\(plugin) wants to remove this \(noun)"
    case .action(let verb): "\(plugin) asks to \(verb) it"
    }
  }

  /// What the message after an approval says the approval allows.
  public var approved: String {
    if case .action = kind {
      return "Approved. \(plugin) will not ask again until you take this back."
    }
    return "Approved. \(plugin) can write this version of “\(name)” the next time it asks."
  }

  public var refused: String { "Refused. \(plugin) has been told no." }

  /// Whether the file changed after the plugin asked, so an approval would
  /// not fit: the blob there now is not the one the put replaces.
  public var isStale: Bool {
    guard effect.op == "put" else { return false }
    return current?.lowercased() != effect.prior?.lowercased()
  }

  /// Whether the put replaces a blob the Mac could not read.
  public var isPriorMissing: Bool { effect.prior != nil && priorContent == nil }

  /// The plugin's name as one thing: `tasks` names a task.
  var singular: String {
    plugin.hasSuffix("s") && !plugin.hasSuffix("ss") ? String(plugin.dropLast()) : plugin
  }

  /// The record a put writes, or for a removal the record it removes.
  var record: JSONValue? {
    effect.record ?? (effect.op == "rm" ? priorContent.flatMap { try? JSONValue.parse($0) } : nil)
  }

  /// The text a put writes, or for a removal the text it removes.
  var text: String? {
    effect.text
      ?? (effect.op == "rm" ? priorContent.map { String(decoding: $0, as: UTF8.self) } : nil)
  }

  /// The `key: value` lines between a text's opening `---` lines, with a
  /// quoted value read as a JSON string.
  var frontMatter: [String: String] {
    guard let text, text.hasPrefix("---\n") else { return [:] }
    var fields: [String: String] = [:]
    for line in text.dropFirst(4).split(separator: "\n", omittingEmptySubsequences: false) {
      if line == "---" { break }
      guard let colon = line.firstIndex(of: ":") else { continue }
      let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      let quoted = value.hasPrefix("\"") ? (try? JSONValue.parse(Data(value.utf8)))?.string : nil
      fields[String(line[..<colon])] = quoted ?? value
    }
    return fields
  }
}

/// The requests waiting, newest first, and the boards they wait in.
public struct Inbox: Sendable {
  public let requests: [Request]

  public init(_ requests: [Request]) {
    self.requests = requests.sorted { ($0.asked, $1.id) > ($1.asked, $0.id) }
  }

  /// Each board with requests waiting and how many, by name.
  public var boards: [(name: String, count: Int)] {
    Dictionary(grouping: requests, by: \.boardName)
      .map { ($0.key, $0.value.count) }
      .sorted { $0.name < $1.name }
  }

  /// The requests in `board`, or in every board when it is nil.
  public func requests(in board: String?) -> [Request] {
    board.map { name in requests.filter { $0.boardName == name } } ?? requests
  }
}

/// When a request was asked, as a row shows it: the time today, "Yesterday",
/// or the date.
public func askedLabel(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
  if calendar.isDate(date, inSameDayAs: now) {
    return date.formatted(
      Date.FormatStyle(
        date: .omitted, time: .shortened, locale: calendar.locale ?? .current, calendar: calendar,
        timeZone: calendar.timeZone))
  }
  if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
    calendar.isDate(date, inSameDayAs: yesterday)
  {
    return "Yesterday"
  }
  return date.formatted(
    Date.FormatStyle(
      date: .abbreviated, time: .omitted, locale: calendar.locale ?? .current, calendar: calendar,
      timeZone: calendar.timeZone))
}
