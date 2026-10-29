// Requests with real diffs, for previews: a task whose dates move, a control
// whose budget rises, a plain review action, and a task with a long title.
import Foundation
import Requests
import SSHSig

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

  static let taskAfter = taskBefore.replacingOccurrences(of: "2026-10-29", with: "2026-11-02")
    .replacingOccurrences(of: "2026-10-25", with: "2026-10-29")

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
      board: "owner/board-src", minutesAgo: 108)
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

  static var all: [Request] { [task, control, review, longTask] }

  private static func request(
    fields: [String: Any], board: String = "owner/board", prior: String? = nil,
    current: String? = nil, minutesAgo: Double
  ) -> Request {
    var object = fields
    object["$type"] = "board/effect/v1"
    object["board"] =
      board == "owner/board" ? "/Users/ana/Code/board" : "/Users/ana/Code/board"
    let data = try! JSONSerialization.data(withJSONObject: object)
    return Request(
      effect: try! Effect(json: data), boardName: board,
      asked: Date().addingTimeInterval(-minutesAgo * 60), priorContent: prior.map { Data($0.utf8) },
      current: current)
  }
}
