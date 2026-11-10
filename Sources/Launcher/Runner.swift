// Runs provider commands from argv, with no shell, a timeout and a cap on
// what they may print.
import Foundation

/// How a command ended.
enum RunOutcome: Sendable, Hashable {
  /// The command exited by itself.
  case exited(status: Int32)
  /// The command ran past the timeout and was killed.
  case timedOut
  /// The command printed more than the cap and was killed.
  case overCap
  /// The command could not start, with the reason.
  case notStarted(String)
}

public struct RunResult: Sendable, Hashable {
  let argv: [String]
  let outcome: RunOutcome
  /// Standard output, cut at the cap.
  let stdout: Data
  /// Standard error, cut at the cap.
  let stderr: Data

  /// What went wrong, in a sentence, or nil when the command exited 0.
  var problem: String? {
    switch outcome {
    case .exited(0): nil
    case .exited(let status): "The command exited with status \(status)"
    case .timedOut: "The command took longer than the timeout and was stopped"
    case .overCap: "The command printed more than the output cap and was stopped"
    case .notStarted(let reason): "The command could not start: \(reason)"
    }
  }

  /// The start of what the command printed, for showing beside a failure.
  func outputStart(_ limit: Int = 2000) -> String {
    let both = stderr.isEmpty ? stdout : stdout + Data("\n".utf8) + stderr
    let text = String(decoding: both.prefix(limit), as: UTF8.self)
    return both.count > limit ? text + "…" : text
  }
}

/// Runs one command at a time from argv. argv[0] must be an absolute path,
/// since no shell looks the command up.
///
/// The command runs in a process group of its own, so a timeout or the cap
/// stops everything it started, not only the command itself.
public struct Runner: Sendable {
  let timeout: Duration
  let cap: Int

  public init(timeout: Duration = .seconds(5), cap: Int = 1_000_000) {
    self.timeout = timeout
    self.cap = cap
  }

  /// Runs the command, writing `input` to its standard input when there is
  /// some. Cancelling the calling task stops the command, because the
  /// deadline's cancelled sleep returns at once, and the result then reads
  /// as timed out. A cancelled caller's command gets SIGKILL straight after
  /// SIGTERM, with no one-second gap, because the kill timer joins a
  /// cancelled group.
  @concurrent
  public func run(_ argv: [String], input: Data? = nil) async -> RunResult {
    guard let path = argv.first, path.hasPrefix("/") else {
      return RunResult(
        argv: argv, outcome: .notStarted("argv[0] must be an absolute path"), stdout: Data(),
        stderr: Data())
    }
    let out = Pipe()
    let err = Pipe()
    let stdin = input.map { _ in Pipe() }
    let pid: pid_t
    switch spawn(argv, stdin: stdin, stdout: out, stderr: err) {
    case .failure(let reason):
      return RunResult(
        argv: argv, outcome: .notStarted(reason.description), stdout: Data(), stderr: Data())
    case .success(let started):
      pid = started
    }
    if let input, let stdin { send(input, to: stdin.fileHandleForWriting) }

    return await withTaskGroup(of: Event.self) { group in
      group.addTask {
        do {
          return .exited(.exited(status: try await exitStatus(of: pid)))
        } catch {
          return .exited(.notStarted(String(describing: error)))
        }
      }
      group.addTask {
        let (data, over) = await collect(out.fileHandleForReading, cap: cap)
        return .output(.stdout, data, over: over)
      }
      group.addTask {
        let (data, over) = await collect(err.fileHandleForReading, cap: cap)
        return .output(.stderr, data, over: over)
      }
      group.addTask {
        try? await Task.sleep(for: timeout)
        return .deadline
      }

      var stdout = Data()
      var stderr = Data()
      var open = 2
      var exited = false
      var outcome: RunOutcome?
      var killScheduled = false

      /// Stops the command's whole process group: SIGTERM, then SIGKILL a
      /// second later for anything still running.
      func stop(_ reason: RunOutcome) {
        outcome = reason
        killpg(pid, SIGTERM)
        guard !killScheduled else { return }
        killScheduled = true
        group.addTask {
          try? await Task.sleep(for: .seconds(1))
          return .kill
        }
      }

      while let event = await group.next() {
        switch event {
        case .output(let stream, let data, let over):
          switch stream {
          case .stdout: stdout = data
          case .stderr: stderr = data
          }
          open -= 1
          if over {
            if !exited { stop(.overCap) }
            // A command that printed past the cap and exited at once is
            // still over it, so cut output never reads as success.
            outcome = .overCap
          }
        case .deadline:
          if !exited && outcome == nil { stop(.timedOut) }
        case .kill:
          // Cancelling the group ends the wait early, so anything left
          // behind dies when the run ends after a stop.
          killpg(pid, SIGKILL)
        case .exited(let ended):
          exited = true
          if outcome == nil { outcome = ended }
          // A child the command left behind can hold a pipe open. Its
          // output stops counting half a second after the command ends.
          group.addTask {
            try? await Task.sleep(for: .milliseconds(500))
            return .grace
          }
        case .grace:
          group.cancelAll()
        }
        if exited && open == 0 { group.cancelAll() }
      }
      return RunResult(
        argv: argv, outcome: outcome ?? .notStarted("The command did not report an exit"),
        stdout: stdout, stderr: stderr)
    }
  }
}

/// What the tasks waiting on a running command report to the loop that holds
/// its state.
private enum Event: Sendable {
  enum Stream: Sendable {
    case stdout
    case stderr
  }

  case exited(RunOutcome)
  case output(Stream, Data, over: Bool)
  case deadline
  case grace
  case kill
}

/// Starts the command in a new process group, with standard input from
/// `stdin` or /dev/null and no other descriptors inherited.
private func spawn(
  _ argv: [String], stdin: Pipe?, stdout: Pipe, stderr: Pipe
) -> Result<pid_t, SpawnError> {
  var attributes: posix_spawnattr_t?
  var actions: posix_spawn_file_actions_t?
  unsafe posix_spawnattr_init(&attributes)
  unsafe posix_spawn_file_actions_init(&actions)
  defer {
    unsafe posix_spawnattr_destroy(&attributes)
    unsafe posix_spawn_file_actions_destroy(&actions)
  }
  unsafe posix_spawnattr_setflags(
    &attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT)
  )
  unsafe posix_spawnattr_setpgroup(&attributes, 0)
  // A cooperative thread blocks most signals and the command would inherit
  // that mask, which leaves it unable to receive SIGTERM.
  var unblocked = sigset_t()
  unsafe posix_spawnattr_setsigmask(&attributes, &unblocked)
  if let stdin {
    unsafe posix_spawn_file_actions_adddup2(&actions, stdin.fileHandleForReading.fileDescriptor, 0)
  } else {
    unsafe posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
  }
  unsafe posix_spawn_file_actions_adddup2(&actions, stdout.fileHandleForWriting.fileDescriptor, 1)
  unsafe posix_spawn_file_actions_adddup2(&actions, stderr.fileHandleForWriting.fileDescriptor, 2)
  let cArgs = unsafe argv.map { unsafe strdup($0) } + [nil]
  defer { for unsafe arg in unsafe cArgs { unsafe free(arg) } }
  var pid: pid_t = 0
  let status = unsafe posix_spawn(&pid, argv[0], &actions, &attributes, cArgs, environ)
  // The parent's copies of the child's ends close either way, so the pipes
  // reach end of file when the command and its children are done.
  try? stdin?.fileHandleForReading.close()
  try? stdout.fileHandleForWriting.close()
  try? stderr.fileHandleForWriting.close()
  guard status == 0 else {
    try? stdin?.fileHandleForWriting.close()
    try? stdout.fileHandleForReading.close()
    try? stderr.fileHandleForReading.close()
    return .failure(SpawnError(code: status))
  }
  return .success(pid)
}

/// Writes `input` to the command's standard input from a thread of its own,
/// then closes it.
///
/// A blocked write on this thread lasts until the command and everything
/// holding its standard input have gone. An input larger than the pipe
/// holds, sent to a child left behind that holds stdin and never reads, keeps
/// one thread until that child ends. A non-blocking writer would replace
/// this thread.
private func send(_ input: Data, to handle: FileHandle) {
  _ = fcntl(handle.fileDescriptor, F_SETNOSIGPIPE, 1)
  Thread.detachNewThread {
    // Nil is right here: a command that stops reading simply does not get
    // the rest.
    try? handle.write(contentsOf: input)
    try? handle.close()
  }
}

/// Waits for the command on a thread of its own, since `waitpid` blocks.
private func exitStatus(of pid: pid_t) async throws -> Int32 {
  try await withCheckedThrowingContinuation { continuation in
    Thread.detachNewThread {
      var status: Int32 = 0
      var waited = unsafe waitpid(pid, &status, 0)
      while waited == -1, errno == EINTR { waited = unsafe waitpid(pid, &status, 0) }
      guard waited != -1 else {
        continuation.resume(throwing: SpawnError(code: errno))
        return
      }
      // A plain exit keeps its code; a signal reads as 128 plus its number,
      // as shells report it.
      continuation.resume(
        returning: status & 0x7F == 0 ? (status >> 8) & 0xFF : 128 + (status & 0x7F))
    }
  }
}

/// Reads a pipe up to the cap. It returns as soon as a chunk overflows the
/// room, and returns what it has at end of file or when cancelled.
///
/// Only the consumer counts bytes, so the stream's buffer can pass the cap
/// while no cooperative thread is free to run the consumer. Counting bytes in
/// the readability handler under an `OSAllocatedUnfairLock` and finishing the
/// stream at the cap would replace this.
private func collect(_ handle: FileHandle, cap: Int) async -> (Data, over: Bool) {
  let chunks = AsyncStream<Data> { continuation in
    continuation.onTermination = { _ in handle.readabilityHandler = nil }
    handle.readabilityHandler = { handle in
      let chunk = handle.availableData
      if chunk.isEmpty {
        continuation.finish()
      } else {
        continuation.yield(chunk)
      }
    }
  }
  var data = Data()
  for await chunk in chunks {
    let room = cap - data.count
    data.append(chunk.prefix(max(room, 0)))
    if chunk.count > room { return (data, over: true) }
  }
  return (data, over: false)
}

private struct SpawnError: Error, CustomStringConvertible {
  let code: Int32
  var description: String { unsafe String(cString: strerror(code)) }
}

/// A command that did not exit 0, with what it printed.
public struct RunFailure: LocalizedError, Sendable {
  /// The last path component of the command.
  let command: String
  /// What went wrong, in a sentence.
  let problem: String
  /// Standard error, as text.
  public let output: String
  /// Standard output, where `board --json` prints a refusal.
  public let stdout: Data
  public var errorDescription: String? { "\(command): \(problem): \(output)" }
}

extension RunResult {
  /// Standard output when the command exited 0.
  public func output() throws(RunFailure) -> Data {
    guard let problem else { return stdout }
    throw RunFailure(
      command: URL(fileURLWithPath: argv.first ?? "").lastPathComponent, problem: problem,
      output: String(decoding: stderr, as: UTF8.self), stdout: stdout)
  }
}
