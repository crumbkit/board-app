// What the Mac holds that the install sheet describes: the installed
// release, the known boards, the old attention plugin and mods, and the
// person's PATH. This file owns the module's reads of the file system.
import Foundation
import Launcher

/// A piece of an older Board that the install removes.
public enum OldPiece: Sendable, Hashable {
  /// The Python attention plugin's links, which the install removes.
  case pythonAttention
  /// The board-controls mod, which board-rules replaces.
  case boardControls
}

/// The boards Board's config names, and the old pieces on the Mac.
public struct Survey: Sendable, Hashable {
  /// The personal board, or nil when the config names none. It is also in
  /// `controls` when it still names controls.
  public let personal: URL?
  /// The other known boards whose plugins the install refreshes.
  public let others: [URL]
  /// The known boards that still name controls, which the install leaves.
  public let controls: [URL]
  public let old: [OldPiece]
}

/// Reads one home directory.
public struct Machine: Sendable {
  public let home: URL

  public init(home: URL) { self.home = home }

  private var share: URL { home.appendingPathComponent(".local/share/board") }

  /// The release ~/.local/share/board/current names.
  public func installed() -> Installed {
    let current = share.appendingPathComponent("current")
    // Nil is right: a missing link means no release is installed.
    guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)
    else { return .none }
    let id = URL(fileURLWithPath: target).lastPathComponent
    // Nil is right: Offer only needs the id when the release cannot be read.
    let data = try? Data(contentsOf: current.appendingPathComponent("release.json"))
    return .release(id: id, data.flatMap { try? Release(json: $0) })
  }

  public func survey() -> Survey {
    let config = json(home.appendingPathComponent(".config/board/config.json"))
    let personal = (config?["personal"] as? String).map { URL(fileURLWithPath: $0) }
    var others: [URL] = []
    var controls: [URL] = []
    var seen = Set<String>()
    let boards = (personal.map { [$0.path] } ?? []) + (config?["boards"] as? [String] ?? [])
    for path in boards where seen.insert(path).inserted {
      let board = URL(fileURLWithPath: path)
      let manifest = json(board.appendingPathComponent(".board/board.json"))
      if (manifest?["plugins"] as? [String] ?? []).contains("controls") {
        controls.append(board)
      } else if board != personal {
        others.append(board)
      }
    }
    let mods = json(home.appendingPathComponent(".claude/plugins/installed_plugins.json"))
    let installed = (mods?["plugins"] as? [String: Any]).map { Set($0.keys) } ?? []
    var old: [OldPiece] = []
    let links = [
      share.appendingPathComponent("plugins/attention"),
      home.appendingPathComponent(".claude/skills/attention"),
    ]
    // Nil is right: no link there means the old plugin is not linked.
    if links.contains(where: {
      (try? FileManager.default.destinationOfSymbolicLink(atPath: $0.path)) != nil
    }) {
      old.append(.pythonAttention)
    }
    if installed.contains("board-controls@board") { old.append(.boardControls) }
    return Survey(personal: personal, others: others, controls: controls, old: old)
  }

  /// The mods in a release's Claude Code marketplace, in its order.
  public static func mods(release: URL) -> [String] {
    let marketplace = json(release.appendingPathComponent(".claude-plugin/marketplace.json"))
    return (marketplace?["plugins"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
  }
}

/// A JSON object from a file of at most 1 MB, or nil when there is none.
private func json(_ file: URL) -> [String: Any]? {
  // Nil is right: a missing or unreadable file reads as nothing to describe.
  guard let handle = try? FileHandle(forReadingFrom: file),
    let data = try? handle.read(upToCount: 1_000_000)
  else { return nil }
  // Nil is right: a file that is not a JSON object describes nothing.
  return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

/// The PATH a login shell sets up, which an app opened from Finder does not
/// get. The shell runs `printenv`, which prints the exported PATH joined by
/// colons in zsh, bash and fish alike. zsh and bash read .zshrc and .bashrc,
/// where many people add ~/.local/bin, only when interactive, so when the
/// login PATH lacks `home`'s ~/.local/bin they run again with `-i`, with the
/// same timeout. Nil when the shell fails or takes longer than the timeout.
public func loginPath(
  shell: String, home: URL, runner: Runner = Runner(timeout: .seconds(5))
) async -> String? {
  let local = home.appendingPathComponent(".local/bin").path
  let login = await path(from: runner, [shell, "-l", "-c", "/usr/bin/printenv PATH"])
  guard login.map({ !$0.split(separator: ":").contains(Substring(local)) }) ?? true,
    ["zsh", "bash"].contains(URL(fileURLWithPath: shell).lastPathComponent)
  else { return login }
  let interactive = await path(from: runner, [shell, "-i", "-l", "-c", "/usr/bin/printenv PATH"])
  return interactive.flatMap { $0.split(separator: ":").contains(Substring(local)) ? $0 : nil }
    ?? login
}

/// The PATH a shell printed as the last line of its output, or nil.
private func path(from runner: Runner, _ argv: [String]) async -> String? {
  let result = await runner.run(argv)
  // Nil is right: a shell that fails gives the fallback PATH.
  guard let output = try? result.output() else { return nil }
  // A startup file may print before the command runs, so PATH is the last line.
  let last = String(decoding: output, as: UTF8.self).split(separator: "\n").last
  return last.map(String.init).flatMap { $0.contains("/") ? $0 : nil }
}

/// The PATH install runs with: the login shell's, or when that could not be
/// read, the app's with ~/.local/bin first, since install refuses without it.
public func installPath(login: String?, app: String, home: URL) -> String {
  login ?? "\(home.appendingPathComponent(".local/bin").path):\(app)"
}
