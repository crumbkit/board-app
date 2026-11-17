import Foundation
import Testing
import os

@testable import Launcher

/// The runner hands each line a command prints to a line handler as it
/// arrives, as well as returning the whole output at the end.
private final class Lines: Sendable {
  private let lines = OSAllocatedUnfairLock<[RunLine]>(initialState: [])
  var all: [RunLine] { lines.withLock { $0 } }
  func add(_ line: RunLine) { lines.withLock { $0.append(line) } }
  func text(_ stream: RunStream) -> [String] { all.filter { $0.stream == stream }.map(\.text) }
}

@Test func each_line_reaches_the_handler_with_its_stream() async {
  let lines = Lines()
  let result = await Runner().run(
    ["/bin/sh", "-c", "echo one; echo two >&2; echo three"], lines: lines.add)
  #expect(result.outcome == .exited(status: 0))
  #expect(lines.text(.stdout) == ["one", "three"])
  #expect(lines.text(.stderr) == ["two"])
  #expect(result.stdout == Data("one\nthree\n".utf8))
}

@Test func a_line_printed_in_pieces_arrives_whole() async {
  let lines = Lines()
  _ = await Runner().run(
    ["/bin/sh", "-c", "printf 'ab'; sleep 0.2; printf 'c\\nd'"], lines: lines.add)
  #expect(lines.text(.stdout) == ["abc", "d"])
}

@Test func a_line_arrives_while_the_command_still_runs() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let answer = directory.appendingPathComponent("answer").path
  // The command waits for a file that only the handler writes, so the run
  // ends only when the handler saw the first line before the command exited.
  let result = await Runner(timeout: .seconds(20)).run(
    ["/bin/sh", "-c", "echo ready; while [ ! -f \"$0\" ]; do sleep 0.05; done; echo seen", answer],
    lines: { line in
      if line.text == "ready" { FileManager.default.createFile(atPath: answer, contents: nil) }
    })
  #expect(result.outcome == .exited(status: 0))
  #expect(result.stdout == Data("ready\nseen\n".utf8))
}

@Test func no_line_past_the_cap_reaches_the_handler() async {
  let lines = Lines()
  let result = await Runner(cap: 8).run(
    ["/bin/sh", "-c", "echo 1234; echo 5678; echo 9999"], lines: lines.add)
  #expect(result.outcome == .overCap)
  #expect(lines.text(.stdout) == ["1234", "567"])
}
