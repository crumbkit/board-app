import Foundation

/// Lines of Board's allowed signers file, `~/.config/board/allowed_signers`.
/// Board checks approvals, the owner's own writes and orders against it.
/// Board and ssh-keygen parse these lines, so their text is wire format.
public enum AllowedSigners {
  /// The Mac's own line: approvals, the owner's own writes, which only the
  /// Mac's key may sign, and orders.
  public static func macLine(x963: Data, comment: String) -> String {
    line(x963: x963, comment: comment, [approvalNamespace, writeNamespace, orderNamespace])
  }

  /// A paired device's one line, or nil when it may sign nothing. A device
  /// never gets `board/write/v1`.
  public static func deviceBoardLine(x963: Data, label: String, approves: Bool, signsOrders: Bool)
    -> String?
  {
    let namespaces = (approves ? [approvalNamespace] : []) + (signsOrders ? [orderNamespace] : [])
    return namespaces.isEmpty ? nil : line(x963: x963, comment: label, namespaces)
  }

  private static func line(x963: Data, comment: String, _ namespaces: [String]) -> String {
    let key = openSSHPublicKey(x963: x963, comment: comment)
    return "owner namespaces=\"\(namespaces.joined(separator: ","))\" \(key)"
  }
}
