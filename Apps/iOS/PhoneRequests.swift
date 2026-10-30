// The requests the Mac shared, as the inbox shows them.
import Foundation
import Requests

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
  private let cloud: RequestCloud?

  init() {
    inbox = Inbox([])
    cloud = RequestCloud()
  }

  /// Fixed requests that never refresh, for previews.
  init(preview requests: [Request], shared: Date? = Date()) {
    inbox = Inbox(requests)
    known = Dictionary(requests.map { ($0.id, $0) }) { a, _ in a }
    self.shared = shared
    cloud = nil
  }

  /// A list the Mac has not refreshed for this long may be out of date. The Mac
  /// shares every 10 seconds while Board is open there.
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

  /// Reads the requests again. A failed read keeps the list as it was, and the
  /// inbox says how old it is once the Mac's stamp is old enough.
  func refresh() async {
    guard let cloud, let read = try? await cloud.requests() else { return }
    inbox = Inbox(read.requests.values.compactMap(\.request).filter { !answered.contains($0.id) })
    for request in inbox.requests { known[request.id] = request }
    shared = read.shared
  }

  /// The request with this id, waiting or read earlier.
  func request(_ id: String) -> Request? { known[id] }

  /// Signs the request's statement with Face ID or Touch ID and sends the
  /// approval. Throws when the owner cancels it or iCloud refuses the answer.
  func approve(_ request: Request) async throws {
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
