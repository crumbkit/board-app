// The questions and requests the Mac shared, as the inbox shows them, the
// requests' threads, and Board's refusals of answers to questions.
import Foundation
import Requests
import os

/// The inbox's log, which Console shows under this subsystem and category.
private let log = Logger(subsystem: "com.stemmacorp.board", category: "inbox")

@MainActor
@Observable
final class PhoneRequests {
  private(set) var inbox: Inbox
  /// When the Mac last shared, or nil before it ever has.
  private(set) var shared: Date?
  /// Requests whose answer is on its way, so a second answer sends nothing.
  private(set) var sending: Set<String> = []
  /// Requests answered here, hidden until the Mac removes them.
  private var answered: Set<String> = []
  /// Every request read since launch, so a request screen still has its
  /// request while it closes after the request leaves the inbox.
  private var known: [String: Request] = [:]
  /// Each request's thread, by request id.
  private var threads: [String: RequestThread] = [:]
  /// Replies sent from this phone, shown until Board holds them.
  private(set) var sent: [PhoneReply] = []
  /// Questions answered here, by id, marked as sending until they leave the
  /// list or Board refuses the answer.
  private(set) var answering: Set<String> = []
  /// Every question read since launch, so a question screen still has its
  /// question while it closes.
  private var knownQuestions: [String: Question] = [:]
  /// When an answer to a question was last sent, which shows the banner.
  private(set) var answerSent: Date?
  /// Board's refusals not yet shown, oldest first. The inbox shows the first
  /// as an alert.
  private(set) var refusals: [QuestionRefused] = []
  /// Refusals shown here, so one is not shown again while its record is
  /// being deleted.
  private var shown: [QuestionRefused] = []
  /// How many refreshes have started a read, and the number of the one whose
  /// read was last applied, so an older read never replaces a newer one.
  private var readsStarted = 0
  private var readApplied = 0
  private let cloud: RequestCloud?

  init() {
    inbox = Inbox([])
    cloud = RequestCloud()
  }

  /// Fixed requests and threads that never refresh, for previews.
  init(
    preview requests: [Request], questions: [Question] = [],
    threads: [String: RequestThread] = [:], shared: Date? = Date(),
    answering: Set<String> = [], refusals: [QuestionRefused] = []
  ) {
    inbox = Inbox(requests, questions: questions)
    known = Dictionary(requests.map { ($0.id, $0) }) { a, _ in a }
    knownQuestions = Dictionary(questions.map { ($0.id, $0) }) { a, _ in a }
    self.answering = answering
    self.refusals = refusals
    answerSent = answering.isEmpty ? nil : Date()
    self.threads = threads
    self.shared = shared
    cloud = nil
  }

  /// A list the Mac has not refreshed for this long may be out of date. The Mac
  /// shares every 10 seconds while Board is running there.
  static let outOfDateAfter: TimeInterval = 2 * 60

  func isOutOfDate(now: Date = Date()) -> Bool {
    shared.map { now.timeIntervalSince($0) > Self.outOfDateAfter } ?? false
  }

  /// Reads the requests every 10 seconds while the inbox is on screen.
  func watch() async {
    guard let cloud else { return }
    try? await cloud.prepare()
    while !Task.isCancelled {
      await refresh()
      try? await Task.sleep(for: .seconds(10))
    }
  }

  /// Reads the requests, questions and refusals again, in one read of the
  /// changes since the last. A failed read is logged and keeps the list as it
  /// was, and the inbox says how old it is once the Mac's stamp is old
  /// enough. A read that started before the last one applied is dropped.
  func refresh() async {
    guard let cloud else { return }
    readsStarted += 1
    let number = readsStarted
    let started = Date()
    let read:
      (
        requests: [String: SharedRequest], shared: Date?, questions: [Question],
        refusals: [QuestionRefused]
      )
    do {
      read = try await cloud.inbox()
    } catch {
      log.error("The inbox could not refresh: \(error.localizedDescription, privacy: .public)")
      return
    }
    guard number > readApplied else { return }
    readApplied = number
    log.info(
      "The inbox refreshed in \(Date().timeIntervalSince(started), format: .fixed(precision: 2)) s"
    )
    var requests: [Request] = []
    for shared in read.requests.values {
      guard let request = shared.request, !answered.contains(request.id) else { continue }
      requests.append(request)
      threads[request.id] = shared.thread(for: request)
    }
    let questions = read.questions
    inbox = Inbox(RequestThread.latestOnly(requests, threads: threads), questions: questions)
    for request in inbox.requests { known[request.id] = request }
    for question in questions { knownQuestions[question.id] = question }
    // A question that left the list no longer needs its sending mark.
    answering.formIntersection(questions.map(\.id))
    shared = read.shared
    for refused in read.refusals where !shown.contains(refused) {
      answering.remove(refused.question)
      if !refusals.contains(refused) { refusals.append(refused) }
    }
  }

  /// The question with this id, waiting or read earlier.
  func question(_ id: String) -> Question? { knownQuestions[id] }

  /// Sends the owner's answer to a question. It is not signed. The question
  /// stays in the list, marked as sending, until the Mac records the answer.
  /// The mark starts before the save, so a second tap during the save sends
  /// nothing, and a save that throws clears it so the owner can try again.
  func answer(_ question: Question, choice: QuestionChoice?, note: String) async throws {
    guard !answering.contains(question.id),
      let answer = QuestionAnswer(question: question, choice: choice, note: note)
    else { return }
    answering.insert(question.id)
    do {
      try await cloud?.answer(answer)
    } catch {
      answering.remove(question.id)
      log.error(
        "The answer to \(answer.path, privacy: .public) was not saved: \(error.localizedDescription, privacy: .public)"
      )
      throw error
    }
    log.info("The answer to \(answer.path, privacy: .public) was saved")
    answerSent = Date()
  }

  /// Hides the banner that says an answer was sent.
  func hideAnswerSent() { answerSent = nil }

  /// Drops the refusal the inbox has shown, and deletes its record so it is
  /// shown once.
  func dismissRefusal() {
    guard !refusals.isEmpty else { return }
    let refused = refusals.removeFirst()
    shown.append(refused)
    Task { try? await cloud?.finish(refused) }
  }

  /// The request with this id, waiting or read earlier.
  func request(_ id: String) -> Request? { known[id] }

  /// The request's thread, with the replies sent from here that Board does
  /// not hold yet.
  func thread(for request: Request) -> RequestThread {
    (threads[request.id] ?? RequestThread(request: request)).adding(sent)
  }

  /// Whether a reply in the request's thread was sent from here and is not
  /// in the board yet.
  func isWaiting(_ reply: RequestThread.Reply, in request: Request) -> Bool {
    !(threads[request.id]?.replies.contains { $0.path == reply.path } ?? false)
      && sent.contains { $0.path == reply.path }
  }

  /// Sends a reply to the request's latest version. It approves and refuses
  /// nothing; the request stays open.
  func reply(to request: Request, text: String) async throws {
    let effect = thread(for: request).latest?.id ?? request.id
    guard let reply = PhoneReply(effect: effect, text: text, sent: Date()) else { return }
    try await cloud?.reply(reply)
    sent.append(reply)
  }

  /// Signs the request's statement with Face ID or Touch ID and sends the
  /// approval. Throws when the owner cancels it or iCloud refuses the answer.
  func approve(_ request: Request) async throws {
    guard thread(for: request).isApprovable(request) else { throw NotLatest() }
    guard sending.insert(request.id).inserted else { return }
    defer { sending.remove(request.id) }
    let effect = request.effect
    let signature = try await Task.detached { try await PhoneKey.approve(effect) }.value
    try await send(
      RequestAnswer(id: request.id, approve: true, reason: nil, signature: signature))
  }

  /// Sends a refusal, which is not signed.
  func refuse(_ request: Request, reason: String) async throws {
    guard sending.insert(request.id).inserted else { return }
    defer { sending.remove(request.id) }
    let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    try await send(
      RequestAnswer(
        id: request.id, approve: false, reason: reason.isEmpty ? nil : reason, signature: nil))
  }

  /// Sends the answer and removes the request from the inbox, which is all
  /// the owner sees of it.
  private func send(_ answer: RequestAnswer) async throws {
    try await cloud?.answer(answer)
    answered.insert(answer.id)
    inbox = Inbox(inbox.requests.filter { $0.id != answer.id })
  }
}

/// Thrown when Approve is pressed on a version that a later one replaces.
struct NotLatest: LocalizedError {
  var errorDescription: String? {
    "A later version of this request is waiting. Only the latest version can be approved."
  }
}
