// The request screens' colours: stock iOS, as the signed-off chat design
// draws them in light mode. Dark mode uses the matching system colours.
import SwiftUI
import UIKit

enum Palette {
  /// The screen's ground, #F2F2F7.
  static let ground = color(0xF2F2F7, dark: .systemGroupedBackground)
  /// Cards and rows, white.
  static let row = color(0xFFFFFF, dark: .secondarySystemGroupedBackground)
  /// Actions and the owner's replies, #007AFF.
  static let action = color(0x007AFF, dark: .systemBlue)
  /// Secondary text, #6C6C70.
  static let secondary = color(0x6C6C70, dark: .secondaryLabel)
  /// Body text, #1C1C1E.
  static let text = color(0x1C1C1E, dark: .label)

  private static func color(_ hex: UInt32, dark: UIColor) -> Color {
    let light = UIColor(
      red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    return Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
  }
}
