// Shares the personal board's pending effects with the phone, and hands the
// phone's answers to `board answer`. It has no window of its own: it runs
// while Board's window is open on the Mac. Board checks every signature.
import Foundation
import SSHSig

@MainActor
final class RequestRelay {
  private let cloud = RequestCloud()
  private let home = FileManager.default.homeDirectoryForCurrentUser

  /// Shares and answers every 10 seconds until the app quits.
  func run() async {
    try? await cloud.prepare()
    while !Task.isCancelled {
      do {
        let pending = try await pendingRequests()
        try await cloud.share(pending)
        for answer in try await cloud.answers() {
          // An answer whose request is no longer pending is dropped unread.
          let delivered = pending[answer.id] != nil ? await deliver(answer) : false
          try await cloud.finish(answer.id, answered: delivered)
        }
      } catch {
        log("Board could not share requests: \(error.localizedDescription)")
      }
      try? await Task.sleep(for: .seconds(10))
    }
  }

  /// The personal board's root, from Board's config.
  private func personalBoard() throws -> URL {
    let file = home.appendingPathComponent(".config/board/config.json")
    let config = try JSONValue.parse(Data(contentsOf: file))
    guard let personal = config["personal"]?.string else {
      throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: file.path])
    }
    return URL(fileURLWithPath: personal)
  }

  /// The committed files under `effects/pending/`, by the id each hashes to.
  /// A file whose name is not its effect's id is left out.
  private func pendingRequests() async throws -> [String: SharedRequest] {
    let root = try personalBoard()
    let names = try await git(root, ["ls-tree", "--name-only", "HEAD", "effects/pending/"])
    var requests: [String: SharedRequest] = [:]
    for file in names.split(separator: "\n").map(String.init) where file.hasSuffix(".json") {
      guard let bytes = try? await gitData(root, ["show", "HEAD:" + file]),
        let effect = try? Effect(json: bytes), file == "effects/pending/\(effect.id).json"
      else { continue }
      let seconds = try await git(root, ["log", "-1", "--format=%ct", "--", file])
      let board = URL(fileURLWithPath: effect.board)
      requests[effect.id] = SharedRequest(
        effect: bytes, boardName: await boardName(board),
        asked: Date(timeIntervalSince1970: TimeInterval(seconds.trimmed) ?? 0),
        prior: await prior(effect, in: board), current: await current(effect, in: board),
        currentContent: effect.content == nil ? await currentContent(effect, in: board) : nil)
    }
    return requests
  }

  /// `owner/name` from the board's origin, or the directory's name.
  private func boardName(_ board: URL) async -> String {
    guard let url = try? await git(board, ["remote", "get-url", "origin"]).trimmed, !url.isEmpty
    else { return board.lastPathComponent }
    let path = url.replacingOccurrences(of: ".git", with: "", options: .anchored.union(.backwards))
    let parts = path.split(whereSeparator: { $0 == "/" || $0 == ":" })
    return parts.suffix(2).joined(separator: "/")
  }

  private func prior(_ effect: Effect, in board: URL) async -> Data? {
    guard let prior = effect.prior, prior.allSatisfy({ $0.isASCII && $0.isHexDigit }),
      prior.count >= 7
    else {
      return nil
    }
    return try? await gitData(board, ["cat-file", "blob", prior])
  }

  /// The blob at the effect's path on HEAD, trying the path as written and
  /// then with `.json`, since a logical path leaves that out.
  private func current(_ effect: Effect, in board: URL) async -> String? {
    let file = String(effect.path.drop { $0 == "/" })
    for candidate in [file, file + ".json"] {
      if let blob = try? await git(board, ["rev-parse", "--verify", "-q", "HEAD:" + candidate]) {
        return blob.trimmed
      }
    }
    return nil
  }

  /// The file at a plain action's path on HEAD, which the phone shows as what
  /// the action would use now.
  private func currentContent(_ effect: Effect, in board: URL) async -> Data? {
    let file = String(effect.path.drop { $0 == "/" })
    for candidate in [file, file + ".json"] {
      if let data = try? await gitData(board, ["show", "HEAD:" + candidate]) { return data }
    }
    return nil
  }

  /// Runs `board --personal answer`, with the phone's signature on stdin for
  /// an approval. True when Board recorded the answer.
  private func deliver(_ answer: RequestAnswer) async -> Bool {
    let board = home.appendingPathComponent(".local/bin/board")
    var arguments = ["--personal", "answer", answer.id]
    var input: Data?
    if answer.approve {
      guard let signature = answer.signature else { return false }
      arguments += ["approve", "--signature", "-"]
      input = Data(signature.utf8)
    } else {
      arguments += ["refuse"]
      if let reason = answer.reason, !reason.isEmpty { arguments += ["--reason=" + reason] }
    }
    do {
      _ = try await runProcess(board, arguments, input: input)
      return true
    } catch {
      log("board answer \(answer.id) failed: \(error.localizedDescription)")
      return false
    }
  }

  private func git(_ directory: URL, _ arguments: [String]) async throws -> String {
    String(decoding: try await gitData(directory, arguments), as: UTF8.self)
  }

  private func gitData(_ directory: URL, _ arguments: [String]) async throws -> Data {
    try await runProcess(URL(fileURLWithPath: "/usr/bin/git"), ["-C", directory.path] + arguments)
  }

  private func log(_ message: String) {
    FileHandle.standardError.write(Data("Board: \(message)\n".utf8))
  }
}

struct ProcessFailure: LocalizedError {
  let command: String
  let status: Int32
  let output: String
  var errorDescription: String? { "\(command) exited \(status): \(output)" }
}

/// Runs `program` off the main thread and returns its stdout, or throws with
/// its stderr when it exits non-zero. It reads stderr alongside stdout, so a
/// chatty child cannot fill a pipe and stall, and stops a child that runs
/// longer than 60 seconds.
func runProcess(_ program: URL, _ arguments: [String], input: Data? = nil) async throws -> Data {
  try await Task.detached { try runBlocking(program, arguments, input: input) }.value
}

private func runBlocking(_ program: URL, _ arguments: [String], input: Data?) throws -> Data {
  let process = Process()
  process.executableURL = program
  process.arguments = arguments
  let output = Pipe()
  let errors = Pipe()
  let stdin = Pipe()
  process.standardOutput = output
  process.standardError = errors
  process.standardInput = stdin
  try process.run()
  let timeout = DispatchWorkItem { process.terminate() }
  DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: timeout)
  defer { timeout.cancel() }
  let message = Pipe.Collected()
  let reading = DispatchGroup()
  DispatchQueue.global().async(group: reading) {
    message.data = errors.fileHandleForReading.readDataToEndOfFile()
  }
  if let input { stdin.fileHandleForWriting.write(input) }
  try stdin.fileHandleForWriting.close()
  let data = output.fileHandleForReading.readDataToEndOfFile()
  reading.wait()
  process.waitUntilExit()
  guard process.terminationStatus == 0 else {
    throw ProcessFailure(
      command: program.lastPathComponent, status: process.terminationStatus,
      output: String(decoding: message.data, as: UTF8.self))
  }
  return data
}

extension Pipe {
  /// Bytes one reader thread fills and another reads after the group waits.
  fileprivate final class Collected: @unchecked Sendable {
    var data = Data()
  }
}

extension String {
  fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
