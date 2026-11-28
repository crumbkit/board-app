import Foundation
import Launcher
import Testing

@testable import Installer

private func out(_ text: String) -> RunLine { RunLine(stream: .stdout, text: text) }
private func err(_ text: String) -> RunLine { RunLine(stream: .stderr, text: text) }

/// The install sheet's Make Key runs `board-sign line`; these are the
/// results the sheet shows from what it printed and how it ended.
struct SignerLineTests {
  let line = "owner namespaces=\"a,b,c\" ecdsa-sha2-nistp256 AAAA board"

  @Test func the_line_board_sign_prints_is_this_macs_line() {
    #expect(SignerLine([out(line)], outcome: .exited(status: 0)) == .line(line))
  }

  @Test func a_note_on_stderr_beside_the_line_still_gives_the_line() {
    #expect(
      SignerLine(
        [err("board-sign: could not move the key to /k, so it stays at /a: denied"), out(line)],
        outcome: .exited(status: 0)) == .line(line))
  }

  @Test func a_failure_shows_board_signs_last_message_and_its_exit() {
    let result = SignerLine(
      [
        err("2026 AppKit warning"),
        err("board-sign: cannot describe the key's access: no fingerprint is enrolled"),
      ], outcome: .exited(status: 1))
    #expect(
      result
        == .failed(
          message: "board-sign: cannot describe the key's access: no fingerprint is enrolled",
          exit: "board-sign line exited with 1"))
  }

  @Test func output_that_is_not_one_line_is_a_failure() {
    #expect(
      SignerLine([out("usage: x")], outcome: .exited(status: 0))
        == .failed(
          message: "board-sign printed no line for this Mac", exit: "board-sign line exited with 0")
    )
  }

  @Test func a_signer_that_did_not_start_or_was_stopped_says_so() {
    #expect(
      SignerLine([], outcome: .notStarted("no such file"))
        == .failed(
          message: "board-sign could not start: no such file", exit: "board-sign line did not start"
        ))
    #expect(
      SignerLine([], outcome: .timedOut)
        == .failed(
          message: "board-sign printed no message",
          exit: "board-sign line took longer than 30 seconds and was stopped"))
  }
}
