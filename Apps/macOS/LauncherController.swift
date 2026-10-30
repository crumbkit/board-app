// The launcher's live state: it loads the config, runs the providers, and
// carries out what each key returns. `Launcher` decides what a key does;
// this class does it.
import AppKit
import Launcher
import os

@MainActor
@Observable
final class LauncherController {
  var state = Launcher()
  /// Changes on each open, so the view focuses the field again.
  private(set) var opened = 0
  /// Closes the panel.
  @ObservationIgnored var close: () -> Void = {}
  /// Opens the evidence preview window.
  @ObservationIgnored var showPreview: (EvidenceBrowser) -> Void = { _ in }

  /// Whether the list beside an item's parts is hidden, remembered
  /// between opens.
  private(set) var sidebarHidden = UserDefaults.standard.launcherSidebarHidden {
    didSet { UserDefaults.standard.launcherSidebarHidden = sidebarHidden }
  }
  @ObservationIgnored private var refreshing: Task<Void, Never>?
  private let runner = Runner()
  /// An action's command may run for ten minutes, since it may start or
  /// stop something.
  private let actionRunner = Runner(timeout: .seconds(600))
  /// Logs a provider's name or an action's label and the outcome, never a
  /// command or its output.
  private let log = Logger(subsystem: "com.stemmacorp.board", category: "launcher")

  /// Whether the list shows at the current level. The top level always
  /// shows it, since the list is all it has.
  var showsList: Bool { state.path.isEmpty || !sidebarHidden }

  /// The sidebar button and ⌃⌘S. They do nothing at the top level.
  func toggleSidebar() {
    guard !state.path.isEmpty else { return }
    sidebarHidden.toggle()
  }

  /// Each open starts at the top level with an empty field, and lists
  /// again. An item's parts are listed again when it is opened.
  func opening() {
    state.reset()
    state.parts = [:]
    state.previews = [:]
    opened += 1
    refreshing?.cancel()
    refreshing = Task { await refresh() }
  }

  /// Loads the config and runs every provider at once. A provider keeps its
  /// last listing until the new one arrives. A cancelled refresh writes
  /// nothing more, so an older run cannot replace a newer one.
  func refresh() async {
    let config: Config
    do {
      config = try Config.load(
        from: Config.file(home: FileManager.default.homeDirectoryForCurrentUser))
      state.problem = nil
    } catch {
      state.problem = error.description
      state.providers = []
      return
    }
    let previous = Dictionary(
      state.providers.map { ($0.provider, $0.listing) }, uniquingKeysWith: { a, _ in a })
    state.providers = config.providers.map {
      ProviderState(provider: $0, listing: previous[$0] ?? .loading)
    }
    let runner = runner
    await withTaskGroup(of: (Provider, Loaded<Listing>).self) { group in
      for provider in config.providers {
        group.addTask { (provider, .listing(await runner.run(provider.list))) }
      }
      for await (provider, listing) in group {
        guard !Task.isCancelled else { return }
        if case .failed = listing {
          log.error("Provider \(provider.name, privacy: .public) failed")
        }
        if let index = state.providers.firstIndex(where: { $0.provider == provider }) {
          state.providers[index].listing = listing
        }
      }
    }
  }

  // MARK: Keys

  func activate(alternate: Bool) { perform(state.activate(alternate: alternate)) }

  func escape() { perform(state.escape()) }

  /// False when the field should take the key.
  func backspace() -> Bool { state.backspace() }

  /// False when the field should take the key and type a space.
  func space() -> Bool {
    guard let effect = state.space() else { return false }
    perform(effect)
    return true
  }

  func move(_ delta: Int) { state.move(delta) }

  func perform(_ effect: Effect) {
    switch effect {
    case .none: return
    case .close: break
    case .open(let url):
      // The contract admits only http and https; this holds the line here too.
      if Address.isWeb(url) { NSWorkspace.shared.open(url) }
    case .openFile(let path): openEvidence(path)
    case .copy(let text):
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    case .run(let located, let action): run(located, action)
    case .loadParts(let located): loadParts(located)
    case .runPreview(let located, let action): runPreview(located, action)
    case .preview(let browser): showPreview(browser)
    }
    if effect.closesPanel { close() }
  }

  private func loadParts(_ located: Located) {
    guard let children = located.item.children else { return }
    state.parts[located.key] = .loading
    let runner = runner
    Task { state.parts[located.key] = .listing(await runner.run(children)) }
  }

  private func runPreview(_ located: Located, _ action: Action) {
    guard case .run(let run) = action.perform, let confirm = run.confirm else { return }
    let key = Launcher.previewKey(located, action)
    let runner = runner
    Task {
      state.previews[key] = .preview(await runner.run(confirm.preview))
    }
  }

  /// Runs an action's command after the panel closes. A failure shows as a
  /// row at the top of the next open.
  private func run(_ located: Located, _ action: Action) {
    guard case .run(let run) = action.perform else { return }
    state.actionFailure = nil
    let runner = actionRunner
    let log = log
    Task {
      let result = await runner.run(run.argv)
      if let failure = Failure(result) {
        log.error(
          "Action \(action.label, privacy: .public) of \(located.provider, privacy: .public) failed"
        )
        state.actionFailure = ActionFailure(label: action.label, failure: failure)
      } else {
        log.info(
          "Action \(action.label, privacy: .public) of \(located.provider, privacy: .public) finished"
        )
      }
    }
  }
}
