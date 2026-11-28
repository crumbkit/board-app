// What `board-sign line` gave the install sheet's signing step: this Mac's
// line for Board's allowed signers file, or the message and exit the sheet
// shows when it gave none.
import Launcher

/// How long the sheet waits for `board-sign line`, which makes a key in the
/// Secure Enclave when there is none.
public let signerTimeout: Duration = .seconds(30)

public enum SignerLine: Equatable, Sendable {
  case line(String)
  /// board-sign's last message on stderr, and how the command ended.
  case failed(message: String, exit: String)

  /// The result of `board-sign line` from what it printed and how it ended.
  /// It gives a line only when the command exited 0 and printed exactly one
  /// line, an `owner` line, on stdout. Another message on stderr, such as a
  /// note that the key could not be moved, does not stop it.
  public init(_ lines: [RunLine], outcome: RunOutcome) {
    let printed = lines.filter { $0.stream == .stdout && !$0.text.isEmpty }.map(\.text)
    let message =
      lines.last { $0.stream == .stderr && !$0.text.isEmpty }?.text
      ?? "board-sign printed no message"
    switch outcome {
    case .exited(status: 0):
      if printed.count == 1, let line = printed.first, line.hasPrefix("owner ") {
        self = .line(line)
      } else {
        self = .failed(
          message: "board-sign printed no line for this Mac", exit: "board-sign line exited with 0")
      }
    case .exited(let status):
      self = .failed(message: message, exit: "board-sign line exited with \(status)")
    case .timedOut:
      self = .failed(
        message: message,
        exit:
          "board-sign line took longer than \(signerTimeout.components.seconds) seconds and was stopped"
      )
    case .overCap:
      self = .failed(message: message, exit: "board-sign line printed too much and was stopped")
    case .notStarted(let reason):
      self = .failed(
        message: "board-sign could not start: \(reason)", exit: "board-sign line did not start")
    }
  }
}
