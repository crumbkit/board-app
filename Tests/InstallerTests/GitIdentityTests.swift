import Foundation
import Launcher
import Testing

@testable import Installer

@Test func an_email_has_one_at_sign_with_text_on_both_sides_and_no_spaces() {
  #expect(GitIdentity.isEmail("ana@example.com"))
  #expect(GitIdentity.isEmail("a@b"))
  #expect(!GitIdentity.isEmail("ana.silva"))
  #expect(!GitIdentity.isEmail("@example.com"))
  #expect(!GitIdentity.isEmail("ana@"))
  #expect(!GitIdentity.isEmail("ana@b@example.com"))
  #expect(!GitIdentity.isEmail("ana silva@example.com"))
  #expect(!GitIdentity.isEmail("ana@example.com "))
  #expect(!GitIdentity.isEmail("ana@exa\tmple.com"))
  #expect(!GitIdentity.isEmail(""))
}

@Test func an_identity_is_complete_only_with_a_name_and_an_email() {
  #expect(GitIdentity(name: "Ana Silva", email: "ana@example.com").complete)
  #expect(!GitIdentity(name: "Ana Silva", email: nil).complete)
  #expect(!GitIdentity(name: nil, email: "ana@example.com").complete)
}

/// A scratch global git config file, removed afterwards.
private struct GlobalConfig: ~Copyable {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

  init(_ text: String) throws { try Data(text.utf8).write(to: url) }

  deinit {
    // Nil is right: a scratch file left behind is harmless.
    try? FileManager.default.removeItem(at: url)
  }

  var git: [String] {
    ["/usr/bin/env", "GIT_CONFIG_GLOBAL=\(url.path)", "GIT_CONFIG_NOSYSTEM=1", "git"]
  }
}

@Test func the_global_identity_is_read_from_git() async throws {
  let config = try GlobalConfig("[user]\n\tname = Ana Silva\n\temail = ana@example.com\n")
  let identity = await GitIdentity.read(git: config.git)
  #expect(identity == GitIdentity(name: "Ana Silva", email: "ana@example.com"))
}

@Test func an_identity_in_a_file_the_global_config_includes_counts() async throws {
  let included = try GlobalConfig("[user]\n\tname = Ana Silva\n\temail = ana@example.com\n")
  let config = try GlobalConfig("[include]\n\tpath = \(included.url.path)\n")
  let identity = await GitIdentity.read(git: config.git)
  #expect(identity == GitIdentity(name: "Ana Silva", email: "ana@example.com"))
}

@Test func an_identity_set_only_through_a_conditional_include_is_reported() async throws {
  let included = try GlobalConfig("[user]\n\tname = Ana Silva\n\temail = ana@example.com\n")
  let config = try GlobalConfig(
    "[includeIf \"gitdir:~/work/\"]\n\tpath = \(included.url.path)\n")
  let identity = await GitIdentity.read(git: config.git)
  #expect(identity == GitIdentity(name: nil, email: nil, conditional: true))
  #expect(!identity.complete)
  #expect(identity.problem == GitIdentity.conditionalProblem)
}

@Test func a_conditional_include_beside_a_set_identity_changes_nothing() async throws {
  let config = try GlobalConfig(
    "[user]\n\tname = Ana Silva\n\temail = ana@example.com\n[includeIf \"gitdir:~/work/\"]\n\tpath = /nowhere\n"
  )
  let identity = await GitIdentity.read(git: config.git)
  #expect(identity == GitIdentity(name: "Ana Silva", email: "ana@example.com"))
  #expect(identity.problem == nil)
}

@Test func an_unset_or_blank_value_reads_as_nil() async throws {
  let config = try GlobalConfig("[user]\n\tname = \"  \"\n")
  let identity = await GitIdentity.read(git: config.git)
  #expect(identity == GitIdentity(name: nil, email: nil))
}

@Test func a_git_that_does_not_run_reads_as_no_identity() async {
  let identity = await GitIdentity.read(git: ["/nonexistent/git"])
  #expect(identity == GitIdentity(name: nil, email: nil))
}

@Test func the_installer_prints_the_same_conditional_refusal_as_the_sheet() throws {
  let installer = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Install/install")
  let script = try String(contentsOf: installer, encoding: .utf8)
  #expect(script.contains("refuse \"\" \"\(GitIdentity.conditionalProblem)\""))
}
