import Foundation
import Launcher
import Testing

@testable import Installer

private let board = "e3d2cb16a7c3cc566f611eaf2219e04ae6a9218a"
private let app = "acbf7236b1c4aa1fd0d9c2b3e4f5a6b7c8d9e0f1"

/// A scratch home that each test owns and removes.
private struct Home: ~Copyable {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

  init() throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  deinit {
    // Nil is right: a scratch folder left behind is harmless.
    try? FileManager.default.removeItem(at: url)
  }

  func write(_ path: String, _ text: String) throws {
    let file = url.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: file)
  }

  func link(_ path: String, to target: String) throws {
    let file = url.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: target)
  }

  func release(_ id: String) -> String {
    #"{"id": "\#(id)", "board": "\#(board)", "board-app": "\#(app)"}"#
  }
}

@Test func a_home_with_no_current_link_has_nothing_installed() throws {
  let home = try Home()
  #expect(Machine(home: home.url).installed() == .none)
}

@Test func the_installed_release_is_the_one_current_names() throws {
  let home = try Home()
  try home.write(".local/share/board/releases/old/release.json", home.release("old"))
  try home.link(".local/share/board/current", to: "releases/old")
  let installed = Machine(home: home.url).installed()
  guard case .release(let id, let release) = installed else {
    Issue.record("nothing is installed")
    return
  }
  #expect(id == "old")
  #expect(release?.id == "old")
}

@Test func a_current_link_with_no_readable_release_still_names_its_id() throws {
  let home = try Home()
  try home.link(".local/share/board/current", to: "releases/gone")
  #expect(Machine(home: home.url).installed() == .release(id: "gone", nil))
}

@Test func the_survey_names_the_personal_board_the_others_and_those_using_controls() throws {
  let home = try Home()
  let root = home.url.path
  try home.write(
    ".config/board/config.json",
    #"{"personal": "\#(root)/board", "boards": ["\#(root)/board", "\#(root)/board/team", "\#(root)/old"]}"#
  )
  try home.write("board/.board/board.json", #"{"plugins": ["rules", "evals"]}"#)
  try home.write("board/team/.board/board.json", #"{"plugins": ["evals"]}"#)
  try home.write("old/.board/board.json", #"{"plugins": ["controls"]}"#)
  let survey = Machine(home: home.url).survey()
  #expect(survey.personal?.path == "\(root)/board")
  #expect(survey.others.map(\.path) == ["\(root)/board/team"])
  #expect(survey.controls.map(\.path) == ["\(root)/old"])
}

@Test func a_home_with_no_config_has_no_boards() throws {
  let home = try Home()
  let survey = Machine(home: home.url).survey()
  #expect(survey.personal == nil)
  #expect(survey.others.isEmpty && survey.controls.isEmpty)
}

@Test func the_survey_finds_the_old_attention_plugins_links() throws {
  let home = try Home()
  #expect(Machine(home: home.url).survey().old == [])
  try home.link(".local/share/board/plugins/attention", to: "/somewhere/board-attention")
  try home.write(
    ".claude/plugins/installed_plugins.json",
    #"{"version": 2, "plugins": {"board-controls@board": [], "rust-analyzer-lsp@x": []}}"#)
  #expect(Machine(home: home.url).survey().old == [.pythonAttention])
}

@Test func the_attention_approve_mod_alone_is_not_the_old_attention_plugins_links() throws {
  let home = try Home()
  try home.write(
    ".claude/plugins/installed_plugins.json",
    #"{"plugins": {"attention-approve@attention": []}}"#)
  #expect(Machine(home: home.url).survey().old == [])
  try home.link(".claude/skills/attention", to: "/somewhere/board-attention")
  #expect(Machine(home: home.url).survey().old == [.pythonAttention])
}

@Test func the_path_for_install_is_the_login_shells_or_the_apps_with_local_bin_first() {
  let home = URL(fileURLWithPath: "/Users/a")
  #expect(
    installPath(login: "/opt/bin:/usr/bin", app: "/usr/bin:/bin", home: home) == "/opt/bin:/usr/bin"
  )
  #expect(
    installPath(login: nil, app: "/usr/bin:/bin", home: home) == "/Users/a/.local/bin:/usr/bin:/bin"
  )
}

/// A shell that runs the real one with a scratch home, so the test reads no
/// one's own startup files. It has the real shell's name, which loginPath
/// reads.
private func shell(_ real: String, home: borrowing Home) throws -> String {
  let folder = home.url.appendingPathComponent("shells")
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let wrapper = folder.appendingPathComponent(URL(fileURLWithPath: real).lastPathComponent)
  try Data("#!/bin/sh\nexec /usr/bin/env -i HOME='\(home.url.path)' '\(real)' \"$@\"\n".utf8)
    .write(to: wrapper)
  try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
  return wrapper.path
}

@Test func zsh_as_a_login_shell_reports_its_path() async throws {
  let home = try Home()
  try home.write(".zprofile", "export PATH=/from/zprofile:$PATH\n")
  let path = await loginPath(shell: try shell("/bin/zsh", home: home), home: home.url)
  #expect(path?.hasPrefix("/from/zprofile:") == true)
}

@Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/fish")))
func fish_as_a_login_shell_reports_its_path_joined_by_colons() async throws {
  let home = try Home()
  try home.write(
    ".config/fish/config.fish", "if status is-login; set -gx PATH /from/fish $PATH; end\n")
  let path = await loginPath(shell: try shell("/opt/homebrew/bin/fish", home: home), home: home.url)
  #expect(path?.hasPrefix("/from/fish:") == true)
}

@Test func a_login_shell_that_prints_a_banner_first_still_reports_its_path() async throws {
  let home = try Home()
  try home.write("banner", "#!/bin/sh\necho 'Welcome!'\necho\necho /a/bin:/usr/bin\n")
  try FileManager.default.setAttributes(
    [.posixPermissions: 0o755], ofItemAtPath: home.url.appendingPathComponent("banner").path)
  #expect(
    await loginPath(shell: home.url.appendingPathComponent("banner").path, home: home.url)
      == "/a/bin:/usr/bin")
}

@Test func a_login_shell_that_fails_or_hangs_reports_no_path() async throws {
  let home = try Home()
  try home.write("fails", "#!/bin/sh\nexit 3\n")
  try home.write("hangs", "#!/bin/sh\nexec /bin/sleep 30\n")
  for name in ["fails", "hangs"] {
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: home.url.appendingPathComponent(name).path)
  }
  #expect(
    await loginPath(shell: home.url.appendingPathComponent("fails").path, home: home.url) == nil)
  #expect(
    await loginPath(
      shell: home.url.appendingPathComponent("hangs").path, home: home.url,
      runner: Runner(timeout: .milliseconds(200))) == nil)
}

@Test func zsh_that_adds_local_bin_only_in_zshrc_reports_it_from_an_interactive_shell() async throws
{
  let home = try Home()
  try home.write(".zshrc", "export PATH=\(home.url.path)/.local/bin:$PATH\n")
  let path = await loginPath(shell: try shell("/bin/zsh", home: home), home: home.url)
  #expect(path?.hasPrefix("\(home.url.path)/.local/bin:") == true)
}

@Test func bash_that_adds_local_bin_only_in_bashrc_reports_it_from_an_interactive_shell()
  async throws
{
  let home = try Home()
  try home.write(".bashrc", "export PATH=\(home.url.path)/.local/bin:$PATH\n")
  try home.write(".bash_profile", "[ -n \"$PS1\" ] && . ~/.bashrc\n")
  let path = await loginPath(shell: try shell("/bin/bash", home: home), home: home.url)
  #expect(path?.hasPrefix("\(home.url.path)/.local/bin:") == true)
}
