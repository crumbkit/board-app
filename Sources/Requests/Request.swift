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
  /// The file at a plain action's path now, which the action would use. It is
  /// not part of what the owner signs.
  public let currentContent: Data?

  public init(
    effect: Effect, boardName: String, asked: Date, priorContent: Data?, current: String?,
    currentContent: Data? = nil
  ) {
    self.effect = effect
    self.boardName = boardName
    self.asked = asked
    self.priorContent = priorContent
    self.current = current
    self.currentContent = currentContent
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

  /// The request screen's title, such as "Change a Task" or "Post a Review".
  public var heading: String {
    switch kind {
    case .change: "Change a \(capitalized(noun))"
    case .add: "Add a \(capitalized(noun))"
    case .remove: "Remove a \(capitalized(noun))"
    case .action(let verb): "\(capitalized(verb)) a \(capitalized(singular))"
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

  /// Whether the file changed after the plugin asked, so an approval would
  /// not fit: the blob there now is not the one the put replaces, or the one
  /// the removal names.
  public var isStale: Bool {
    guard effect.op == "put" || (effect.op == "rm" && effect.prior != nil) else { return false }
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

  /// The two-up rows of what a put changes in a text file or a record's
  /// JSON, every line added when there was no file, or nil for a plain action
  /// or when the replaced blob could not be read.
  public var lineRows: [DiffRow]? {
    if effect.op == "rm", let priorContent {
      return LineDiff.rows(String(decoding: priorContent, as: UTF8.self), "")
    }
    guard let content = effect.content else { return nil }
    if effect.prior == nil { return LineDiff.rows("", content) }
    guard let priorContent else { return nil }
    // A record is compared as Board prints it, so formatting alone shows no change.
    let old =
      effect.record != nil
      ? (try? JSONValue.parse(priorContent))?.pretty
      : nil
    return LineDiff.rows(old ?? String(decoding: priorContent, as: UTF8.self), content)
  }

  /// A record put's fields, compared with the record it replaces, or nil when
  /// the put writes text or the replaced blob is not a JSON record.
  public var fields: (changed: [FieldRow], same: [String])? {
    guard let record = effect.record else { return nil }
    guard effect.prior != nil else { return FieldDiff.compare(.object([]), record) }
    guard let priorContent, let old = try? JSONValue.parse(priorContent) else { return nil }
    return FieldDiff.compare(old, record)
  }

  /// The last segment of the path, which a plain action acts on: `report`.
  public var target: String { effect.path.split(separator: "/").last.map(String.init) ?? "" }

  /// What approving allows, in one sentence the screen prints in bold.
  public var allows: String {
    if case .action(let verb) = kind {
      return "Approving lets \(plugin) \(verb) from this \(target) whenever it runs."
    }
    return "Approving lets \(plugin) write exactly this version."
  }

  /// What the approval does not cover, or why it can go stale.
  public var limits: String {
    if case .action(let verb) = kind {
      return
        "Your approval names the \(target), not its words. If the \(target) changes, \(plugin) can \(verb) the new words."
    }
    return
      "If the \(noun) changes first, this approval no longer fits and \(plugin) has to ask again."
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

private func capitalized(_ word: String) -> String {
  word.prefix(1).uppercased() + word.dropFirst()
}

/// The questions and requests waiting, each newest first, and the boards
/// they wait in.
public struct Inbox: Sendable {
  public let requests: [Request]
  /// Newest first, by path when two were asked at the same time.
  public let questions: [Question]

  public init(_ requests: [Request], questions: [Question] = []) {
    self.requests = requests.sorted { ($0.asked, $1.id) > ($1.asked, $0.id) }
    let distant = Date.distantPast
    self.questions = questions.sorted {
      ($0.askedDate ?? distant, $1.path) > ($1.askedDate ?? distant, $0.path)
    }
  }

  /// Each board with questions or requests waiting and how many, by name.
  public var boards: [(name: String, count: Int)] {
    let names = requests.map(\.boardName) + questions.map(\.boardName)
    return Dictionary(grouping: names, by: { $0 })
      .map { ($0.key, $0.value.count) }
      .sorted { $0.name < $1.name }
  }

  /// The requests in `board`, or in every board when it is nil.
  public func requests(in board: String?) -> [Request] {
    board.map { name in requests.filter { $0.boardName == name } } ?? requests
  }

  /// The questions in `board`, or in every board when it is nil.
  public func questions(in board: String?) -> [Question] {
    board.map { name in questions.filter { $0.boardName == name } } ?? questions
  }

  /// How many questions and requests wait in `board`, or in every board.
  public func count(in board: String?) -> Int {
    requests(in: board).count + questions(in: board).count
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
