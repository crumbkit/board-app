// Requests with real diffs, for previews: a task whose dates move, in a
// thread of two versions and a reply, a control whose budget rises, a plain
// review action, and a task with a long title.
import Foundation
import Requests
import SSHSig
import UIKit

enum PreviewRequests {
  static let taskBefore = """
    ---
    $type: "tasks/task/v2"
    title: "Write the release notes"
    status: "open"
    defer: "2026-10-29"
    reviewed: "2026-10-25"
    ---

    Collect the merged pull requests since the last tag.
    Group them by app: the Mac app first, then the iPhone app.

    Keep each line under 80 characters.

    """

  static let taskAfter = taskBefore.replacingOccurrences(of: "2026-10-29", with: "2026-11-03")
    .replacingOccurrences(of: "2026-10-25", with: "2026-10-29")

  /// The task's first version, which the owner replied to.
  static let taskFirst = taskAfter.replacingOccurrences(of: "2026-11-03", with: "2026-11-02")

  /// The task's thread: version 1 deferred to Monday, the owner's reply, and
  /// version 2, the task request, deferred to Tuesday.
  static var threads: [String: RequestThread] {
    let task = task
    let first = String(repeating: "1", count: 64)
    func asked(_ minutesAgo: Double) -> String {
      Date().addingTimeInterval(-minutesAgo * 60).formatted(
        .iso8601.year().month().day().time(includingFractionalSeconds: false)
          .dateSeparator(.dash).timeSeparator(.colon)) + ".000000Z"
    }
    func stamp(_ minutesAgo: Double) -> String {
      Date().addingTimeInterval(-minutesAgo * 60).formatted(
        .iso8601.year().month().day().time(includingFractionalSeconds: false)
          .dateSeparator(.omitted).timeSeparator(.omitted)) + "Z"
    }
    func version(_ id: String, _ text: String, _ minutesAgo: Double, latest: Bool) -> [String: Any]
    {
      [
        "id": id, "asked": asked(minutesAgo), "record": NSNull(), "text": text,
        "pending": true, "latest": latest, "answer": NSNull(),
      ]
    }
    let output: [String: Any] = [
      "board": task.effect.board, "plugin": "tasks", "op": "put", "path": task.effect.path,
      "versions": [
        version(first, taskFirst, 7, latest: false), version(task.id, taskAfter, 1, latest: true),
      ],
      "replies": [
        [
          "effect": first, "path": "/requests/replies/\(first)/\(stamp(4))",
          "text": "Monday's full. Defer it to Tuesday instead.",
        ]
      ],
    ]
    let report: [String: Any] = [
      "schema": "board/call-report/v2",
      "data": ["capability": "thread", "plugin": "requests", "output": output], "failures": [],
    ]
    let data = try! JSONSerialization.data(withJSONObject: report)
    return [task.id: try! RequestThread(report: data, request: task)]
  }

  static let controlBefore = """
    {
      "$type": "controls/control/v1",
      "paths": [
        "repos/board-app/DOCS.md"
      ],
      "purpose": "An agent reads the root map and then only the docs its task needs.",
      "requirement": "DOCS.md holds at most 400 words: one line per child doc saying what it covers.",
      "rule": {
        "budget": "words",
        "max": 400
      }
    }

    """

  static var task: Request {
    request(
      fields: [
        "plugin": "tasks", "op": "put", "path": "/tasks/write-the-release-notes.md",
        "prior": "4e5b030", "text": taskAfter,
      ], prior: taskBefore, current: "4e5b030", minutesAgo: 1)
  }

  static var control: Request {
    let record = controlBefore.replacingOccurrences(of: "400", with: "450")
    let json = try! JSONSerialization.jsonObject(with: Data(record.utf8))
    return request(
      fields: [
        "plugin": "controls", "op": "put", "path": "/controls/board-app/docs-map-budget",
        "prior": "177774c", "record": json,
      ], prior: controlBefore, current: "177774c", minutesAgo: 13)
  }

  static var review: Request {
    request(
      fields: ["plugin": "review", "op": "review.post", "path": "/reviews/fix-sync/report"],
      board: "crumbkit/board", minutesAgo: 108,
      currentContent: """
        Changes requested · 2 findings

        crates/board-ops/src/sync.rs:212
        A push that fails after the fetch leaves the mount pin moved, so the next sync skips commits.

        docs/architecture/writes.md
        Says sync retries once; the code retries three times.
        """)
  }

  static var longTask: Request {
    let text = taskBefore.replacingOccurrences(
      of: "Write the release notes",
      with:
        "Move every app's settings into one shared settings file, probably with a migration step")
    return request(
      fields: [
        "plugin": "tasks", "op": "put", "path": "/tasks/move-every-apps-settings.md",
        "prior": "9c1d2e3", "text": text.replacingOccurrences(of: "open", with: "waiting"),
      ], prior: text, current: "9c1d2e3", minutesAgo: 26 * 60)
  }

  /// The task after someone else changed it, so the approval would not fit.
  static var stale: Request {
    request(
      fields: [
        "plugin": "tasks", "op": "put", "path": "/tasks/write-the-release-notes.md",
        "prior": "4e5b030", "text": taskAfter,
      ], prior: taskBefore, current: "7aa01be", minutesAgo: 1)
  }

  /// The task whose old version the Mac could not read.
  static var noPrior: Request {
    request(
      fields: [
        "plugin": "tasks", "op": "put", "path": "/tasks/write-the-release-notes.md",
        "prior": "4e5b030", "text": taskAfter,
      ], prior: nil, current: "4e5b030", minutesAgo: 1)
  }

  static var all: [Request] { [task, control, review, longTask] }

  private static func request(
    fields: [String: Any], board: String = "owner/board", prior: String? = nil,
    current: String? = nil, minutesAgo: Double, currentContent: String? = nil
  ) -> Request {
    var object = fields
    object["$type"] = "board/effect/v1"
    object["board"] =
      board == "owner/board" ? "/Users/ana/Code/board" : "/Users/ana/Code/board-src"
    let data = try! JSONSerialization.data(withJSONObject: object)
    return Request(
      effect: try! Effect(json: data), boardName: board,
      asked: Date().addingTimeInterval(-minutesAgo * 60), priorContent: prior.map { Data($0.utf8) },
      current: current, currentContent: currentContent.map { Data($0.utf8) })
  }
}

/// Launch options that open the app on these requests instead of iCloud's,
/// for screenshots in the Simulator. `-fixtures` turns them on; `-open task`
/// opens a request by its name here, `-boards` opens on the Boards list,
/// `-scroll top` opens a thread scrolled to its top, `-landscape` turns the
/// screen to landscape, and `-sheet sign` or
/// `-sheet refuse` opens What You Sign or the Refuse alert. Release builds
/// ignore them.
enum Fixture {
  static var on: Bool {
    #if DEBUG
      CommandLine.arguments.contains("-fixtures")
    #else
      false
    #endif
  }

  static var boards: Bool { on && CommandLine.arguments.contains("-boards") }
  static var sheet: String? { on ? value("-sheet") : nil }
  static var scrolledUp: Bool { on && value("-scroll") == "top" }

  /// Turns the screen to landscape when `-landscape` is given.
  @MainActor static func turn() async {
    guard on, CommandLine.arguments.contains("-landscape") else { return }
    try? await Task.sleep(for: .seconds(1))
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { error in
      FileHandle.standardError.write(Data("turn: \(error)\n".utf8))
    }
  }

  /// The request `-open` names.
  static var open: Request? {
    switch on ? value("-open") : nil {
    case "task": PreviewRequests.task
    case "control": PreviewRequests.control
    case "review": PreviewRequests.review
    case "stale": PreviewRequests.stale
    case "noPrior": PreviewRequests.noPrior
    default: nil
    }
  }

  /// The inbox's requests, with the opened one in place of any that shares
  /// its id, as the stale task shares the task's.
  static var requests: [Request] {
    guard let open else { return PreviewRequests.all }
    return PreviewRequests.all.filter { $0.id != open.id } + [open]
  }

  private static func value(_ option: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else {
      return nil
    }
    return arguments[index + 1]
  }
}
