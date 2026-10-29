// The requests the Mac shared, as the inbox shows them.
import Foundation
import Requests

@MainActor
@Observable
final class PhoneRequests {
  private(set) var inbox: Inbox
  /// When the Mac last shared, or nil before it ever has.
  private(set) var shared: Date?
  private let cloud: RequestCloud?

  init() {
    inbox = Inbox([])
    cloud = RequestCloud()
  }

  /// Fixed requests that never refresh, for previews.
  init(preview requests: [Request], shared: Date? = Date()) {
    inbox = Inbox(requests)
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
    inbox = Inbox(read.requests.values.compactMap(\.request))
    shared = read.shared
  }
}
