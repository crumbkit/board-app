import Foundation

/// Lines of the two allowed signers files: `~/.config/board/allowed_signers`
/// for Board and `~/.config/attention/allowed_signers` for attention. Board
/// and ssh-keygen parse these lines, so their text is wire format.
public enum AllowedSigners {
  /// The Mac's own line for Board's file: approvals and the owner's own
  /// writes, which only the Mac's key may sign.
  public static func macLine(x963: Data, comment: String) -> String {
    line(x963: x963, comment: comment, [approvalNamespace, writeNamespace])
  }

  /// A paired device's line for Board's file, or nil when it may approve
  /// nothing. A device never gets `board/write/v1`.
  public static func deviceBoardLine(x963: Data, label: String, approves: Bool) -> String? {
    approves ? line(x963: x963, comment: label, [approvalNamespace]) : nil
  }

  /// A paired device's line for attention's file, or nil when it may not sign
  /// orders.
  public static func deviceAttentionLine(x963: Data, label: String, signsOrders: Bool) -> String? {
    signsOrders ? line(x963: x963, comment: label, [orderNamespace]) : nil
  }

  private static func line(x963: Data, comment: String, _ namespaces: [String]) -> String {
    let key = openSSHPublicKey(x963: x963, comment: comment)
    return "owner namespaces=\"\(namespaces.joined(separator: ","))\" \(key)"
  }
}
