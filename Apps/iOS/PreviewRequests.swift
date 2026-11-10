// Requests with real diffs, for previews: a task whose dates move, in a
// thread of two versions and a reply, a control whose budget rises, a plain
// review action, and a task with a long title.
import Foundation
import Requests
import SSHSig
import UIKit

/// The value `parse` reads from a fixture this file writes. Every fixture is
/// a literal that parses, so a failure is a broken invariant.
private func fixture<Value>(_ parse: () throws -> Value) -> Value {
  do {
    return try parse()
  } catch {
    preconditionFailure("A preview fixture does not parse: \(error)")
  }
}

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
    let data = fixture { try JSONSerialization.data(withJSONObject: report) }
    return [task.id: fixture { try RequestThread(report: data, request: task) }]
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
    let json = fixture { try JSONSerialization.jsonObject(with: Data(record.utf8)) }
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
    let data = fixture { try JSONSerialization.data(withJSONObject: object) }
    return Request(
      effect: fixture { try Effect(json: data) }, boardName: board,
      asked: Date().addingTimeInterval(-minutesAgo * 60), priorContent: prior.map { Data($0.utf8) },
      current: current, currentContent: currentContent.map { Data($0.utf8) })
  }
}

/// Real questions from `plans.open`, all under `/projects/` in the personal
/// board: two merge questions in a mounted board, a review decision with a
/// note, and a question with no recommendation.
enum PreviewQuestions {
  static let merge = Question(
    path: "/projects/board/questions/20261025T1248Z-5f31",
    question:
      "May crumbkit/board#294 (shared repo-listing and day helpers moved into python/board-plugin) and then #297 (tasks/task/v2 Markdown tasks and the tasks.available call, which syncs in-scope repos with a 5 s deadline and keeps each context's tasks in its silo) be merged? Before #297 merges, please check one thing in Reflect on your phone: it shows a tasks/ folder, and it keeps a task file's frontmatter when you edit the task.",
    asked: "2026-10-25T12:48:00Z",
    session: "local_31dd8fcd-6180-489e-80e9-e63391b9ac05",
    options: [
      .init(
        id: "merge", text: "Merge #294, then #297; I install the new board binary and start PR 3"),
      .init(id: "hold", text: "Hold them; I want to look first"),
    ],
    recommendation: "merge",
    blocks:
      "Tasks v2 PRs 3 to 5 (write calls, sweep skill, removing tasks.next and tasks.due), which build on these two.",
    why:
      "Two clean-context Opus reviews ran, and the second found nothing that must be fixed. All 7 CI checks pass on #294 (88337546) and #297 (49f7297b). #294 adds 37 net lines and #297 adds 593. Measured with one GitHub remote, a warm call takes 0.76 s at the median and 0.84 to 0.97 s at p95, within the 1.0 s budget. A cold call took 1.13 s at p95, and several remotes were not measured (/evals/tasks-available-latency). A hung remote makes later calls take about 5 s, and the README says so. Bounding Board's git fetch is a separate follow-up PR. Board's AGENTS.md leaves merges to the owner.",
    mount: "/repos/board",
    boardName: "crumbkit/board")

  static let mergeWrites = Question(
    path: "/projects/board/questions/20261025T1443Z-9c62",
    question:
      "May crumbkit/board#302 (tasks v2 write calls: tasks.add, done, defer, drop and reviewed edit task frontmatter in place, sync before writing and push after, and keep each context's tasks in its silo) be merged? Two choices I made for you: done never moves a repeating task earlier than its defer, and add refuses when two notes repos cover the remote. After it merges, please check that Reflect handles a task file these calls wrote (values are quoted, such as status: \"done\").",
    asked: "2026-10-25T14:43:23Z",
    session: "local_31dd8fcd-6180-489e-80e9-e63391b9ac05",
    options: [
      .init(id: "merge", text: "Merge #302; I install the new board binary and start PR 4"),
      .init(id: "hold", text: "Hold it; I want to look first"),
    ],
    recommendation: "merge",
    blocks:
      "Tasks v2 PR 4 (the sweep skill) and PR 5 (removing tasks.next and tasks.due), which build on the write calls.",
    why:
      "Three clean-context Opus reviews ran, and the last approved. Fixed along the way: weekdays skipping Monday, writes to a mount that is not a notes repo, a crash on a task that fails its schema, a retry applying done twice, done moving a task earlier, and a work task silently routed to personal when the origin was unreadable. All 7 CI checks pass on 7b40c6fc. Net +483 production lines against a planned 250, mostly retry handling shared with notes and the input descriptions. Board's AGENTS.md leaves merges to the owner.",
    mount: "/repos/board",
    boardName: "crumbkit/board")

  static let review = Question(
    path: "/projects/board/questions/20261024T1830Z-1213",
    question:
      "Review control decision 3: how are review runs recorded?",
    asked: "2026-10-24T18:30:00Z",
    session: "local_745521c7-4d23-41fb-87e9-492902b65f9f",
    options: [
      .init(id: "a", text: "The report alone holds the token use."),
      .init(
        id: "b",
        text:
          "review.run also writes a runs/run/v1 in the author's board, one suite per repository and kind, with tokens and cost as measures."
      ),
    ],
    recommendation: "b",
    why:
      "B costs one put, keeps a local record of every run including unposted re-rolls, and lets runs.trend show review spend.",
    note:
      "The design is at /Users/ana/.local/share/orchestrator/2026-10-24/review-control-design.md, Part 3.",
    boardName: "owner/board")

  static let listings = Question(
    path: "/projects/crumbkit-go/questions/20261024T1830Z-d653",
    question:
      "Review and merge crumbkit-go PR 6, the Listings PR? It has been open since 2026-10-19.",
    asked: "2026-10-24T18:30:00Z",
    session: "local_b1a26257-f649-49c0-b715-c18d03761dc4",
    options: [.init(id: "a", text: "Merge it."), .init(id: "b", text: "Hold it.")],
    boardName: "owner/board")

  static var all: [Question] { [merge, mergeWrites, review, listings] }

  /// Board's refusal of an answer to a question answered elsewhere first.
  static let alreadyAnswered = QuestionRefused(
    question: merge.id, code: "plans::answer::already_answered",
    message: "\(merge.path) already has an answer, so nothing was recorded")
}

/// Launch options that open the app on these requests instead of iCloud's,
/// for screenshots in the Simulator. `-fixtures` turns them on; `-open task`
/// opens a request or question by its name here (`merge`, `decision` or
/// `listings` for a question), `-choose b` chooses an
/// option on the open question (or `other`), `-note text` types a note,
/// `-sent` marks the first question as sending with the banner, `-refused`
/// shows the Already Answered alert, `-empty` shows nothing waiting,
/// `-boards` opens on the Boards list,
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

  /// The question `-open` names.
  static var openQuestion: Question? {
    switch on ? value("-open") : nil {
    case "merge": PreviewQuestions.merge
    case "decision": PreviewQuestions.review
    case "listings": PreviewQuestions.listings
    default: nil
    }
  }

  static var chosen: String? { on ? value("-choose") : nil }
  static var note: String? { on ? value("-note") : nil }
  static var empty: Bool { on && CommandLine.arguments.contains("-empty") }

  static var questions: [Question] { empty ? [] : PreviewQuestions.all }

  static var answering: Set<String> {
    on && CommandLine.arguments.contains("-sent") ? [PreviewQuestions.merge.id] : []
  }

  static var refusals: [QuestionRefused] {
    on && CommandLine.arguments.contains("-refused") ? [PreviewQuestions.alreadyAnswered] : []
  }

  /// The inbox's requests, with the opened one in place of any that shares
  /// its id, as the stale task shares the task's.
  static var requests: [Request] {
    if empty { return [] }
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
