import SwiftUI

@main
struct BoardApp: App {
  var body: some Scene {
    Window("Board", id: "pairing") {
      PairingSheet().frame(width: 560)
    }
    .windowResizability(.contentSize)
  }
}
