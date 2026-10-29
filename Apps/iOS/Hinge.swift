// Whether an iPhone Duo is half folded, from UIKit's hinge (iOS 27.1). A
// phone with no hinge never reports one.
import SwiftUI
import UIKit

struct HingeReader: UIViewRepresentable {
  @Binding var halfOpen: Bool

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.isUserInteractionEnabled = false
    if #available(iOS 27.1, *) {
      let halfOpen = $halfOpen
      view.addInteraction(
        UIHingeInteraction { _, update in
          // UIKit calls this with the state at once, then on each change.
          let partly = update.hinge?.status == .partiallyOpen
          Task { @MainActor in halfOpen.wrappedValue = partly }
        })
    }
    return view
  }

  func updateUIView(_ view: UIView, context: Context) {}
}
