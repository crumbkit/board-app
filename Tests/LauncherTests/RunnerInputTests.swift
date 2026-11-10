import Foundation
import Testing

@testable import Launcher

/// The runner feeds a command's standard input, and `output()` turns a run
/// into its stdout or a failure that carries what the command printed.
@Test func a_command_reads_the_input_it_is_given() async {
  let input = Data("signature".utf8)
  let result = await Runner().run(["/bin/cat"], input: input)
  #expect(result.outcome == .exited(status: 0))
  #expect(result.stdout == input)
}

@Test func an_input_larger_than_a_pipe_holds_comes_back_whole() async {
  let input = Data(repeating: 0x61, count: 1_000_000)
  let result = await Runner(cap: 2_000_000).run(["/bin/cat"], input: input)
  #expect(result.outcome == .exited(status: 0))
  #expect(result.stdout == input)
}

@Test func a_command_that_never_reads_its_input_still_reports_its_exit() async {
  let input = Data(repeating: 0x61, count: 1_000_000)
  let result = await Runner().run(["/usr/bin/true"], input: input)
  #expect(result.outcome == .exited(status: 0))
}

@Test func a_command_given_no_input_reads_end_of_file() async {
  let result = await Runner().run(["/bin/cat"])
  #expect(result.outcome == .exited(status: 0))
  #expect(result.stdout.isEmpty)
}

@Test func a_command_that_prints_past_the_cap_and_exits_at_once_reads_as_over_the_cap() async {
  let result = await Runner(cap: 3).run(["/bin/echo", "hello"])
  #expect(result.outcome == .overCap)
  #expect(result.stdout.count == 3)
}

@Test func output_returns_stdout_for_a_successful_command() async throws {
  let result = await Runner().run(["/bin/echo", "hello"])
  #expect(try result.output() == Data("hello\n".utf8))
}

@Test func output_throws_the_stderr_and_stdout_of_a_failed_command() async throws {
  let result = await Runner().run(["/bin/sh", "-c", "echo refusal; echo reason >&2; exit 3"])
  let failure = try #require(throws: RunFailure.self) { try result.output() }
  #expect(failure.command == "sh")
  #expect(failure.output == "reason\n")
  #expect(failure.stdout == Data("refusal\n".utf8))
  #expect(failure.problem == "The command exited with status 3")
}

@Test func output_throws_when_the_command_timed_out() async {
  let result = await Runner(timeout: .milliseconds(100)).run(["/bin/sleep", "10"])
  #expect(throws: RunFailure.self) { try result.output() }
}

@Test func a_stopped_command_gets_sigterm_before_sigkill() async {
  let result = await Runner(timeout: .seconds(1)).run([
    "/bin/sh", "-c", "trap 'echo term; exit 7' TERM; while :; do sleep 0.05; done",
  ])
  #expect(result.outcome == .timedOut)
  #expect(result.stdout == Data("term\n".utf8))
}

@Test func cancelling_the_calling_task_stops_the_command() async {
  let run = Task { await Runner(timeout: .seconds(60)).run(["/bin/sleep", "30"]) }
  run.cancel()
  let result = await run.value
  #expect(result.outcome == .timedOut)
}

@Test func a_child_left_behind_holding_a_pipe_does_not_hold_the_run() async {
  let marker = "sleep 33.\(Int.random(in: 100_000...999_999))"
  let result = await Runner(timeout: .seconds(20)).run([
    "/bin/sh", "-c", "echo before; (\(marker); echo after) & exit 0",
  ])
  _ = await Runner().run(["/usr/bin/pkill", "-f", marker])
  #expect(result.outcome == .exited(status: 0))
  #expect(result.stdout == Data("before\n".utf8))
}
