import SwiftUI

@main
struct BoardApp: App {
  /// Shares pending effects with a paired phone while the app runs.
  private let relay = RequestRelay()

  var body: some Scene {
    Window("Board", id: "pairing") {
      PairingSheet().frame(width: 560)
        .task { await relay.run() }
    }
    .windowResizability(.contentSize)
  }
}
