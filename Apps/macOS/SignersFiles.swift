// Board's allowed signers file: pairing adds and removes a paired device's
// line, the install sheet's signing step writes this Mac's own line, and the
// window reads back the devices it admits. Every other line stays as it was.
import Foundation
import Pairing
import SSHSig

enum SignersFiles {
  static let board = home(".config/board/allowed_signers")

  /// The line `pair` would write, for the sheet's Details.
  static func lines(_ device: Device, scope: Scope) -> [(URL, String)] {
    AllowedSigners.boardLine(device, scope: scope).map { [(board, $0)] } ?? []
  }

  /// Writes the device's one line, or removes it when the owner ticked
  /// nothing.
  static func pair(_ device: Device, scope: Scope) throws {
    try AllowedSignersFile.update(
      board, device: device.id, line: AllowedSigners.boardLine(device, scope: scope))
  }

  /// Removes the device's line.
  static func remove(_ id: String) throws {
    try AllowedSignersFile.remove(device: id, from: [board])
  }

  /// The devices the file admits. A missing file admits none.
  static func paired() throws -> [PairedDevice] {
    PairedDevice.list(board: try read(board))
  }

  /// Writes this Mac's own line, replacing any line with its key, and
  /// returns the other lines it kept.
  static func addMac(_ line: String, key: Data) throws -> MacLine.Kept {
    try AllowedSignersFile.setOwn(board, key: key, line: line)
  }

  /// The file's text, or "" when it is missing.
  static func read(_ file: URL) throws -> String {
    do {
      return try String(contentsOf: file, encoding: .utf8)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return ""
    }
  }

  /// `~/…` for a file in the home directory, as the window shows it.
  static func shown(_ file: URL) -> String {
    file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~", options: .anchored)
  }

  private static func home(_ path: String) -> URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path)
  }
}
