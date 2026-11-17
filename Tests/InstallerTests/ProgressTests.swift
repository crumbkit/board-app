import Foundation
import Launcher
import Testing

@testable import Installer

private func out(_ text: String) -> RunLine { RunLine(stream: .stdout, text: text) }
private func err(_ text: String) -> RunLine { RunLine(stream: .stderr, text: text) }

private func progress(_ lines: [RunLine]) -> InstallProgress {
  var progress = InstallProgress()
  for line in lines { progress.read(line) }
  return progress
}

@Test func each_line_the_installer_prints_parses_into_its_kind() {
  #expect(InstallerLine("::step 4 Install skills") == .step(4, "Install skills"))
  #expect(InstallerLine("::done 4 Installed 17 skills") == .done(4, "Installed 17 skills"))
  #expect(
    InstallerLine("::warn 6 Installed no Claude Code mods, because claude is not on PATH")
      == .warning(6, "Installed no Claude Code mods, because claude is not on PATH"))
  #expect(InstallerLine("::controls /Users/a/board/team") == .controls("/Users/a/board/team"))
  #expect(InstallerLine("::path /Users/a/.local/bin") == .path("/Users/a/.local/bin"))
  #expect(InstallerLine("::refusal Add it to PATH.") == .refusal("Add it to PATH."))
  #expect(InstallerLine("Copied release board-x.") == .text("Copied release board-x."))
}

@Test func a_line_that_only_looks_like_a_step_is_text() {
  #expect(InstallerLine("::step four Install skills") == .text("::step four Install skills"))
  #expect(InstallerLine("::step 9 Something new") == .text("::step 9 Something new"))
  #expect(InstallerLine("::other 1 x") == .text("::other 1 x"))
}

@Test func the_app_names_the_same_seven_steps_as_the_installer() throws {
  let installer = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Install/install")
  let script = try String(contentsOf: installer, encoding: .utf8)
  let steps = script.split(separator: "\n").compactMap { line -> String? in
    let line = line.trimmingCharacters(in: .whitespaces)
    guard line.hasPrefix("step "), let quote = line.firstIndex(of: "\"") else { return nil }
    return
      "\(line.dropFirst(5).prefix(while: { $0 != " " })) \(line[quote...].dropFirst().dropLast())"
  }
  #expect(steps == InstallProgress.labels.enumerated().map { "\($0.offset + 1) \($0.element)" })
}

@Test func a_step_is_waiting_then_running_then_done() {
  var progress = InstallProgress()
  #expect(progress.state(of: 1) == .waiting)
  progress.read(out("::step 1 Check this Mac"))
  #expect(progress.state(of: 1) == .running)
  #expect(progress.state(of: 2) == .waiting)
  progress.read(out("::done 1 Checked this Mac"))
  #expect(progress.state(of: 1) == .done("Checked this Mac"))
}

@Test func a_warning_is_kept_with_its_step() {
  let progress = progress([
    out("::step 6 Install Claude Code mods"),
    out("::warn 6 Installed no Claude Code mods, because claude is not on PATH"),
  ])
  #expect(
    progress.state(of: 6)
      == .warning("Installed no Claude Code mods, because claude is not on PATH")
  )
  #expect(progress.results.map(\.step) == [6])
}

@Test func the_output_holds_every_line_for_a_person_and_no_marker() {
  let progress = progress([
    out("::step 1 Check this Mac"), out("Checked it."), err("a warning"),
    out("::done 1 Checked this Mac"),
  ])
  #expect(progress.output == ["Checked it.", "a warning"])
}

@Test func the_refusal_is_what_standard_error_said_since_the_step_started() {
  let progress = progress([
    out("::step 1 Check this Mac"), err("noise before"), out("::done 1 Checked this Mac"),
    out("::step 2 Copy the release"), out("::path /h/.local/share/board/plugins/attention"),
    err(
      "install: /h/.local/share/board/plugins/attention is a folder, not a link the installer made."
    ),
  ])
  #expect(
    progress.refusal
      == "/h/.local/share/board/plugins/attention is a folder, not a link the installer made.")
  #expect(progress.path == "/h/.local/share/board/plugins/attention")
}

@Test func the_boards_that_still_use_controls_are_collected() {
  let progress = progress([out("::controls /h/team"), out("::controls /h/work")])
  #expect(progress.controls == ["/h/team", "/h/work"])
}

@Test func a_run_that_exits_zero_is_installed() {
  let progress = progress([out("::step 1 Check this Mac"), out("::done 1 Checked this Mac")])
  #expect(InstallOutcome(progress, exit: .exited(status: 0)) == .installed)
}

@Test func a_run_that_fails_during_a_step_stopped_there() {
  let progress = progress([
    out("::step 1 Check this Mac"), out("::done 1 Checked this Mac"),
    out("::step 4 Install skills"), err("error: a folder is not Board's"),
    err("install: board skills install refused."),
  ])
  let outcome = InstallOutcome(progress, exit: .exited(status: 1))
  #expect(
    outcome
      == .stopped(
        Stop(
          stage: .step(4), refusal: "error: a folder is not Board's\nboard skills install refused.",
          path: nil, exit: "install exited 1")))
}

@Test func a_run_that_timed_out_or_did_not_start_says_so() {
  let empty = InstallProgress()
  guard case .stopped(let late) = InstallOutcome(empty, exit: .timedOut),
    case .stopped(let unstarted) = InstallOutcome(empty, exit: .notStarted("No such file"))
  else {
    Issue.record("the runs did not stop")
    return
  }
  #expect(late.exit == "install took longer than 10 minutes and was stopped")
  #expect(unstarted.exit == "install could not start: No such file")
  #expect(unstarted.stage == .step(1))
}

@Test func the_summary_says_what_a_stop_left_behind() {
  let first = Stop(stage: .step(1), refusal: "", path: nil, exit: "")
  #expect(
    first.summary(installed: "f534257a")
      == "The installer stopped while checking this Mac, before it changed anything. The installed release, f534257a, still runs."
  )
  #expect(
    first.summary(installed: nil)
      == "The installer stopped while checking this Mac, before it changed anything.")
  let skills = Stop(stage: .step(4), refusal: "", path: nil, exit: "")
  #expect(
    skills.summary(installed: "f534257a").hasPrefix(
      "The installer stopped while installing skills."))
}

@Test func a_run_that_fails_after_its_last_step_without_naming_a_path_stopped_in_that_step() {
  let progress = progress([
    out("::step 5 Enable plugins in your boards"), out("::done 5 Enabled plugins in 1 board"),
    err("install: something went wrong"),
  ])
  guard case .stopped(let stop) = InstallOutcome(progress, exit: .exited(status: 1)) else {
    Issue.record("the run did not stop")
    return
  }
  #expect(stop.stage == .step(5))
}

@Test func a_refusal_read_before_its_step_line_still_shows() {
  let progress = progress([
    err("install: /h/.local/bin is not on PATH."),
    out("::step 1 Check this Mac"), out("::path /h/.local/bin"),
    out("::refusal /h/.local/bin is not on PATH."),
  ])
  guard case .stopped(let stop) = InstallOutcome(progress, exit: .exited(status: 1)) else {
    Issue.record("the run did not stop")
    return
  }
  #expect(stop.stage == .step(1))
  #expect(stop.refusal == "/h/.local/bin is not on PATH.")
}

@Test func a_refusal_follows_what_a_tool_said_on_standard_error_in_its_step() {
  let progress = progress([
    out("::step 4 Install skills"), err("error: a folder is not Board's"),
    err("install: board skills install refused."), out("::refusal board skills install refused."),
  ])
  #expect(progress.refusal == "error: a folder is not Board's\nboard skills install refused.")
}
