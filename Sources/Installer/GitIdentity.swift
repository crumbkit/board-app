// The name and email git puts on commits for this account, which a new
// personal board's first commits need. Install/install applies the same
// email rule to --git-email.
import Foundation
import Launcher

/// The global `user.name` and `user.email`, each nil when unset or blank.
public struct GitIdentity: Sendable, Hashable {
  public let name: String?
  public let email: String?
  /// Whether a value is unset and the global config has an `[includeIf]`
  /// section, which may set it in some repositories. The installer then
  /// refuses rather than write a value that would override it there.
  public let conditional: Bool

  public init(name: String?, email: String?, conditional: Bool = false) {
    self.name = name
    self.email = email
    self.conditional = conditional
  }

  /// Whether git has both a name and an email.
  public var complete: Bool { name != nil && email != nil }

  /// Why the installer would refuse this identity whatever the sheet is given.
  public var problem: String? { conditional ? Self.conditionalProblem : nil }

  /// The refusal Install/install prints for a conditional identity. A test
  /// checks that the script prints the same text.
  public static let conditionalProblem =
    "Your git name or email is set only through a conditional include, an [includeIf] section of your global git config, so a name Board set there would override it in every repository the include covers. Set user.name and user.email in your global git config outside the conditional include, then try again."

  /// Reads both values with `git config --global --includes --get`, so a
  /// value set in a file the global config includes counts. `git` is the
  /// command that runs git. A git that does not run reads as no identity.
  public static func read(
    git: [String] = ["/usr/bin/git"], runner: Runner = Runner(timeout: .seconds(5))
  ) async -> GitIdentity {
    async let name = value("user.name", git: git, runner: runner)
    async let email = value("user.email", git: git, runner: runner)
    let (found, mail) = await (name, email)
    guard found == nil || mail == nil else { return GitIdentity(name: found, email: mail) }
    let includes = await runner.run(
      git + ["config", "--global", "--get-regexp", #"^includeif\..*\.path$"#])
    // Nil is right: git exits 1 when no key matches, so there is no [includeIf].
    let conditional = (try? includes.output()).map { !$0.isEmpty } ?? false
    return GitIdentity(name: found, email: mail, conditional: conditional)
  }

  /// Whether `text` has one `@`, text on both sides of it, and no white space.
  public static func isEmail(_ text: String) -> Bool {
    let parts = text.split(separator: "@", omittingEmptySubsequences: false)
    return parts.count == 2 && parts.allSatisfy { !$0.isEmpty }
      && !text.contains(where: \.isWhitespace)
  }

  private static func value(_ key: String, git: [String], runner: Runner) async -> String? {
    let result = await runner.run(git + ["config", "--global", "--includes", "--get", key])
    // Nil is right: git exits 1 for an unset key, and a git that fails sets nothing.
    guard let output = try? result.output() else { return nil }
    let value = String(decoding: output, as: UTF8.self).trimmingCharacters(
      in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}
