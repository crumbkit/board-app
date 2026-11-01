import AppKit
import SwiftUI
import os

@main
struct BoardApp: App {
  /// The relay, the launcher and its shortcut.
  @NSApplicationDelegateAdaptor(BoardAppDelegate.self) private var app

  var body: some Scene {
    Window("Board", id: BoardWindow.id) {
      BoardWindow(relay: app.relay, openLauncher: app.openLauncher)
    }
    .defaultSize(width: 900, height: 600)
    MenuBarExtra("Board", systemImage: "square.grid.2x2") {
      BoardMenu(toggleLauncher: app.toggleLauncher)
    }
  }
}

/// The menu bar item's menu.
struct BoardMenu: View {
  let toggleLauncher: () -> Void
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Open Launcher", action: toggleLauncher)
      .keyboardShortcut(.space, modifiers: [.control, .option])
    Button("Open Board Window") {
      NSApp.activate()
      openWindow(id: BoardWindow.id)
    }
  }
}

/// Starts the relay, the launcher and its shortcut when the app starts.
/// They run until the app quits, so closing the window stops none of them.
@MainActor
final class BoardAppDelegate: NSObject, NSApplicationDelegate {
  let relay = RequestRelay()
  private var panel: PanelController?
  private var hotKey: HotKey?

  func applicationDidFinishLaunching(_ notification: Notification) {
    Task { await relay.run() }
    let panel = PanelController()
    self.panel = panel
    hotKey = HotKey { [weak panel] in panel?.toggle() }
    if hotKey == nil {
      Logger(subsystem: "com.stemmacorp.board", category: "launcher").error(
        "⌃⌥Space is taken by another app; open the launcher from the menu bar")
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func openLauncher() { panel?.show() }

  func toggleLauncher() { panel?.toggle() }
}
