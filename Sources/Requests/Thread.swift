// A request as a thread: every version a plugin asked for the same op at the
// same path, oldest first, and the owner's replies, as Board's
// `requests.thread` returns them. Only the latest version can be approved.
import Foundation
import SSHSig

public struct RequestThread: Sendable {
  /// One version of the request.
  public struct Version: Identifiable, Sendable {
    /// The effect id Board gave this version.
    public let id: String
    /// 1 for the oldest version.
    public let number: Int
    /// When Board wrote it, or nil for an effect written before Board kept
    /// the time.
    public let asked: Date?
    /// The version as the screens word it.
    public let request: Request
    /// The owner's answer, or nil while it waits.
    public let answer: Answer?
    /// Whether Board marks it the newest pending version, the only one that
    /// can be approved.
    public let isLatest: Bool
    /// The number of the version after it, or nil when none came after.
    public let replacedBy: Int?
  }

  public struct Answer: Equatable, Sendable {
    public let approved: Bool
    public let reason: String?

    public init(approved: Bool, reason: String?) {
      self.approved = approved
      self.reason = reason
    }
  }

  /// A reply of the owner's to one version.
  public struct Reply: Equatable, Sendable {
    /// The id of the version it answers.
    public let effect: String
    public let text: String
    /// From the reply's file name, or nil when the name is not a time.
    public let sent: Date?
    /// The logical path in the personal board, which names the reply.
    public let path: String
  }

  /// A version or a reply, in the order the screen shows them.
  public enum Item: Identifiable, Sendable {
    case version(Version)
    case reply(Reply)

    public var id: String {
      switch self {
      case .version(let version): version.id
      case .reply(let reply): reply.path
      }
    }
  }

  /// Oldest first.
  public let versions: [Version]
  /// Oldest first.
  public let replies: [Reply]

  /// Board's report did not describe the thread of this request.
  public struct Mismatch: Error, Equatable {
    /// The first field that did not fit, such as `path` or `versions`.
    public let field: String

    public init(field: String) { self.field = field }
  }

  /// A thread of one version, for a request the Mac shared without one.
  public init(request: Request) {
    versions = [
      Version(
        id: request.id, number: 1, asked: request.asked, request: request, answer: nil,
        isLatest: true, replacedBy: nil)
    ]
    replies = []
  }

  /// The thread in `report`, what `board call requests.thread --json` prints,
  /// for `request`. The report must name the request's board, plugin, op and
  /// path, and hold a version with its id. That version keeps `request`
  /// itself, so the latest version is shown from the bytes the phone signs.
  /// The others are worded against the same old version and file as
  /// `request`, since Board's report does not carry theirs.
  public init(report: Data, request: Request) throws {
    let parsed = try JSONValue.parse(report)
    guard parsed["schema"]?.string == "board/call-report/v2",
      let output = parsed["data"]?["output"]
    else { throw Mismatch(field: "schema") }
    let effect = request.effect
    for (key, value) in [
      ("board", effect.board), ("plugin", effect.plugin), ("op", effect.op), ("path", effect.path),
    ] where output[key]?.string.map({ Array($0.utf8) }) != Array(value.utf8) {
      throw Mismatch(field: key)
    }
    guard case .array(let items)? = output["versions"],
      case .array(let replyItems)? = output["replies"]
    else { throw Mismatch(field: "versions") }
    let hasLatest = items.contains { $0["latest"] == .bool(true) && $0["pending"] == .bool(true) }
    var versions: [Version] = []
    for (index, item) in items.enumerated() {
      guard let id = item["id"]?.string else { throw Mismatch(field: "versions") }
      let asked = item["asked"]?.string.flatMap(rfc3339)
      let answer = item["answer"].flatMap { value -> Answer? in
        guard let word = value["answer"]?.string else { return nil }
        return Answer(approved: word == "approve", reason: value["reason"]?.string)
      }
      let shown =
        id == request.id
        ? request
        : try Self.version(
          of: request, record: item["record"], text: item["text"]?.string, asked: asked)
      versions.append(
        Version(
          id: id, number: index + 1, asked: asked, request: shown, answer: answer,
          isLatest: item["latest"] == .bool(true) && item["pending"] == .bool(true),
          replacedBy: hasLatest && index + 1 < items.count ? index + 2 : nil))
    }
    guard versions.contains(where: { $0.id == request.id }) else {
      throw Mismatch(field: "versions")
    }
    self.versions = versions
    replies = replyItems.compactMap { item in
      guard let effect = item["effect"]?.string, let text = item["text"]?.string,
        let path = item["path"]?.string
      else { return nil }
      let name = path.split(separator: "/").last.map(String.init) ?? ""
      return Reply(effect: effect, text: text, sent: replyTime(name), path: path)
    }
  }

  private init(versions: [Version], replies: [Reply]) {
    self.versions = versions
    self.replies = replies
  }

  /// Another version of `request`, with its own content.
  private static func version(
    of request: Request, record: JSONValue?, text: String?, asked: Date?
  ) throws -> Request {
    let effect = request.effect
    var members: [(key: String, value: JSONValue)] = [
      ("$type", .string("board/effect/v1")), ("board", .string(effect.board)),
      ("plugin", .string(effect.plugin)), ("op", .string(effect.op)),
      ("path", .string(effect.path)),
    ]
    if let prior = effect.prior { members.append(("prior", .string(prior))) }
    if let record, record != .null { members.append(("record", record)) }
    if let text { members.append(("text", .string(text))) }
    return Request(
      effect: try Effect(json: Data(JSONValue.object(members).pretty.utf8)),
      boardName: request.boardName, asked: asked ?? request.asked,
      priorContent: request.priorContent, current: request.current,
      currentContent: request.currentContent)
  }

  /// The version Board marks latest, which Approve signs.
  public var latest: Version? { versions.last(where: \.isLatest) }

  /// Whether approving `request` is allowed: only when it is the latest
  /// version.
  public func isApprovable(_ request: Request) -> Bool { latest?.id == request.id }

  /// The versions and replies by time. A version with no time comes first;
  /// on a tie a version comes before a reply.
  public var items: [Item] {
    var out: [Item] = []
    var pending = replies[...]
    for version in versions {
      while let reply = pending.first, let sent = reply.sent, let asked = version.asked,
        sent < asked
      {
        out.append(.reply(reply))
        pending = pending.dropFirst()
      }
      out.append(.version(version))
    }
    return out + pending.map(Item.reply)
  }

  /// The thread with the replies sent from this phone that Board does not
  /// hold yet.
  public func adding(_ sent: [PhoneReply]) -> RequestThread {
    let known = Set(replies.map(\.path))
    let ids = Set(versions.map(\.id))
    let new = sent.filter { !known.contains($0.path) && ids.contains($0.effect) }.map {
      Reply(effect: $0.effect, text: $0.text, sent: $0.sent, path: $0.path)
    }
    return RequestThread(versions: versions, replies: replies + new)
  }

  /// `requests` without each version that a later version waiting among them
  /// replaces, so the inbox shows a request once. A version is dropped only
  /// for a latest version with its board, plugin, op and path.
  public static func latestOnly(_ requests: [Request], threads: [String: RequestThread])
    -> [Request]
  {
    let byID = Dictionary(requests.map { ($0.id, $0.effect) }, uniquingKeysWith: { a, _ in a })
    return requests.filter { request in
      guard let latest = threads[request.id]?.latest, latest.id != request.id,
        let other = byID[latest.id]
      else { return true }
      let mine = request.effect
      return [mine.board, mine.plugin, mine.op, mine.path].map { Array($0.utf8) }
        != [other.board, other.plugin, other.op, other.path].map { Array($0.utf8) }
    }
  }
}

/// A reply the owner wrote on the phone, on its way through iCloud to the Mac,
/// which puts it in the personal board. It approves and refuses nothing.
public struct PhoneReply: Equatable, Sendable {
  /// The id of the version it answers.
  public let effect: String
  public let text: String
  /// When it was written, to the second.
  public let sent: Date

  /// The reply, or nil when the text is blank or `effect` is not 64 lowercase
  /// hex digits. The text is trimmed.
  public init?(effect: String, text: String, sent: Date) {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, effect.utf8.count == 64,
      effect.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
    else { return nil }
    self.effect = effect
    self.text = text
    self.sent = Date(timeIntervalSince1970: sent.timeIntervalSince1970.rounded(.down))
  }

  /// The time as the reply's file name: `20261030T224454Z`.
  public var stamp: String { replyStamp(sent) }

  /// The zone record's name.
  public var name: String { "reply-\(effect)-\(stamp)" }

  /// The zone record's fields.
  public var fields: [String: String] { ["effect": effect, "text": text, "sent": stamp] }

  /// The reply in a zone record, or nil when the fields do not make one or
  /// the record's name is not the one they give.
  public init?(name: String, fields: [String: String]) {
    guard let effect = fields["effect"], let text = fields["text"],
      let sent = fields["sent"].flatMap(replyTime),
      let reply = PhoneReply(effect: effect, text: text, sent: sent), reply.name == name
    else { return nil }
    self = reply
  }

  /// Where the Mac puts it in the personal board.
  public var path: String { "/requests/replies/\(effect)/\(stamp)" }

  /// The `requests/reply/v1` record the Mac puts there.
  public var record: Data {
    let record = JSONValue.object([
      ("$type", .string("requests/reply/v1")), ("effect", .string(effect)),
      ("text", .string(text)),
    ])
    return Data((record.pretty + "\n").utf8)
  }
}

private func utcFormatter(_ format: String) -> DateFormatter {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(identifier: "UTC")
  formatter.dateFormat = format
  return formatter
}

private func replyStamp(_ date: Date) -> String {
  utcFormatter("yyyyMMdd'T'HHmmss'Z'").string(from: date)
}

/// A reply's file name as a time, or nil when it is not one.
private func replyTime(_ name: String) -> Date? {
  utcFormatter("yyyyMMdd'T'HHmmss'Z'").date(from: name)
}

/// Board's `asked`, RFC 3339 in UTC to the microsecond, read to the second.
private func rfc3339(_ text: String) -> Date? {
  guard text.hasSuffix("Z"), text.count >= 20 else { return nil }
  return utcFormatter("yyyy-MM-dd'T'HH:mm:ss").date(from: String(text.prefix(19)))
}
