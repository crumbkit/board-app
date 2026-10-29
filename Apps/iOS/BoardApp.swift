import SwiftUI

/// The UserDefaults key set once the Mac has granted this phone a scope.
let pairedKey = "paired"

@main
struct BoardApp: App {
  /// Read once at launch, so "You're set" stays on screen after pairing and
  /// the inbox opens the next time Board opens.
  private let paired = UserDefaults.standard.bool(forKey: pairedKey)

  var body: some Scene {
    WindowGroup {
      if paired {
        InboxView(requests: PhoneRequests())
      } else {
        PairingView()
      }
    }
  }
}
