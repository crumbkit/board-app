// Where board-sign keeps the Mac's Secure Enclave key: Board's config folder.
// attention-sign, the signer before it, kept the key in attention's folder,
// so board-sign moves that key on its first run and leaves a symlink behind,
// and the old attention-sign signs with the same key.
import Foundation

nonisolated struct KeyFile: Sendable {
  let home: URL

  /// `~/.config/board/secure-enclave-key`.
  var current: URL { home.appendingPathComponent(".config/board/secure-enclave-key") }

  /// `~/.config/attention/secure-enclave-key`, attention-sign's path.
  var attention: URL { home.appendingPathComponent(".config/attention/secure-enclave-key") }

  enum Located: Equatable, Sendable {
    /// The key is at this path.
    case found(URL)
    /// No key exists; one may be made at this path.
    case none(URL)
    /// The key stays at attention-sign's path, because moving it failed.
    case unmoved(URL, problem: String)
  }

  /// Finds the key, first moving attention-sign's key to Board's path when
  /// only that one exists. A key already at Board's path is used as it is,
  /// whatever attention's path holds. Nothing is made here.
  func locate() -> Located {
    let manager = FileManager.default
    guard !manager.fileExists(atPath: current.path) else { return .found(current) }
    guard manager.fileExists(atPath: attention.path) else { return .none(current) }
    do {
      try manager.createDirectory(
        at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
      try manager.moveItem(at: attention, to: current)
    } catch {
      return .unmoved(
        attention,
        problem:
          "could not move the key to \(current.path), so it stays at \(attention.path): \(error.localizedDescription)"
      )
    }
    do {
      try manager.createSymbolicLink(at: attention, withDestinationURL: current)
    } catch {
      // Without the link the old attention-sign would find no key, so the
      // key goes back where it was.
      let link = error.localizedDescription
      do {
        try manager.moveItem(at: current, to: attention)
      } catch {
        return .found(current)
      }
      return .unmoved(
        attention,
        problem: "could not leave a link at \(attention.path), so the key stays there: \(link)")
    }
    return .found(current)
  }
}
