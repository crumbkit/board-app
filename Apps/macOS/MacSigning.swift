// The install sheet's "Let this Mac sign" step: it makes this Mac's key with
// board-sign, shows the one line Board's allowed signers file needs, and
// writes it after Touch ID. It reads the file to say whether the line is
// there, so the menu bar offers the step while it is missing.
import Foundation
import Installer
import Launcher
import LocalAuthentication
import Pairing

@MainActor
@Observable
final class MacSigning {
  enum Phase: Equatable {
    /// Reading the key and the file.
    case checking
    /// No key yet: Make Key makes one. True while it runs.
    case noKey(making: Bool)
    /// The line to add, and the other lines the file keeps.
    case line(String, MacLine.Kept, authorizing: Bool)
    /// The line is in the file.
    case written(MacLine.Kept, writableBy: String)
    /// board-sign gave no line. `making` when it was asked to make the key.
    case cannotSign(message: String, exit: String, making: Bool)
    /// The file was left as it was.
    case refused(AllowedSignersFile.Refusal)
    /// The file could not be read or written.
    case failed(String)
  }

  private(set) var phase = Phase.checking
  /// What Board's file holds for this Mac's line, or nil until read.
  private(set) var status: MacLine.Status?

  /// Whether the menu bar offers Let This Mac Sign…: the line is missing,
  /// or a line of this Mac's key lacks a namespace.
  var needed: Bool { status.map { $0 != .current } ?? false }

  var authorizing: Bool {
    if case .line(_, _, authorizing: true) = phase { return true }
    return false
  }

  private let home = FileManager.default.homeDirectoryForCurrentUser
  private var signer: URL { home.appendingPathComponent(".local/bin/board-sign") }

  /// Whether board-sign has a key: at Board's path, or at the older signer's,
  /// which board-sign moves to Board's path when it next runs.
  private var keyMade: Bool {
    [".config/board/secure-enclave-key", ".config/attention/secure-enclave-key"].contains {
      FileManager.default.fileExists(atPath: home.appendingPathComponent($0).path)
    }
  }

  /// Reads the status again. It runs board-sign only when a key exists, so
  /// it never makes one.
  func refresh() async {
    guard keyMade, case .line(let line) = await readLine() else {
      status = .missing
      return
    }
    // A file Board cannot read reads as missing the line, so the menu
    // offers the step, and the step names the file and the error.
    status =
      (try? SignersFiles.read(SignersFiles.board)).map { MacLine.status(of: line, in: $0) }
      ?? .missing
  }

  /// Shows the step: the line when a key exists, and Make Key when not.
  func start() async {
    guard keyMade else {
      phase = .noKey(making: false)
      return
    }
    phase = .checking
    await show(await readLine(), making: false)
  }

  /// Make Key: board-sign makes the key when there is none and prints the
  /// line. Making it needs no Touch ID.
  func makeKey() async {
    phase = .noKey(making: true)
    await show(await readLine(), making: true)
  }

  /// Try Again after a failure.
  func retry() async {
    if case .cannotSign(_, _, making: true) = phase, !keyMade {
      await makeKey()
    } else {
      await start()
    }
  }

  /// Add with Touch ID: Touch ID alone, with no password button, then the
  /// file is checked and written. The line is the one shown before Touch ID.
  /// Cancelling leaves the line shown and writes nothing.
  func add() async {
    guard case .line(let line, let kept, authorizing: false) = phase,
      let key = MacLine.key(of: line)
    else { return }
    phase = .line(line, kept, authorizing: true)
    let context = LAContext()
    context.localizedFallbackTitle = ""
    do {
      try await context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        localizedReason: "let this Mac's key sign approvals and orders for you")
    } catch let error as LAError where error.code == .userCancel || error.code == .appCancel {
      phase = .line(line, kept, authorizing: false)
      return
    } catch {
      phase = .cannotSign(
        message: error.localizedDescription, exit: "Touch ID did not finish", making: false)
      return
    }
    do {
      let kept = try SignersFiles.addMac(line, key: key)
      phase = .written(kept, writableBy: writableBy())
    } catch let refusal as AllowedSignersFile.Refusal {
      phase = .refused(refusal)
    } catch {
      phase = .failed(
        "Board could not write \(SignersFiles.shown(SignersFiles.board)): \(error.localizedDescription)"
      )
    }
    await refresh()
  }

  private func show(_ result: SignerLine, making: Bool) async {
    switch result {
    case .line(let line):
      do {
        let text = try SignersFiles.read(SignersFiles.board)
        guard let key = MacLine.key(of: line) else {
          phase = .cannotSign(
            message: "board-sign printed a line with no key Board can read",
            exit: "board-sign line exited with 0", making: making)
          return
        }
        phase = .line(line, MacLine.kept(in: text, key: key), authorizing: false)
      } catch {
        phase = .failed(
          "Board could not read \(SignersFiles.shown(SignersFiles.board)): \(error.localizedDescription)"
        )
      }
    case .failed(let message, let exit):
      phase = .cannotSign(message: message, exit: exit, making: making)
    }
    await refresh()
  }

  /// Who may write the file after the write: you, or root when it owns it.
  private func writableBy() -> String {
    let attributes = try? FileManager.default.attributesOfItem(
      atPath: SignersFiles.board.resolvingSymlinksInPath().path)
    let owner = (attributes?[.ownerAccountID] as? NSNumber)?.uint32Value
    return owner == 0 ? "root" : "you"
  }

  /// Runs `board-sign line` off the main actor.
  private func readLine() async -> SignerLine {
    let path = signer.path
    guard FileManager.default.isExecutableFile(atPath: path) else {
      return .failed(
        message:
          "board-sign is not installed at \(SignersFiles.shown(signer)). Install Board, then try again.",
        exit: "board-sign line did not start")
    }
    return await Self.run(path)
  }

  @concurrent
  private static func run(_ path: String) async -> SignerLine {
    let (stream, sink) = AsyncStream.makeStream(of: RunLine.self)
    let result = await Runner(timeout: signerTimeout).run([path, "line"]) { sink.yield($0) }
    sink.finish()
    var lines: [RunLine] = []
    for await line in stream { lines.append(line) }
    return SignerLine(lines, outcome: result.outcome)
  }
}
