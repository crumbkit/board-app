// The launcher's screen model: where the owner is, what each level lists,
// which row is selected, and what a key does. The app draws `screen` and
// carries out the `Effect` a key returns.
import Foundation

/// A command's result as the launcher shows it: still running, done, or
/// failed with a reason.
public enum Loaded<Value: Sendable & Hashable>: Sendable, Hashable {
  case loading
  case loaded(Value)
  case failed(Failure)
}

/// A provider command that failed, timed out or printed invalid output.
public struct Failure: Sendable, Hashable {
  public let reason: String
  public let argv: [String]
  /// The start of what the command printed.
  public let output: String
}

/// A `run` action that failed after the panel closed. The top level shows it
/// until the next action runs.
public struct ActionFailure: Sendable, Hashable {
  public let label: String
  public let failure: Failure

  public init(label: String, failure: Failure) {
    self.label = label
    self.failure = failure
  }
}

extension Failure {
  /// Why a command failed, or nil when it exited 0.
  public init?(_ result: RunResult) {
    guard let problem = result.problem else { return nil }
    self.init(reason: problem, argv: result.argv, output: result.outputStart())
  }
}

extension Loaded where Value == Listing {
  /// A listing command's result: its decoded output, or why it has none.
  public static func listing(_ result: RunResult) -> Loaded<Listing> {
    if let failure = Failure(result) { return .failed(failure) }
    do {
      return .loaded(try Listing.decode(result.stdout))
    } catch {
      return .failed(
        Failure(reason: "\(error)", argv: result.argv, output: result.outputStart()))
    }
  }
}

extension Loaded where Value == String {
  /// A confirm preview's result: its output exactly as printed.
  public static func preview(_ result: RunResult) -> Loaded<String> {
    if let failure = Failure(result) { return .failed(failure) }
    return .loaded(String(decoding: result.stdout, as: UTF8.self))
  }
}

/// An item and the provider that listed it.
public struct Located: Sendable, Hashable {
  public let provider: String
  public let item: Item

  /// Unique across providers.
  public var key: String { provider + "\u{1F}" + item.id }
}

/// A level below the top.
public enum Level: Sendable, Hashable {
  /// An item's parts.
  case item(Located)
  /// The preview of a `run` action, before it runs.
  case confirm(Located, Action)
  /// A failed command's details.
  case failure(Failure, provider: String)
}

public enum RowKind: Sendable, Hashable {
  /// A listed item, at the top level or among an item's parts.
  case item(Located)
  /// One of an item's actions.
  case action(Located, Action)
  /// The action a confirm step runs.
  case confirm(Located, Action)
  case cancel
  case failure(Failure, provider: String)
  /// A line that does nothing: loading, skipped items, nothing found.
  case note(String)
}

public struct Row: Sendable, Hashable, Identifiable {
  public let id: String
  public let title: String
  public let subtitle: String?
  public let status: Status?
  public let kind: RowKind
}

public struct ScreenSection: Sendable, Hashable, Identifiable {
  public let id: String
  public let title: String
  public let rows: [Row]
}

/// A key and what it does, for the footer.
public struct Hint: Sendable, Hashable {
  public let key: String
  public let label: String
}

/// What one state of the launcher shows.
public struct Screen: Sendable {
  /// The item named left of the field below the top level.
  public let chip: String?
  public let placeholder: String
  /// A problem above the list, such as a refused config.
  public let notice: String?
  public let sections: [ScreenSection]
  let defaultSelection: Int
  /// A confirm step's preview command, its output, and the command the
  /// action runs.
  public let preview: (argv: [String], output: Loaded<String>, runs: [String])?

  public var rows: [Row] { sections.flatMap(\.rows) }
}

/// What the app does after a key.
public enum Effect: Sendable, Hashable {
  case none
  /// Closes the panel.
  case close
  case open(URL)
  /// Opens a file in its default app.
  case openFile(String)
  case copy(String)
  /// Runs an action's command from argv, with no shell.
  case run(Located, Action)
  /// Lists an item's parts with its `children` command.
  case loadParts(Located)
  /// Runs a confirm step's preview.
  case runPreview(Located, Action)
  /// Opens the evidence preview window.
  case preview(EvidenceBrowser)

  /// Whether the panel closes after the app carries this out.
  public var closesPanel: Bool {
    switch self {
    case .close, .open, .openFile, .copy, .run: true
    default: false
    }
  }
}

public struct ProviderState: Sendable, Hashable {
  public let provider: Provider
  public var listing: Loaded<Listing>

  public init(provider: Provider, listing: Loaded<Listing> = .loading) {
    self.provider = provider
    self.listing = listing
  }
}

public struct Launcher: Sendable {
  /// Why the config was not loaded, when it was not.
  public var problem: String?
  public var providers: [ProviderState] = []
  /// Each item's parts, by `Located.key`.
  public var parts: [String: Loaded<Listing>] = [:]
  /// Each confirm step's preview, by `Located.key` and action id.
  public var previews: [String: Loaded<String>] = [:]
  /// The last `run` action that failed, shown at the top level.
  public var actionFailure: ActionFailure?
  public private(set) var path: [Level] = []
  public var query = "" {
    didSet { if query != oldValue { selectedID = nil } }
  }
  /// The selected row's id; nil selects the screen's default row. A row
  /// keeps its selection across a refresh while it is still listed.
  public var selectedID: String?

  public init() {}

  /// Back to the top level with an empty field, as each open starts.
  public mutating func reset() {
    path = []
    query = ""
    selectedID = nil
  }

  public static func previewKey(_ located: Located, _ action: Action) -> String {
    located.key + "\u{1F}" + action.id
  }

  // MARK: Screens

  public var screen: Screen {
    switch path.last {
    case nil: topScreen
    case .item(let located): itemScreen(located)
    case .confirm(let located, let action): confirmScreen(located, action)
    case .failure(let failure, let provider): failureScreen(failure, provider: provider)
    }
  }

  private var words: [String] {
    query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
  }

  private func matches(_ fields: [String?]) -> Bool {
    let haystack = fields.compactMap { $0 }.joined(separator: "\n").lowercased()
    return words.allSatisfy { haystack.contains($0) }
  }

  private func row(_ located: Located) -> Row {
    let item = located.item
    return Row(
      id: "item:" + located.key, title: item.title, subtitle: item.subtitle, status: item.status,
      kind: .item(located))
  }

  private static func failureRow(_ failure: Failure, provider: String) -> Row {
    Row(
      id: "failure:" + provider, title: provider, subtitle: failure.reason,
      status: Status(tone: .failed, word: "Failed"), kind: .failure(failure, provider: provider))
  }

  private static func note(_ id: String, _ text: String) -> Row {
    Row(id: "note:" + id, title: text, subtitle: nil, status: nil, kind: .note(text))
  }

  /// A listing's sections, filtered by the query. A failed listing is one
  /// failure row, which the query never hides.
  private func sections(
    _ listing: Loaded<Listing>, provider: String, id: String, loadingTitle: String
  ) -> [ScreenSection] {
    switch listing {
    case .loading:
      return [
        ScreenSection(
          id: id, title: loadingTitle, rows: [Self.note(id, "Loading \(provider)…")])
      ]
    case .failed(let failure):
      return [
        ScreenSection(
          id: id, title: loadingTitle, rows: [Self.failureRow(failure, provider: provider)])
      ]
    case .loaded(let listing):
      var result: [ScreenSection] = listing.sections.enumerated().compactMap { index, section in
        let rows = section.items
          .filter { matches([$0.title, $0.subtitle] + $0.keywords) }
          .map { row(Located(provider: provider, item: $0)) }
        return rows.isEmpty
          ? nil : ScreenSection(id: "\(id)/\(index)", title: section.title, rows: rows)
      }
      if words.isEmpty, !listing.skipped.isEmpty {
        let text = listing.skipped.map {
          "\($0.count) \($0.type) item\($0.count == 1 ? "" : "s") skipped: Board.app has no view for \($0.type)"
        }.joined(separator: "; ")
        result.append(
          ScreenSection(
            id: "\(id)/skipped", title: provider, rows: [Self.note("\(id)/skipped", text)]))
      }
      return result
    }
  }

  private var topScreen: Screen {
    var sections: [ScreenSection] = []
    if let failed = actionFailure {
      sections.append(
        ScreenSection(
          id: "action-failure", title: "Last action",
          rows: [Self.failureRow(failed.failure, provider: failed.label)]))
    }
    sections += providers.flatMap {
      self.sections(
        $0.listing, provider: $0.provider.name, id: "provider:" + $0.provider.name,
        loadingTitle: $0.provider.name)
    }
    if sections.isEmpty, problem == nil {
      sections = [
        ScreenSection(
          id: "empty", title: "",
          rows: [Self.note("empty", words.isEmpty ? "Nothing is listed." : "Nothing matches.")])
      ]
    }
    return Screen(
      chip: nil, placeholder: "Search", notice: problem, sections: sections, defaultSelection: 0,
      preview: nil)
  }

  private func itemScreen(_ located: Located) -> Screen {
    var sections: [ScreenSection] = []
    let actions = located.item.actions
      .filter { matches([$0.label]) }
      .map {
        Row(
          id: "action:" + $0.id, title: $0.label, subtitle: nil, status: nil,
          kind: .action(located, $0))
      }
    if !actions.isEmpty {
      sections.append(ScreenSection(id: "actions", title: "Actions", rows: actions))
    }
    if located.item.children != nil {
      sections += self.sections(
        parts[located.key] ?? .loading, provider: located.provider, id: "parts",
        loadingTitle: "Parts")
    }
    if sections.isEmpty {
      sections = [
        ScreenSection(
          id: "empty", title: "",
          rows: [Self.note("empty", words.isEmpty ? "This item has no parts." : "Nothing matches.")]
        )
      ]
    }
    return Screen(
      chip: located.item.title, placeholder: "Search this \(located.item.type)", notice: nil,
      sections: sections, defaultSelection: 0, preview: nil)
  }

  private func confirmScreen(_ located: Located, _ action: Action) -> Screen {
    guard case .run(let run) = action.perform, let confirm = run.confirm else {
      return itemScreen(located)
    }
    let output = previews[Self.previewKey(located, action)] ?? .loading
    var rows = [
      Row(id: "cancel", title: "Cancel", subtitle: nil, status: nil, kind: .cancel)
    ]
    if case .loaded = output {
      rows.insert(
        Row(
          id: "confirm", title: action.label, subtitle: nil, status: nil,
          kind: .confirm(located, action)), at: 0)
    }
    return Screen(
      chip: located.item.title, placeholder: action.label, notice: nil,
      sections: [ScreenSection(id: "confirm", title: action.label, rows: rows)],
      defaultSelection: rows.count - 1, preview: (confirm.preview, output, run.argv))
  }

  private func failureScreen(_ failure: Failure, provider: String) -> Screen {
    Screen(
      chip: provider, placeholder: "", notice: nil,
      sections: [
        ScreenSection(
          id: "failure", title: provider, rows: [Self.failureRow(failure, provider: provider)])
      ], defaultSelection: 0, preview: nil)
  }

  // MARK: Selection

  public func selected(in screen: Screen) -> Row? {
    let rows = screen.rows
    if let row = rows.first(where: { $0.id == selectedID }) { return row }
    return rows.indices.contains(screen.defaultSelection)
      ? rows[screen.defaultSelection] : rows.first
  }

  public var selected: Row? { selected(in: screen) }

  public mutating func move(_ delta: Int) {
    let screen = screen
    let rows = screen.rows
    guard !rows.isEmpty else { return }
    let current = selected(in: screen).flatMap { row in rows.firstIndex(of: row) } ?? 0
    selectedID = rows[min(max(current + delta, 0), rows.count - 1)].id
  }

  /// The provider the footer names: the selected row's, or the level's.
  public var provider: String? {
    switch selected?.kind {
    case .item(let located), .action(let located, _), .confirm(let located, _):
      return located.provider
    case .failure(_, let provider): return provider
    default: break
    }
    switch path.last {
    case .item(let located), .confirm(let located, _): return located.provider
    case .failure(_, let provider): return provider
    case nil: return providers.count == 1 ? providers[0].provider.name : nil
    }
  }

  // MARK: Keys

  /// Whether ↩ opens an item: at the top level, when it has parts or more
  /// than two actions, so every action is in reach.
  private func descends(_ item: Item) -> Bool {
    path.isEmpty && (item.children != nil || item.actions.count > 2)
  }

  /// The action ⌘↩ runs on an item: its first action when ↩ opens the item,
  /// its second when ↩ runs the first.
  private func secondAction(_ item: Item) -> Action? {
    let index = descends(item) ? 0 : 1
    return item.actions.indices.contains(index) ? item.actions[index] : nil
  }

  /// Enter, or ⌘↩ when `alternate` is set.
  public mutating func activate(alternate: Bool = false) -> Effect {
    guard let row = selected else { return .none }
    switch row.kind {
    case .item(let located):
      let item = located.item
      if alternate {
        return secondAction(item).map { perform(located, $0) } ?? .none
      }
      if descends(item) {
        push(.item(located))
        return item.children != nil && parts[located.key] == nil ? .loadParts(located) : .none
      }
      if let file = item.evidenceFile { return .openFile(file.evidence.path) }
      return item.actions.first.map { perform(located, $0) } ?? .none
    case .action(let located, let action):
      return alternate ? .none : perform(located, action)
    case .confirm(let located, let action):
      return .run(located, action)
    case .cancel:
      back()
      return .none
    case .failure(let failure, let provider):
      if path.last != .failure(failure, provider: provider) {
        push(.failure(failure, provider: provider))
      }
      return .none
    case .note:
      return .none
    }
  }

  private mutating func perform(_ located: Located, _ action: Action) -> Effect {
    switch action.perform {
    case .open(let link): return .open(link.href)
    case .copy(let text): return .copy(text)
    case .run(let run):
      guard run.confirm != nil else { return .run(located, action) }
      previews[Self.previewKey(located, action)] = nil
      push(.confirm(located, action))
      return .runPreview(located, action)
    }
  }

  /// Space: the evidence preview when an evidence row is selected. Nil when
  /// the field should take the key and type a space.
  public func space() -> Effect? {
    guard case .item(let located) = selected?.kind, located.item.evidenceFile != nil else {
      return nil
    }
    let files = screen.rows.compactMap { row -> EvidenceFile? in
      guard case .item(let other) = row.kind else { return nil }
      return other.item.evidenceFile
    }
    let index = files.firstIndex { $0.id == located.item.id } ?? 0
    return .preview(EvidenceBrowser(files: files, index: index))
  }

  /// Esc: back a level, or close at the top.
  public mutating func escape() -> Effect {
    if path.isEmpty { return .close }
    back()
    return .none
  }

  /// Backspace: back a level when the field is empty. False when the field
  /// should take the key.
  public mutating func backspace() -> Bool {
    guard query.isEmpty, !path.isEmpty else { return false }
    back()
    return true
  }

  private mutating func push(_ level: Level) {
    path.append(level)
    query = ""
    selectedID = nil
  }

  /// Back a level, selecting the row that led to it.
  public mutating func back() {
    guard let level = path.popLast() else { return }
    query = ""
    switch level {
    case .item(let located): selectedID = "item:" + located.key
    case .confirm(_, let action): selectedID = "action:" + action.id
    case .failure(_, let provider): selectedID = "failure:" + provider
    }
  }

  // MARK: Footer

  /// The keys the footer shows for the selected row.
  public var hints: [Hint] {
    var hints: [Hint] = []
    switch selected?.kind {
    case .item(let located):
      let item = located.item
      if descends(item) {
        hints.append(Hint(key: "↩", label: "Open"))
      } else if item.evidenceFile != nil {
        hints.append(Hint(key: "space", label: "Preview"))
        hints.append(Hint(key: "↩", label: "Open file"))
      } else if let first = item.actions.first {
        hints.append(Hint(key: "↩", label: first.label))
      }
      if let second = secondAction(item) {
        hints.append(Hint(key: "⌘↩", label: second.label))
      }
    case .action(_, let action): hints.append(Hint(key: "↩", label: action.label))
    case .confirm, .cancel: hints.append(Hint(key: "↩", label: "Choose"))
    case .failure(let failure, let provider):
      if path.last != .failure(failure, provider: provider) {
        hints.append(Hint(key: "↩", label: "Details"))
      }
    case .note, nil: break
    }
    hints.append(Hint(key: "esc", label: path.isEmpty ? "Close" : "Back"))
    return hints
  }
}
