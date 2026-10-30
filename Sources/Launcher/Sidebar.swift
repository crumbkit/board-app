// Whether the list beside an item's parts is hidden: one Bool in the user
// defaults, so the next open shows the list the same way.
import Foundation

extension UserDefaults {
  /// False until the owner first hides the list.
  public var launcherSidebarHidden: Bool {
    get { bool(forKey: "launcherSidebarHidden") }
    set { set(newValue, forKey: "launcherSidebarHidden") }
  }
}
