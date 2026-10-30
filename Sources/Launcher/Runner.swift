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
public struct Runner: Sendable {
  let timeout: Duration
  let cap: Int

  public init(timeout: Duration = .seconds(5), cap: Int = 1_000_000) {
    self.timeout = timeout
    self.cap = cap
  }

  public func run(_ argv: [String]) async -> RunResult {
    guard let path = argv.first, path.hasPrefix("/") else {
      return RunResult(
        argv: argv, outcome: .notStarted("argv[0] must be an absolute path"), stdout: Data(),
        stderr: Data())
    }
    let job = Job(argv: argv, cap: cap)
    return await withCheckedContinuation { continuation in
      job.start(timeout: timeout) { continuation.resume(returning: $0) }
    }
  }
}

/// One running command. Its state is guarded by a lock, since the pipes and
/// the wait for exit report on their own threads.
///
/// The command runs in a process group of its own, so a timeout or the cap
/// stops everything it started, not only the command itself.
private final class Job: @unchecked Sendable {
  private let argv: [String]
  private let cap: Int
  private let lock = NSLock()
  private let out = Pipe()
  private let err = Pipe()
  private var pid: pid_t = 0
  private var stdout = Data()
  private var stderr = Data()
  private var open = 2
  private var exited = false
  private var outcome: RunOutcome?
  private var done: (@Sendable (RunResult) -> Void)?

  init(argv: [String], cap: Int) {
    self.argv = argv
    self.cap = cap
  }

  func start(timeout: Duration, done: @escaping @Sendable (RunResult) -> Void) {
    self.done = done
    switch spawn() {
    case .failure(let reason):
      lock.withLock {
        outcome = .notStarted(reason.description)
        exited = true
      }
      finish(force: true)
      return
    case .success(let pid):
      self.pid = pid
    }
    out.fileHandleForReading.readabilityHandler = { [self] in read($0, into: \.stdout) }
    err.fileHandleForReading.readabilityHandler = { [self] in read($0, into: \.stderr) }
    DispatchQueue.global().async { [self] in wait() }
    let nanoseconds =
      timeout.components.seconds * 1_000_000_000 + timeout.components.attoseconds
      / 1_000_000_000
    DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(nanoseconds))) {
      [self] in stop(.timedOut)
    }
  }

  /// Starts the command in a new process group, with standard input from
  /// /dev/null and no other descriptors inherited.
  private func spawn() -> Result<pid_t, SpawnError> {
    var attributes: posix_spawnattr_t?
    var actions: posix_spawn_file_actions_t?
    posix_spawnattr_init(&attributes)
    posix_spawn_file_actions_init(&actions)
    defer {
      posix_spawnattr_destroy(&attributes)
      posix_spawn_file_actions_destroy(&actions)
    }
    posix_spawnattr_setflags(
      &attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
    posix_spawnattr_setpgroup(&attributes, 0)
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_adddup2(&actions, out.fileHandleForWriting.fileDescriptor, 1)
    posix_spawn_file_actions_adddup2(&actions, err.fileHandleForWriting.fileDescriptor, 2)
    let cArgs = argv.map { strdup($0) } + [nil]
    defer { for arg in cArgs { free(arg) } }
    var pid: pid_t = 0
    let status = posix_spawn(&pid, argv[0], &actions, &attributes, cArgs, environ)
    // The parent's write ends close either way, so the pipes reach end of
    // file when the command and its children are done.
    try? out.fileHandleForWriting.close()
    try? err.fileHandleForWriting.close()
    guard status == 0 else {
      try? out.fileHandleForReading.close()
      try? err.fileHandleForReading.close()
      return .failure(SpawnError(code: status))
    }
    return .success(pid)
  }

  private func wait() {
    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1, errno == EINTR {}
    // A plain exit keeps its code; a signal reads as 128 plus its number, as
    // shells report it.
    let code = status & 0x7F == 0 ? (status >> 8) & 0xFF : 128 + (status & 0x7F)
    lock.withLock {
      exited = true
      if outcome == nil { outcome = .exited(status: code) }
    }
    // A child the command left behind can hold a pipe open. Its output
    // stops counting half a second after the command ends.
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [self] in finish(force: true) }
    finish(force: false)
  }

  private func read(_ handle: FileHandle, into buffer: ReferenceWritableKeyPath<Job, Data>) {
    let data = handle.availableData
    var over = false
    lock.withLock {
      if data.isEmpty {
        handle.readabilityHandler = nil
        open -= 1
      } else {
        let room = cap - self[keyPath: buffer].count
        self[keyPath: buffer].append(data.prefix(max(room, 0)))
        over = data.count > room
      }
    }
    if data.isEmpty {
      finish(force: false)
    } else if over {
      stop(.overCap)
    }
  }

  /// Stops the command's whole process group: SIGTERM, then SIGKILL a
  /// second later for anything still running.
  private func stop(_ reason: RunOutcome) {
    let running = lock.withLock {
      guard !exited, outcome == nil else { return false }
      outcome = reason
      return true
    }
    guard running else { return }
    let group = pid
    killpg(group, SIGTERM)
    DispatchQueue.global().asyncAfter(deadline: .now() + 1) { killpg(group, SIGKILL) }
  }

  /// Hands back the result once the command has ended and both pipes have
  /// closed, or at once when `force` is set. It hands it back only once.
  private func finish(force: Bool) {
    let handoff: (RunResult, @Sendable (RunResult) -> Void)? = lock.withLock {
      guard exited, force || open == 0, let outcome, let done else { return nil }
      self.done = nil
      return (RunResult(argv: argv, outcome: outcome, stdout: stdout, stderr: stderr), done)
    }
    guard let (result, done) = handoff else { return }
    // Output after the hand-off is not read.
    out.fileHandleForReading.readabilityHandler = nil
    err.fileHandleForReading.readabilityHandler = nil
    done(result)
  }
}

private struct SpawnError: Error, CustomStringConvertible {
  let code: Int32
  var description: String { String(cString: strerror(code)) }
}
