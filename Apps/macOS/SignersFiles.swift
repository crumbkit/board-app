// Adds a paired device's lines to the two allowed signers files. Every other
// line, the Mac's own key among them, stays as it was.
import Foundation
import Pairing

enum SignersFiles {
  static let board = home(".config/board/allowed_signers")
  static let attention = home(".config/attention/allowed_signers")

  /// The lines `pair` would write, for the sheet's Details.
  static func lines(_ device: Device, scope: Scope) -> [(URL, String)] {
    [
      (board, AllowedSigners.boardLine(device, scope: scope)),
      (attention, AllowedSigners.attentionLine(device, scope: scope)),
    ].compactMap { file, line in line.map { (file, $0) } }
  }

  /// Writes the device's line to each file, or removes it from a file whose
  /// scope the owner left unticked.
  static func pair(_ device: Device, scope: Scope) throws {
    try AllowedSignersFile.update(
      board, device: device.id, line: AllowedSigners.boardLine(device, scope: scope))
    try AllowedSignersFile.update(
      attention, device: device.id, line: AllowedSigners.attentionLine(device, scope: scope))
  }

  private static func home(_ path: String) -> URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path)
  }
}
