// The name and email git puts on commits for this account, which a new
// personal board's first commits need. Install/install applies the same
// email rule to --git-email.
import Foundation
import Launcher

/// The global `user.name` and `user.email`, each nil when unset or blank.
public struct GitIdentity: Sendable, Hashable {
  public let name: String?
  public let email: String?

  public init(name: String?, email: String?) {
    self.name = name
    self.email = email
  }

  /// Whether git has both a name and an email.
  public var complete: Bool { name != nil && email != nil }

  /// Reads both values with `git config --global --get`. `git` is the
  /// command that runs git. A git that does not run reads as no identity.
  public static func read(
    git: [String] = ["/usr/bin/git"], runner: Runner = Runner(timeout: .seconds(5))
  ) async -> GitIdentity {
    async let name = value("user.name", git: git, runner: runner)
    async let email = value("user.email", git: git, runner: runner)
    return await GitIdentity(name: name, email: email)
  }

  /// Whether `text` has one `@`, text on both sides of it, and no white space.
  public static func isEmail(_ text: String) -> Bool {
    let parts = text.split(separator: "@", omittingEmptySubsequences: false)
    return parts.count == 2 && parts.allSatisfy { !$0.isEmpty }
      && !text.contains(where: \.isWhitespace)
  }

  private static func value(_ key: String, git: [String], runner: Runner) async -> String? {
    let result = await runner.run(git + ["config", "--global", "--get", key])
    // Nil is right: git exits 1 for an unset key, and a git that fails sets nothing.
    guard let output = try? result.output() else { return nil }
    let value = String(decoding: output, as: UTF8.self).trimmingCharacters(
      in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}
