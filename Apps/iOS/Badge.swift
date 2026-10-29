// The plugin's badge beside a request: a coloured square with a symbol.
import SwiftUI

struct Badge: View {
  let plugin: String
  var size: CGFloat = 28

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size * 0.5, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(color, in: .rect(cornerRadius: size * 0.29))
  }

  private var symbol: String {
    switch plugin {
    case "tasks": "checkmark.circle"
    case "controls": "shield"
    case "review": "bubble.left"
    default: "puzzlepiece.extension"
    }
  }

  private var color: Color {
    switch plugin {
    case "tasks": Color(red: 0.16, green: 0.44, blue: 0.94)
    case "controls": Color(red: 0.88, green: 0.48, blue: 0.04)
    case "review": Color(red: 0.55, green: 0.36, blue: 0.96)
    default: .gray
    }
  }
}
