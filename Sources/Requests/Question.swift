// A question an agent asked the owner, as `board call plans.open` lists it,
// and the answer the phone sends back. An answer is not signed: it tells the
// agent what to do next, and anything the agent then asks Board to do still
// needs a signed approval.
import Foundation
import SSHSig

/// One open `plans/question/v1` record, with the fields `plans.open` prints.
public struct Question: Identifiable, Equatable, Sendable {
  public struct Option: Equatable, Sendable {
    public let id: String
    public let text: String

    public init(id: String, text: String) {
      self.id = id
      self.text = text
    }
  }

  /// The question's logical path, such as
  /// `/projects/board/questions/20261024T1830Z-1213`.
  public let path: String
  public let question: String
  /// When it was asked, as Board prints it.
  public let asked: String?
  /// The session that asked it.
  public let session: String?
  public let options: [Option]
  /// The id of the option the agent recommends.
  public let recommendation: String?
  /// What waits on the answer.
  public let blocks: String?
  /// Why the agent recommends its option.
  public let why: String?
  /// What the agent could not check.
  public let note: String?
  /// The mount the question concerns, such as `/repos/board`.
  public let mount: String?
  public let contextPath: String?
  /// The board it concerns, as the phone names it: the mount's git remote,
  /// or the personal board's. The Mac sets it.
  public var boardName = ""

  public init(
    path: String, question: String, asked: String? = nil, session: String? = nil,
    options: [Option] = [], recommendation: String? = nil, blocks: String? = nil,
    why: String? = nil, note: String? = nil, mount: String? = nil, contextPath: String? = nil,
    boardName: String = ""
  ) {
    self.path = path
    self.question = question
    self.asked = asked
    self.session = session
    self.options = options
    self.recommendation = recommendation
    self.blocks = blocks
    self.why = why
    self.note = note
    self.mount = mount
    self.contextPath = contextPath
    self.boardName = boardName
  }

  /// The zone record's name: the git blob id of the path, so any path makes a
  /// valid name and the same path the same name.
  public var id: String { Self.recordName(path) }

  public static func recordName(_ path: String) -> String { gitBlobID(Data(path.utf8)) }

  public var askedDate: Date? { asked.flatMap(rfc3339) }

  /// `report` is not what `board call plans.open --json` prints.
  public struct Malformed: Error, Equatable {}

  /// The questions in `report`, what `board call plans.open --json` prints. A
  /// question with no path or text is left out, and so is an option with no
  /// id or text. A field Board does not print reads as absent.
  public static func open(report: Data) throws -> [Question] {
    let parsed = try JSONValue.parse(report)
    guard parsed["schema"]?.string == "board/call-report/v2",
      case .array(let items)? = parsed["data"]?["output"]?["questions"]
    else { throw Malformed() }
    return items.compactMap { Question(item: $0) }
  }

  private init?(item: JSONValue) {
    guard let path = item["path"]?.string, let question = item["question"]?.string else {
      return nil
    }
    var options: [Option] = []
    if case .array(let values)? = item["options"] {
      options = values.compactMap { value in
        guard let id = value["id"]?.string, let text = value["text"]?.string else { return nil }
        return Option(id: id, text: text)
      }
    }
    self.init(
      path: path, question: question, asked: item["asked"]?.string,
      session: item["session"]?.string, options: options,
      recommendation: item["recommendation"]?.string, blocks: item["blocks"]?.string,
      why: item["why"]?.string, note: item["note"]?.string, mount: item["mount"]?.string,
      contextPath: item["context_path"]?.string)
  }

  /// The option the agent recommends, or nil when it names none of them.
  public var recommended: Option? { options.first { $0.id == recommendation } }

  /// The inbox row's second line.
  public var recommendationLine: String {
    recommended.map { "Recommended: " + $0.text } ?? "No recommendation"
  }

  /// The second line, or that the answer is on its way while it is.
  public func rowLine(sending: Bool) -> String {
    sending ? "Sending your answer…" : recommendationLine
  }

  /// Whether Answer is on: an option is chosen, or Something Else is chosen
  /// and the note has words.
  public func canAnswer(_ choice: QuestionChoice?, note: String) -> Bool {
    switch choice {
    case nil: false
    case .option(let id): options.contains { $0.id == id }
    case .other: !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  // MARK: The zone record

  /// The zone record's fields. The options travel as JSON, each with its id
  /// and text.
  public var fields: [String: String] {
    var fields = ["path": path, "question": question, "board": boardName]
    let options = JSONValue.array(
      options.map { .object([("id", .string($0.id)), ("text", .string($0.text))]) })
    fields["options"] = options.pretty
    for (key, value) in [
      ("asked", asked), ("session", session), ("recommendation", recommendation),
      ("blocks", blocks), ("why", why), ("note", note), ("mount", mount),
      ("contextPath", contextPath),
    ] {
      fields[key] = value
    }
    return fields
  }

  /// The question in a zone record, or nil when the fields do not make one or
  /// the record's name is not its path's.
  public init?(name: String, fields: [String: String]) {
    guard let path = fields["path"], let question = fields["question"],
      name == Self.recordName(path),
      case .array(let values)? = fields["options"].flatMap({ try? JSONValue.parse(Data($0.utf8)) })
    else { return nil }
    let options = values.compactMap { value -> Option? in
      guard let id = value["id"]?.string, let text = value["text"]?.string else { return nil }
      return Option(id: id, text: text)
    }
    self.init(
      path: path, question: question, asked: fields["asked"], session: fields["session"],
      options: options, recommendation: fields["recommendation"], blocks: fields["blocks"],
      why: fields["why"], note: fields["note"], mount: fields["mount"],
      contextPath: fields["contextPath"], boardName: fields["board"] ?? "")
  }
}

/// What the owner chose on the question screen.
public enum QuestionChoice: Hashable, Sendable {
  /// One of the question's options, by id.
  case option(String)
  /// Something else, in the owner's note: Board's option `none`.
  case other
}

/// The owner's answer, on its way through iCloud to the Mac, which records it
/// with `plans.answer`.
public struct QuestionAnswer: Equatable, Sendable {
  public let path: String
  /// The chosen option's id, or `none`.
  public let option: String
  /// The owner's note, trimmed; empty when there is none.
  public let note: String

  /// The answer, or nil when the choice and note would not turn Answer on.
  public init?(question: Question, choice: QuestionChoice?, note: String) {
    guard question.canAnswer(choice, note: note), let choice else { return nil }
    path = question.path
    switch choice {
    case .option(let id): option = id
    case .other: option = "none"
    }
    self.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// The answer in a zone record, or nil when the fields do not make one or
  /// the record's name is not the one its path gives.
  public init?(name: String, fields: [String: String]) {
    guard let path = fields["path"], let option = fields["option"], !option.isEmpty,
      name == "qanswer-" + Question.recordName(path)
    else { return nil }
    self.path = path
    self.option = option
    note = fields["note"] ?? ""
  }

  /// The name of the question's record.
  public var question: String { Question.recordName(path) }

  /// The zone record's name.
  public var name: String { "qanswer-" + question }

  public var fields: [String: String] { ["path": path, "option": option, "note": note] }

  /// The arguments the Mac passes to `board`. The note is the answer's words
  /// when it has any; without one, Board uses the option's text.
  public var arguments: [String] {
    ["--personal", "call", "plans.answer", "--path", path, "--option", option]
      + ["--written_by", "board-app/phone"] + (note.isEmpty ? [] : ["--words", note]) + ["--json"]
  }
}

/// A refusal as `board --json` prints it: a `board/failure/v1` record.
public struct BoardFailure: Equatable, Sendable {
  public let code: String
  public let message: String

  public struct Malformed: Error, Equatable {}

  /// Whether `plans.answer` itself refused the answer, so trying again gives
  /// the same refusal. Any other failure, such as a board that was busy, is
  /// worth trying again.
  public var isFinal: Bool { code.hasPrefix("plans::answer::") }

  public init(json: Data) throws {
    let parsed = try JSONValue.parse(json)
    guard parsed["schema"]?.string == "board/failure/v1", let code = parsed["code"]?.string,
      let message = parsed["message"]?.string
    else { throw Malformed() }
    self.code = code
    self.message = message
  }
}

/// Board's refusal of an answer, which the Mac sends back for the phone to
/// show once.
public struct QuestionRefused: Equatable, Sendable {
  /// The name of the question's record.
  public let question: String
  public let code: String
  public let message: String

  public init(question: String, code: String, message: String) {
    self.question = question
    self.code = code
    self.message = message
  }

  public init(answer: QuestionAnswer, failure: BoardFailure) {
    self.init(question: answer.question, code: failure.code, message: failure.message)
  }

  public init?(name: String, fields: [String: String]) {
    guard let question = fields["question"], let code = fields["code"],
      name == "qrefused-" + question
    else { return nil }
    self.init(question: question, code: code, message: fields["message"] ?? "")
  }

  public var name: String { "qrefused-" + question }

  public var fields: [String: String] {
    ["question": question, "code": code, "message": message]
  }

  private var alreadyAnswered: Bool { code == "plans::answer::already_answered" }

  /// The alert's title.
  public var title: String {
    alreadyAnswered ? "Already Answered" : "Board Did Not Record Your Answer"
  }

  /// The alert's message.
  public var text: String {
    alreadyAnswered
      ? "This question was answered from another place before your answer reached Board, so Board kept the first answer. Yours was not recorded."
      : message
  }
}

/// A mounted board, as the Mac names the board a question concerns.
public enum Mount {
  /// The mount's record in the personal board, such as `repos/board.json` for
  /// `/repos/board`, or nil for a path that is not absolute or climbs out.
  public static func file(_ mount: String) -> String? {
    guard mount.hasPrefix("/") else { return nil }
    let segments = mount.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
    guard !segments.isEmpty, !segments.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    else { return nil }
    return segments.joined(separator: "/") + ".json"
  }

  /// The repository a `board/mount/v1` record names, or nil when it names
  /// none, as a mount of another board does.
  public static func repository(_ record: Data) -> String? {
    guard let parsed = try? JSONValue.parse(record),
      parsed["$type"]?.string == "board/mount/v1"
    else { return nil }
    return parsed["repo"]?.string
  }

  /// The mount's last segment, for when its repository's remote cannot be read.
  public static func fallbackName(_ mount: String) -> String {
    mount.split(separator: "/").last.map(String.init) ?? mount
  }
}
