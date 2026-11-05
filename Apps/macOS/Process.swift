// Runs a child process off the main thread, for git and Board.
import Foundation

struct ProcessFailure: LocalizedError {
  let command: String
  let status: Int32
  let output: String
  /// What the child printed to stdout, where `board --json` prints a refusal.
  var stdout = Data()
  var errorDescription: String? { "\(command) exited \(status): \(output)" }
}

/// Runs `program` off the main thread and returns its stdout, or throws with
/// its stderr and stdout when it exits non-zero. It reads stderr alongside stdout, so a
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
      output: String(decoding: message.data, as: UTF8.self), stdout: data)
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
  var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
