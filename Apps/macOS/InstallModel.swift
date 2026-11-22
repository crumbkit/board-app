// Whether to offer the Board release the app carries, and the install run
// the sheet shows. The release sits in Contents/Resources/board; the
// installed one is the one ~/.local/share/board/current names.
import AppKit
import Installer
import Launcher

@MainActor
@Observable
final class InstallModel {
  /// Where the sheet is.
  enum Phase: Equatable {
    case offered
    case running
    case installed
    case stopped(Stop)
  }

  /// The release the app carries, or nil when this build carries none.
  let carried: Release?
  /// The carried release's folder.
  let folder: URL?
  private(set) var offer: Installer.Offer?
  private(set) var survey: Survey
  /// The installed release, when there is one and its release.json reads.
  private(set) var installed: Release?
  private(set) var phase = Phase.offered
  /// Whether the run replaces an installed release, as the offer said
  /// when it started.
  private(set) var updating = false
  private(set) var progress = InstallProgress()
  /// Set when the login shell's PATH could not be read.
  private(set) var pathProblem: String?
  /// Where a new personal board goes, when the config names none.
  private(set) var boardFolder: URL
  /// Whether the installer may make a board in `boardFolder`.
  private(set) var folderCheck: BoardFolder.Check
  /// The global git identity, or nil until it has been read.
  private(set) var identity: GitIdentity?
  /// The name and email typed in the sheet, for the values git lacks.
  var gitName = ""
  var gitEmail = ""
  /// Whether the sheet is up. Not Now takes it down until the next launch,
  /// or until the menu's item puts it back.
  var sheetShown = false
  private var run: Task<Void, Never>?
  private let machine = Machine(home: FileManager.default.homeDirectoryForCurrentUser)

  init() {
    let folder = Bundle.main.resourceURL?.appendingPathComponent("board")
    // Nil is right: a build without a release offers nothing.
    let carried = folder.flatMap {
      try? Data(contentsOf: $0.appendingPathComponent("release.json"))
    }
    .flatMap { try? Release(json: $0) }
    self.carried = carried
    self.folder = carried == nil ? nil : folder
    survey = machine.survey()
    let boardFolder = BoardFolder.default(home: machine.home)
    self.boardFolder = boardFolder
    folderCheck = BoardFolder.check(boardFolder)
    check()
    sheetShown = offer != nil
  }

  var running: Bool { phase == .running }

  /// Whether the install makes a personal board, because the config names none.
  var makesPersonalBoard: Bool { survey.personal == nil }

  /// Whether the sheet asks for a name and email, because git lacks one.
  var asksIdentity: Bool { makesPersonalBoard && identity.map { !$0.complete } ?? false }

  /// Whether the typed email is one the installer would refuse.
  var emailRefused: Bool {
    identity?.email == nil && !gitEmail.isEmpty && !GitIdentity.isEmail(gitEmail)
  }

  /// Whether Install may start: the folder passes and git has, or is given,
  /// a name and an email.
  var canInstall: Bool {
    guard makesPersonalBoard else { return true }
    guard folderCheck.passes, let identity, identity.problem == nil else { return false }
    let name = identity.name ?? gitName.trimmingCharacters(in: .whitespaces)
    let email = identity.email ?? gitEmail
    return !name.isEmpty && GitIdentity.isEmail(email)
  }

  /// Choose…: the folder the person picked.
  func choose(_ folder: URL) {
    boardFolder = folder
    folderCheck = BoardFolder.check(folder)
  }

  /// Reads the installed release again, and what the offer would change.
  func check() {
    guard let carried else { return }
    let installed = machine.installed()
    offer = Installer.Offer(carrying: carried, installed: installed)
    if case .release(_, let release) = installed {
      self.installed = release
    } else {
      self.installed = nil
    }
    if !running {
      survey = machine.survey()
      folderCheck = BoardFolder.check(boardFolder)
      if makesPersonalBoard { readIdentity() }
    }
  }

  /// Reads git's identity off the main actor, and fills the fields with
  /// any value it has.
  private func readIdentity() {
    Task {
      let identity = await GitIdentity.read()
      self.identity = identity
      if let name = identity.name { gitName = name }
      if let email = identity.email { gitEmail = email }
    }
  }

  /// The menu's item: shows the offer again.
  func show() {
    check()
    if phase != .running { phase = .offered }
    sheetShown = offer != nil || phase != .offered
  }

  func notNow() { sheetShown = false }

  /// Done or Close: takes the sheet down and reads what is installed now.
  func close() {
    sheetShown = false
    phase = .offered
    check()
  }

  /// Stops a running install and waits for it, before the app quits.
  func stop() async {
    run?.cancel()
    await run?.value
  }

  /// Starts the install, or does nothing while one runs.
  func install() {
    guard run == nil, let folder else { return }
    run = Task {
      await install(folder.appendingPathComponent("install"))
      run = nil
    }
  }

  private func install(_ installer: URL) async {
    updating = offer != .install
    phase = .running
    progress = InstallProgress()
    let home = machine.home
    let environment = ProcessInfo.processInfo.environment
    let login = await loginPath(shell: environment["SHELL"] ?? "/bin/zsh", home: home)
    // Quitting while the shell ran cancels this task; start nothing then.
    guard !Task.isCancelled else { return }
    pathProblem =
      login == nil
      ? "Board could not read your shell's PATH, so it ran the installer with ~/.local/bin added to the app's PATH."
      : nil
    let path = installPath(login: login, app: environment["PATH"] ?? "/usr/bin:/bin", home: home)
    let (lines, sink) = AsyncStream.makeStream(of: RunLine.self)
    async let result = Self.run(
      ["/usr/bin/env", "PATH=\(path)", installer.path] + arguments, sink: sink)
    for await line in lines { progress.read(line) }
    switch InstallOutcome(progress, exit: await result.outcome) {
    case .installed: phase = .installed
    case .stopped(let stop): phase = .stopped(stop)
    }
    check()
  }

  /// The installer's arguments: the board folder when the config names no
  /// personal board, and only the git values git lacks. Never `--hooks`.
  private var arguments: [String] {
    guard makesPersonalBoard else { return [] }
    var arguments = ["--board-folder", boardFolder.path]
    if identity?.name == nil {
      arguments += ["--git-name", gitName.trimmingCharacters(in: .whitespaces)]
    }
    if identity?.email == nil { arguments += ["--git-email", gitEmail] }
    return arguments
  }

  /// Runs the installer off the main actor, passing each line to `sink`.
  @concurrent
  private static func run(_ argv: [String], sink: AsyncStream<RunLine>.Continuation) async
    -> RunResult
  {
    let result = await Runner(timeout: installTimeout, cap: 16_000_000).run(
      argv, lines: { sink.yield($0) })
    sink.finish()
    return result
  }
}
