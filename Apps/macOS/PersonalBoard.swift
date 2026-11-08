// The personal board as the Mac reads it: its root from Board's config, its
// committed files through git, and the answers Board recorded in it. Every
// read is of HEAD, so a file not yet committed is not shown.
import Foundation
import Requests
import SSHSig

import struct Launcher.Runner

/// A request the owner answered, with when Board recorded the answer.
struct AnsweredRequest: Identifiable, Sendable {
  let request: Request
  let answer: SeenAnswer
  let at: Date
  var id: String { request.id }
}

enum PersonalBoard {
  static let home = FileManager.default.homeDirectoryForCurrentUser
  static var board: URL { home.appendingPathComponent(".local/bin/board") }

  /// Runs git and Board for the relay. A hung call is killed at 60 seconds
  /// and one that prints more than 16 MB is stopped.
  private static let runner = Runner(timeout: .seconds(60), cap: 16_000_000)

  /// The personal board's root, from Board's config.
  static func root() throws -> URL {
    let file = home.appendingPathComponent(".config/board/config.json")
    let config = try JSONValue.parse(Data(contentsOf: file))
    guard let personal = config["personal"]?.string else {
      throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: file.path])
    }
    return URL(fileURLWithPath: personal)
  }

  /// `owner/name` from the board's origin, or the directory's name.
  static func name(_ board: URL) async -> String {
    guard let url = try? await git(board, ["remote", "get-url", "origin"]).trimmed, !url.isEmpty
    else { return board.lastPathComponent }
    let path = url.replacingOccurrences(of: ".git", with: "", options: .anchored.union(.backwards))
    let parts = path.split(whereSeparator: { $0 == "/" || $0 == ":" })
    return parts.suffix(2).joined(separator: "/")
  }

  /// The answers committed under `effects/seen/` since `since`, newest first,
  /// each with its effect from `effects/answered/`. An answer whose effect is
  /// missing or does not hash to its id is left out. The seen record and the
  /// effect of an answer in `known` are not read again, since those files are
  /// named by their content's hash; its time and board name are read afresh.
  static func answered(since: Date, known: [AnsweredRequest] = []) async throws
    -> [AnsweredRequest]
  {
    let known = Dictionary(known.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let root = try root()
    let log = try await git(
      root,
      [
        "log", "--since=@\(Int(since.timeIntervalSince1970))", "--diff-filter=A",
        "--format=%ct", "--name-only", "HEAD", "--", "effects/seen/",
      ])
    var names: [URL: String] = [:]
    var out: [AnsweredRequest] = []
    for (id, at) in SeenAnswer.times(log) {
      let answer: SeenAnswer
      let effect: Effect
      if let cached = known[id] {
        (answer, effect) = (cached.answer, cached.request.effect)
      } else {
        guard
          let seen = try? SeenAnswer(
            json: await gitData(root, ["show", "HEAD:effects/seen/\(id).json"])),
          seen.effect == id,
          let bytes = try? await gitData(root, ["show", "HEAD:effects/answered/\(id).json"]),
          let parsed = try? Effect(json: bytes), parsed.id == id
        else { continue }
        (answer, effect) = (seen, parsed)
      }
      let board = URL(fileURLWithPath: effect.board)
      if names[board] == nil { names[board] = await name(board) }
      out.append(
        AnsweredRequest(
          request: Request(
            effect: effect, boardName: names[board] ?? "",
            asked: effect.asked.flatMap(rfc3339) ?? at, priorContent: nil, current: nil),
          answer: answer, at: at))
    }
    return out
  }

  static func git(_ directory: URL, _ arguments: [String]) async throws -> String {
    String(decoding: try await gitData(directory, arguments), as: UTF8.self)
  }

  static func gitData(_ directory: URL, _ arguments: [String]) async throws -> Data {
    try await run("/usr/bin/git", ["-C", directory.path] + arguments)
  }

  static func run(_ program: String, _ arguments: [String], input: Data? = nil) async throws -> Data
  {
    try await runner.run([program] + arguments, input: input).output()
  }
}

extension String {
  var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
