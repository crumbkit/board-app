// The launcher's colours, by the names Board.app's palette uses. Each name
// maps to a macOS semantic or system colour, so dark mode and Increase
// Contrast come from the system. This file is the only place they appear.
import AppKit
import SwiftUI

/// Named apart from SwiftUI's own `.background` and `.separator` styles.
enum Palette {
  /// The panel's ground: the grouped background.
  static let background = Color(nsColor: .windowBackgroundColor)
  /// A raised surface: the selected row. In dark mode it is the grey macOS
  /// gives a selected row in a list without focus, which is lighter than the
  /// ground, so the selected row stands out.
  static let row = byAppearance(
    "Row", light: .controlBackgroundColor, dark: .unemphasizedSelectedContentBackgroundColor)
  static let text = Color(nsColor: .labelColor)
  /// Muted labels.
  static let secondaryText = Color(nsColor: .secondaryLabelColor)
  /// The selection marker, the primary action and links. It is the accent
  /// colour chosen in System Settings, and it changes when that choice does.
  static let accent = Color(nsColor: .controlAccentColor)
  /// Text and icons on Accent.
  static let onAccent = Color.white
  /// Failures.
  static let alert = Color(nsColor: .systemRed)
  /// Text and icons on Alert.
  static let onAlert = Color.white
  /// Passed and good states. The status badge draws its word and icon in
  /// this colour. System green is too light to read on a light ground, so
  /// light mode uses a darker green and dark mode keeps system green.
  static let verified = byAppearance("Verified", light: NSColor(rgb: 0x1D7A34), dark: .systemGreen)
  /// Deleted or removed things. The status badge draws its word and icon in
  /// this colour, so light mode uses a darker orange for the same reason and
  /// dark mode keeps system orange.
  static let removed = byAppearance("Removed", light: NSColor(rgb: 0xB25000), dark: .systemOrange)
  /// Rules between areas.
  static let separator = Color(nsColor: .separatorColor)

  /// A colour that is `light` in light mode and `dark` in dark mode.
  private static func byAppearance(_ name: String, light: NSColor, dark: NSColor) -> Color {
    Color(
      nsColor: NSColor(name: NSColor.Name(name)) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? dark : light
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
