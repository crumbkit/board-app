import Foundation

/// A directive statement split into the parts the signing window shows.
///
/// `parse` returns nil unless putting the parts back together gives exactly the
/// bytes that will be signed, and unless the context marker appears only once.
/// Without the second rule, a directive could carry a fake context heading and
/// hide binding text in the context box.
public struct Statement: Equatable, Sendable {
  public let expires: String
  public let pinned: Bool
  public let directive: String
  public let contextPath: String
  public let context: String

  public init(
    expires: String, pinned: Bool, directive: String, contextPath: String, context: String
  ) {
    self.expires = expires
    self.pinned = pinned
    self.directive = directive
    self.contextPath = contextPath
    self.context = context
  }

  static let contextMarker = "\n\nContext (non-binding, from "

  public static func parse(_ text: String) -> Statement? {
    let header = "attention/directive/v1\nexpires: "
    guard text.hasPrefix(header), text.components(separatedBy: contextMarker).count == 2 else {
      return nil
    }
    let lines = text.dropFirst(header.count)
    guard let expiresEnd = lines.firstIndex(of: "\n") else { return nil }
    let expires = String(lines[..<expiresEnd])
    var rest = lines[lines.index(after: expiresEnd)...]
    let pinned: Bool
    if rest.hasPrefix("pinned: yes\n\n") {
      pinned = true
    } else if rest.hasPrefix("pinned: no\n\n") {
      pinned = false
    } else {
      return nil
    }
    rest = rest.drop(while: { $0 != "\n" }).dropFirst(2)
    let directiveLabel = "Directive (binding):\n"
    guard rest.hasPrefix(directiveLabel), let marker = rest.range(of: contextMarker) else {
      return nil
    }
    let directive = String(
      rest[rest.index(rest.startIndex, offsetBy: directiveLabel.count)..<marker.lowerBound])
    let afterMarker = rest[marker.upperBound...]
    guard let pathEnd = afterMarker.range(of: "):\n") else { return nil }
    let contextPath = String(afterMarker[..<pathEnd.lowerBound])
    let parsed = Statement(
      expires: expires, pinned: pinned, directive: directive, contextPath: contextPath,
      context: String(afterMarker[pathEnd.upperBound...]))
    guard !expires.contains("\n"), !contextPath.contains("\n"), parsed.text == text else {
      return nil
    }
    return parsed
  }

  /// The statement these parts make, in the form `board_attention.directive.statement` writes.
  public var text: String {
    "attention/directive/v1\nexpires: \(expires)\npinned: \(pinned ? "yes" : "no")\n\n"
      + "Directive (binding):\n\(directive)\(Statement.contextMarker)\(contextPath)):\n\(context)"
  }
}
