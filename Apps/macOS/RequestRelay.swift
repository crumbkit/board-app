// Shares the personal board's pending effects and their threads, and the
// agents' open questions, with the phone. It hands the phone's answers to
// `board answer` or `plans.answer`, and puts its replies in the personal
// board. The app starts it at launch and it runs until the app
// quits, whether or not the window is open. It keeps what it last did, so the
// window can show it. Board checks every signature.
import CloudKit
import Foundation
import Requests
import SSHSig

@MainActor
@Observable
final class RequestRelay {
  /// The requests waiting in the personal board, as the phone's inbox shows
  /// them: newest first, one per thread.
  private(set) var waiting = Inbox([])
  /// Each waiting request's thread, by id.
  private(set) var threads: [String: RequestThread] = [:]
  /// When iCloud first held each waiting request, by id.
  private(set) var sharedSince: [String: Date] = [:]
  /// When the relay last shared to iCloud, or nil before it has.
  private(set) var lastShared: Date?
  /// Why the last share failed, or nil when it worked.
  private(set) var cloudProblem: CloudProblem?
  /// Why the personal board could not be read, or nil when it could.
  private(set) var boardProblem: String?
  /// Why `plans.open` failed, or nil when it worked, so it is logged once.
  @ObservationIgnored private var questionProblem: String?

  @ObservationIgnored private let cloud = RequestCloud()
  @ObservationIgnored private var prepared = false
  /// The answers to questions Board recorded since the app launched.
  @ObservationIgnored private var recordedAnswers = RecordedAnswers()
  private var board: URL { PersonalBoard.board }

  /// Reads the board, then shares and answers, every 10 seconds until the
  /// app quits. A build that may not use iCloud still reads the board, so the
  /// window lists what waits, and says why it shares nothing.
  func run() async {
    while !Task.isCancelled {
      await step()
      try? await Task.sleep(for: .seconds(10))
    }
  }

  private func step() async {
    let pending: [String: SharedRequest]
    do {
      pending = try await pendingRequests()
      boardProblem = nil
    } catch {
      let problem = "Board could not read the personal board: \(error.localizedDescription)"
      if problem != boardProblem { log(problem) }
      boardProblem = problem
      // Nothing is shared while the board cannot be read, so the window
      // shows no list it cannot vouch for.
      waiting = Inbox([])
      threads = [:]
      return
    }
    show(pending)
    do {
      if !prepared {
        try await cloud.prepare()
        prepared = true
      }
      let now = Date()
      sharedSince = try await cloud.share(pending, now: now)
      lastShared = now
      cloudProblem = nil
      for answer in try await cloud.answers() {
        // An answer whose request is no longer pending is dropped unread.
        let delivered = pending[answer.id] != nil ? await deliver(answer) : false
        try await cloud.finish(answer.id, answered: delivered)
      }
      // A reply Board could not take stays in iCloud and is tried again.
      for reply in try await cloud.replies() where await put(reply) {
        try await cloud.finish(reply)
      }
      // A failed listing leaves the shared questions as they were.
      if let questions = await openQuestions() { try await cloud.share(questions) }
      for answer in try await cloud.questionAnswers() {
        // A copy of an answer Board already recorded is deleted unrecorded,
        // so Board does not refuse it as already answered.
        if recordedAnswers.isRepeat(answer) {
          log("Dropped a repeated answer to \(answer.path)")
          try await cloud.finish(answer)
          continue
        }
        switch await record(answer) {
        case .recorded:
          recordedAnswers.remember(answer)
          try await cloud.finish(answer)
        case .refused(let failure):
          try await cloud.finish(answer, refused: QuestionRefused(answer: answer, failure: failure))
        // An answer Board neither took nor refused stays in iCloud and is
        // tried again.
        case .failed: break
        }
      }
    } catch {
      let problem = CloudProblem(error)
      // A problem is logged when it starts, not on every try.
      if problem != cloudProblem {
        log("Board could not share requests: \(error.localizedDescription)")
      }
      cloudProblem = problem
    }
  }

  /// Keeps the requests and threads the window shows. A request no longer
  /// pending loses its share time.
  private func show(_ pending: [String: SharedRequest]) {
    var requests: [Request] = []
    var threads: [String: RequestThread] = [:]
    for shared in pending.values {
      guard let request = shared.request else { continue }
      requests.append(request)
      threads[request.id] = shared.thread(for: request)
    }
    waiting = Inbox(RequestThread.latestOnly(requests, threads: threads))
    self.threads = threads
    sharedSince = sharedSince.filter { pending[$0.key] != nil }
  }

  /// The committed files under `effects/pending/`, by the id each hashes to.
  /// A file whose name is not its effect's id is left out.
  private func pendingRequests() async throws -> [String: SharedRequest] {
    let root = try PersonalBoard.root()
    let names = try await PersonalBoard.git(
      root, ["ls-tree", "--name-only", "HEAD", "effects/pending/"])
    var requests: [String: SharedRequest] = [:]
    for file in names.split(separator: "\n").map(String.init) where file.hasSuffix(".json") {
      guard let bytes = try? await PersonalBoard.gitData(root, ["show", "HEAD:" + file]),
        let effect = try? Effect(json: bytes), file == "effects/pending/\(effect.id).json"
      else { continue }
      let seconds = try await PersonalBoard.git(root, ["log", "-1", "--format=%ct", "--", file])
      let board = URL(fileURLWithPath: effect.board)
      requests[effect.id] = SharedRequest(
        effect: bytes, boardName: await PersonalBoard.name(board),
        asked: Date(timeIntervalSince1970: TimeInterval(seconds.trimmed) ?? 0),
        prior: await prior(effect, in: board), current: await current(effect, in: board),
        currentContent: effect.content == nil ? await currentContent(effect, in: board) : nil,
        thread: await thread(effect.id))
    }
    return requests
  }

  private func prior(_ effect: Effect, in board: URL) async -> Data? {
    guard let prior = effect.prior, prior.allSatisfy({ $0.isASCII && $0.isHexDigit }),
      prior.count >= 7
    else {
      return nil
    }
    return try? await PersonalBoard.gitData(board, ["cat-file", "blob", prior])
  }

  /// The blob at the effect's path on HEAD, trying the path as written and
  /// then with `.json`, since a logical path leaves that out.
  private func current(_ effect: Effect, in board: URL) async -> String? {
    let file = String(effect.path.drop { $0 == "/" })
    for candidate in [file, file + ".json"] {
      if let blob = try? await PersonalBoard.git(
        board, ["rev-parse", "--verify", "-q", "HEAD:" + candidate])
      {
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
      if let data = try? await PersonalBoard.gitData(board, ["show", "HEAD:" + candidate]) {
        return data
      }
    }
    return nil
  }

  /// What `board call requests.thread` prints for the effect, or nil when
  /// Board refuses, as a Board without the requests plugin does.
  private func thread(_ id: String) async -> Data? {
    try? await runProcess(
      board, ["--personal", "call", "requests.thread", "--effect", id, "--json"])
  }

  /// Puts the phone's reply in the personal board as the owner. It is outside
  /// `effects/`, so it needs no signature, and it answers nothing. True when
  /// the board holds the reply, including when an earlier put stored it and
  /// Board refuses this one with `board::put::stale`.
  private func put(_ reply: PhoneReply) async -> Bool {
    do {
      _ = try await runProcess(
        board, ["--personal", "put", reply.path, "--expect", "none"], input: reply.record)
      return true
    } catch let failure as ProcessFailure where failure.output.contains("board::put::stale") {
      return true
    } catch {
      log("board put \(reply.path) failed: \(error.localizedDescription)")
      return false
    }
  }

  /// Runs `board --personal answer`, with the phone's signature on stdin for
  /// an approval. True when Board recorded the answer.
  private func deliver(_ answer: RequestAnswer) async -> Bool {
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

  /// The open questions `plans.open` lists, each named by the board it
  /// concerns, or nil when Board could not list them, such as a Board
  /// without `plans.open`. Requests are relayed either way.
  private func openQuestions() async -> [Question]? {
    var questions: [Question]
    do {
      let report = try await runProcess(
        board, ["--personal", "call", "plans.open", "--limit", "1000", "--json"])
      questions = try Question.open(report: report)
      questionProblem = nil
    } catch {
      let problem = "Board could not list open questions: \(error.localizedDescription)"
      if problem != questionProblem { log(problem) }
      questionProblem = problem
      return nil
    }
    let root = try? PersonalBoard.root()
    var names: [String: String] = [:]
    for index in questions.indices {
      let mount = questions[index].mount
      let key = mount ?? ""
      if names[key] == nil { names[key] = await boardName(mount: mount, root: root) }
      questions[index].boardName = names[key] ?? ""
    }
    return questions
  }

  /// The git remote of the mount's repository, or the personal board's when
  /// the question has no mount. A mount whose repository the Mac cannot read
  /// is named by its last segment.
  private func boardName(mount: String?, root: URL?) async -> String {
    guard let root else { return mount.map(Mount.fallbackName) ?? "" }
    guard let mount else { return await PersonalBoard.name(root) }
    guard let file = Mount.file(mount),
      let record = try? await PersonalBoard.gitData(root, ["show", "HEAD:" + file]),
      let repository = Mount.repository(record)
    else { return Mount.fallbackName(mount) }
    return await PersonalBoard.name(URL(fileURLWithPath: repository))
  }

  private enum Outcome {
    case recorded
    case refused(BoardFailure)
    case failed
  }

  /// Runs `plans.answer` with the phone's answer. Board's refusal is what it
  /// prints on stdout with `--json`.
  private func record(_ answer: QuestionAnswer) async -> Outcome {
    do {
      _ = try await runProcess(board, answer.arguments)
      return .recorded
    } catch let failure as ProcessFailure {
      if let refusal = try? BoardFailure(json: failure.stdout), refusal.isFinal {
        log("Board refused the answer to \(answer.path): \(refusal.code)")
        return .refused(refusal)
      }
      log("plans.answer \(answer.path) failed: \(failure.localizedDescription)")
      return .failed
    } catch {
      log("plans.answer \(answer.path) failed: \(error.localizedDescription)")
      return .failed
    }
  }

  private func log(_ message: String) {
    FileHandle.standardError.write(Data("Board: \(message)\n".utf8))
  }
}

/// Why the relay could not share, as the window words it.
struct CloudProblem: Equatable {
  /// What went wrong, in one sentence.
  let message: String
  /// What the owner can do about it, when the relay knows.
  let advice: String?

  init(_ error: Error) {
    if let error = error as? CKError, error.code == .notAuthenticated {
      message = "This Mac is not signed in to iCloud."
      advice =
        "Sign in with the same Apple Account as your iPhone, and Board shares again within 10 seconds."
    } else {
      message = error.localizedDescription
      advice = nil
    }
  }
}
