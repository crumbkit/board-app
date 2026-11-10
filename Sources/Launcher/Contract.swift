// The launcher contract: what a provider prints. docs/launcher-contract.md
// describes it with a full example.
import Foundation

/// The kind every provider output starts with.
let itemsKind = "launcher/items/v1"

/// Where a URL can be opened from. The Mac opens all three; the phone will
/// open only `proxyable` and `public` ones.
public enum Reach: String, Codable, Sendable, Hashable {
  case macOnly = "mac-only"
  case proxyable
  case `public`
}

/// A URL with the reach every URL in the contract carries. Only http and
/// https URLs decode, so an action cannot open a file or another app.
public struct Address: Sendable, Hashable {
  public let href: URL
  public let reach: Reach

  /// Whether the launcher may open the URL: http and https only.
  public static func isWeb(_ url: URL) -> Bool {
    ["http", "https"].contains(url.scheme?.lowercased() ?? "")
  }
}

extension Address: Decodable {
  private enum Keys: String, CodingKey { case href, reach }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    href = try c.decode(URL.self, forKey: .href)
    reach = try c.decode(Reach.self, forKey: .reach)
    guard Self.isWeb(href) else {
      throw DecodingError.dataCorruptedError(
        forKey: .href, in: c, debugDescription: "only http and https URLs may be opened")
    }
  }
}

/// Throws unless argv is non-empty and starts with an absolute path, since
/// no shell looks the command up.
func checkArgv<K: CodingKey>(
  _ argv: [String], _ key: K, in c: KeyedDecodingContainer<K>
) throws {
  guard argv.first?.hasPrefix("/") == true else {
    throw DecodingError.dataCorruptedError(
      forKey: key, in: c, debugDescription: "the argv must start with an absolute path")
  }
}

/// A state's tone. The shell shows each with a symbol and a word as well as
/// a colour.
public enum Tone: String, Codable, Sendable, Hashable {
  case good, neutral, failed, removed
}

/// The state an item or a record is in: a tone and the word the row shows.
public struct Status: Codable, Sendable, Hashable {
  public let tone: Tone
  public let word: String

  public init(tone: Tone, word: String) {
    self.tone = tone
    self.word = word
  }
}

/// A command the shell runs before an action, whose output the owner reads
/// before confirming.
public struct Confirm: Sendable, Hashable, Decodable {
  public let preview: [String]

  private enum Keys: String, CodingKey { case preview }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    preview = try c.decode([String].self, forKey: .preview)
    try checkArgv(preview, Keys.preview, in: c)
  }
}

/// A command run from argv, with no shell.
public struct Run: Sendable, Hashable, Decodable {
  public let argv: [String]
  public let confirm: Confirm?

  private enum Keys: String, CodingKey { case argv, confirm }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    argv = try c.decode([String].self, forKey: .argv)
    confirm = try c.decodeIfPresent(Confirm.self, forKey: .confirm)
    try checkArgv(argv, Keys.argv, in: c)
  }
}

/// What an action does: open a URL, copy text, or run a command.
public enum Perform: Sendable, Hashable {
  case open(Address)
  case copy(String)
  case run(Run)
}

public struct Action: Sendable, Hashable, Identifiable {
  public let id: String
  public let label: String
  public let perform: Perform
}

extension Action: Decodable {
  private enum Keys: String, CodingKey { case id, label, open, copy, run }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    id = try c.decode(String.self, forKey: .id)
    label = try c.decode(String.self, forKey: .label)
    let given = [Keys.open, .copy, .run].filter { c.contains($0) }
    guard given.count == 1 else {
      throw DecodingError.dataCorruptedError(
        forKey: .id, in: c,
        debugDescription: "action \(id) must have exactly one of open, copy and run")
    }
    switch given[0] {
    case .open: perform = .open(try c.decode(Address.self, forKey: .open))
    case .copy: perform = .copy(try c.decode(String.self, forKey: .copy))
    default: perform = .run(try c.decode(Run.self, forKey: .run))
    }
  }
}

/// One application of a workspace, and where it is served.
public struct App: Decodable, Sendable, Hashable {
  public let name: String
  public let link: Address?
}

/// The data of a `workspace` item.
public struct Workspace: Decodable, Sendable, Hashable {
  public let apps: [App]
  public let branch: String?
  public let updated: Date?
}

/// The data of an `evidence` item: a file a task kept.
public struct Evidence: Decodable, Sendable, Hashable {
  public let path: String
  /// The kind as the provider names it, such as "Markdown" or "PNG image".
  public let kind: String
  /// The size in bytes, as the provider reported it.
  public let size: Int
  public let added: Date
  public let taskRecord: String?
  /// The SHA-256 as the provider reported it. Board.app does not check it.
  public let sha256: String

  enum CodingKeys: String, CodingKey {
    case path, kind, size, added, sha256
    case taskRecord = "task_record"
  }
}

/// The data of a `test-run` part.
public struct TestRun: Decodable, Sendable, Hashable {
  public let passed: Bool
  public let command: String
  public let finished: Date
  public let seconds: Double?
  public let summary: String?
}

/// The data of a `commit` part.
public struct Commit: Decodable, Sendable, Hashable {
  public let sha: String
  public let subject: String
  public let author: String
  public let date: Date
  public let link: Address?
}

/// An item's type-specific data. Each case is a type Board.app has a view
/// for; items of any other type are skipped.
public enum Body: Sendable, Hashable {
  case workspace(Workspace)
  case evidence(Evidence)
  case testRun(TestRun)
  case commit(Commit)
}

/// One row a provider lists.
public struct Item: Sendable, Hashable, Identifiable {
  /// Stable across runs, so a selection survives a refresh.
  public let id: String
  public let type: String
  public let title: String
  public let subtitle: String?
  public let keywords: [String]
  public let status: Status?
  public let actions: [Action]
  /// The command that lists the item's parts, when it has any.
  public let children: [String]?
  public let body: Body
}

public struct Section: Sendable, Hashable {
  public let title: String
  public let items: [Item]
}

/// Items left out because Board.app has no view for their type.
struct Skip: Sendable, Hashable {
  let type: String
  let count: Int
}

/// A decoded provider output.
public struct Listing: Sendable, Hashable {
  public let sections: [Section]
  var skipped: [Skip] = []

  var items: [Item] { sections.flatMap(\.items) }
}

enum ContractError: Error, Sendable, Hashable, CustomStringConvertible {
  case notJSON(String)
  case unknownKind(String?)
  case invalid(String)

  var description: String {
    switch self {
    case .notJSON(let detail): "The output is not JSON: \(detail)"
    case .unknownKind(nil): "The output has no kind; it must start with \"kind\": \"\(itemsKind)\""
    case .unknownKind(let kind?): "The kind \(kind) is not one Board.app knows"
    case .invalid(let detail): "The output does not match \(itemsKind): \(detail)"
    }
  }
}

extension Listing {
  /// Decodes a provider's output, leaving out items of a type Board.app has
  /// no view for and counting them in `skipped`.
  static func decode(_ data: Data) throws -> Listing {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let raw: RawListing
    do {
      raw = try decoder.decode(RawListing.self, from: data)
    } catch let error as ContractError {
      throw error
    } catch DecodingError.dataCorrupted(let context) where context.codingPath.isEmpty {
      let text = String(decoding: data.prefix(80), as: UTF8.self)
      throw ContractError.notJSON(text.isEmpty ? "it is empty" : "it starts \(text)")
    } catch let error as DecodingError {
      throw ContractError.invalid(Self.explain(error))
    }
    var skipped: [String: Int] = [:]
    let sections = raw.sections.map { section in
      var items: [Item] = []
      for raw in section.items {
        if let item = raw.item {
          items.append(item)
        } else {
          skipped[raw.type, default: 0] += 1
        }
      }
      return Section(title: section.title, items: items)
    }
    return Listing(
      sections: sections,
      skipped: skipped.sorted { $0.key < $1.key }.map { Skip(type: $0.key, count: $0.value) })
  }

  private static func explain(_ error: DecodingError) -> String {
    func path(_ context: DecodingError.Context) -> String {
      let keys = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
      return keys.isEmpty ? "the top level" : keys.joined(separator: ".")
    }
    switch error {
    case .keyNotFound(let key, let context):
      return "\(path(context)) is missing \(key.stringValue)"
    case .typeMismatch(_, let context), .valueNotFound(_, let context):
      return "\(path(context)) has the wrong type"
    case .dataCorrupted(let context):
      return "\(path(context)): \(context.debugDescription)"
    @unknown default:
      return "\(error)"
    }
  }
}

/// The whole output, decoded once. The kind is checked before anything
/// else, so an unknown kind is reported as such.
private struct RawListing: Decodable {
  let sections: [RawSection]

  private enum Keys: String, CodingKey { case kind, sections }

  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    let kind = try? c.decodeIfPresent(String.self, forKey: .kind)
    guard kind == itemsKind else { throw ContractError.unknownKind(kind) }
    sections = try c.decode([RawSection].self, forKey: .sections)
  }
}

private struct RawSection: Decodable {
  let title: String
  let items: [RawItem]
}

/// An item before its type is checked. `data` is decoded only for a type
/// Board.app has a view for, so an unknown type's data cannot fail the
/// output.
private struct RawItem: Decodable {
  let type: String
  let item: Item?

  private enum Keys: String, CodingKey {
    case id, type, title, subtitle, keywords, status, actions, children, data
  }

  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    let id = try c.decode(String.self, forKey: .id)
    type = try c.decode(String.self, forKey: .type)
    let body: Body
    switch type {
    case "workspace": body = .workspace(try c.decode(Workspace.self, forKey: .data))
    case "evidence": body = .evidence(try c.decode(Evidence.self, forKey: .data))
    case "test-run": body = .testRun(try c.decode(TestRun.self, forKey: .data))
    case "commit": body = .commit(try c.decode(Commit.self, forKey: .data))
    default:
      item = nil
      return
    }
    let children = try c.decodeIfPresent([String].self, forKey: .children)
    if let children { try checkArgv(children, Keys.children, in: c) }
    item = Item(
      id: id, type: type, title: try c.decode(String.self, forKey: .title),
      subtitle: try c.decodeIfPresent(String.self, forKey: .subtitle),
      keywords: try c.decodeIfPresent([String].self, forKey: .keywords) ?? [],
      status: try c.decodeIfPresent(Status.self, forKey: .status),
      actions: try c.decodeIfPresent([Action].self, forKey: .actions) ?? [],
      children: children, body: body)
  }
}
