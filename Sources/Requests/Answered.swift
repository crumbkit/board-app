// What Board recorded when the owner answered a pending effect, as the Mac
// window's Answered list reads it from `effects/seen/` in the personal board.
import Foundation
import SSHSig

/// A `board/seen/v1` record: the owner's answer to one pending effect.
public struct SeenAnswer: Equatable, Sendable {
  /// The id of the effect it answers, from the record's
  /// `/effects/answered/<id>` path.
  public let effect: String
  public let approved: Bool
  /// The refusal's reason, when it gave one.
  public let reason: String?
  /// The approval's armored signature.
  public let signature: String?

  public struct Malformed: Error, Equatable {
    public let field: String
  }

  public init(json: Data) throws {
    let record = try JSONValue.parse(json)
    guard record["$type"]?.string == "board/seen/v1" else { throw Malformed(field: "$type") }
    guard let answer = record["answer"]?.string, answer == "approve" || answer == "refuse" else {
      throw Malformed(field: "answer")
    }
    let prefix = "/effects/answered/"
    guard let path = record["effect"]?.string, path.hasPrefix(prefix),
      isEffectID(String(path.dropFirst(prefix.count)))
    else { throw Malformed(field: "effect") }
    effect = String(path.dropFirst(prefix.count))
    approved = answer == "approve"
    reason = record["reason"]?.string.flatMap { $0.isEmpty ? nil : $0 }
    signature = record["signature"]?.string
  }

  /// Each effect id with a seen record in `log`, newest first, and when its
  /// record was committed. `log` is what
  /// `git log --format=%ct --name-only -- effects/seen/` prints, newest
  /// commit first; a file named twice keeps its newest time.
  public static func times(_ log: String) -> [(effect: String, at: Date)] {
    var out: [(effect: String, at: Date)] = []
    var seen: Set<String> = []
    var at: Date?
    for line in log.split(separator: "\n") {
      if let seconds = TimeInterval(line) {
        at = Date(timeIntervalSince1970: seconds)
        continue
      }
      let name = line.split(separator: "/").last.map(String.init) ?? ""
      guard line.hasPrefix("effects/seen/"), name.hasSuffix(".json"), let at else { continue }
      let id = String(name.dropLast(5))
      guard isEffectID(id), seen.insert(id).inserted else { continue }
      out.append((id, at))
    }
    return out
  }
}

/// Whether `text` is 64 lowercase hex digits, as Board names an effect.
private func isEffectID(_ text: String) -> Bool {
  text.utf8.count == 64
    && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
}

extension Request {
  /// The inbox sentence in the past tense, for a request already answered:
  /// "tasks wanted to change this task", "review asked to post it".
  public var askedSentence: String {
    switch kind {
    case .change: "\(plugin) wanted to change this \(noun)"
    case .add: "\(plugin) wanted to add this \(noun)"
    case .remove: "\(plugin) wanted to remove this \(noun)"
    case .action(let verb): "\(plugin) asked to \(verb) it"
    }
  }

  /// The first line of the text a request carries that is not blank or
  /// front matter, or nil when it carries none.
  public var summary: String? {
    guard let text else { return nil }
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false)[...]
    if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
      lines = lines[(end + 1)...]
    }
    return lines.lazy.map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
  }
}
