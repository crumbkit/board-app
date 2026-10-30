// The launcher's colours, by the names Board.app's palette uses. Each has a
// light and a dark variant. The hex values are placeholders until the
// shared palette lands; this file is the only place they appear.
import AppKit
import SwiftUI

/// Named apart from SwiftUI's own `.background` and `.separator` styles.
enum Palette {
  /// The panel's ground.
  static let background = named("Background", light: 0xF6F2E9, dark: 0x0B1620)
  /// A raised surface: the selected row.
  static let row = named("Row", light: 0xEAE3D3, dark: 0x183343)
  static let text = named("Text", light: 0x183343, dark: 0xF6F2E9)
  /// Muted labels.
  static let secondaryText = named("SecondaryText", light: 0x4D6270, dark: 0xA9B6BF)
  /// A fill only, never a text or icon colour: the selection marker and
  /// the primary action.
  static let accent = named("Accent", light: 0x7A5309, dark: 0xE5B653)
  /// Text and icons on Accent.
  static let onAccent = named("OnAccent", light: 0xF6F2E9, dark: 0x0B1620)
  /// Failures.
  static let alert = named("Alert", light: 0xA33D16, dark: 0xD9653B)
  /// Text and icons on Alert.
  static let onAlert = named("OnAlert", light: 0xF6F2E9, dark: 0x0B1620)
  /// Passed and good states.
  static let verified = named("Verified", light: 0x3F6E2E, dark: 0xB8CA9A)
  /// Deleted or removed things.
  static let removed = named("Removed", light: 0x6E7F8A, dark: 0x8E9BA4)
  /// Rules between areas.
  static let separator = named("Separator", light: 0xD9D1C0, dark: 0x2B4152)

  private static func named(_ name: String, light: UInt32, dark: UInt32) -> Color {
    Color(
      nsColor: NSColor(name: NSColor.Name(name)) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor(rgb: isDark ? dark : light)
      })
  }
}

extension NSColor {
  fileprivate convenience init(rgb: UInt32) {
    self.init(
      srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
      blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
  }
}
