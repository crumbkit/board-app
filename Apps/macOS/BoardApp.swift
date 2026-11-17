import AppKit
import SwiftUI
import os

@main
struct BoardApp: App {
  /// The relay, the launcher and its shortcut.
  @NSApplicationDelegateAdaptor(BoardAppDelegate.self) private var app

  var body: some Scene {
    Window("Board", id: BoardWindow.id) {
      BoardWindow(relay: app.relay, openLauncher: app.openLauncher, install: app.install)
    }
    .defaultSize(width: 900, height: 600)
    MenuBarExtra {
      BoardMenu(toggleLauncher: app.toggleLauncher, install: app.install)
    } label: {
      MenuBarIcon(install: app.install)
    }
  }
}

/// The menu bar item's menu. While the release the app carries is not
/// installed, it offers it again.
struct BoardMenu: View {
  let toggleLauncher: () -> Void
  let install: InstallModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Open Launcher", action: toggleLauncher)
      .keyboardShortcut(.space, modifiers: [.control, .option])
    Button("Open Board Window") {
      NSApp.activate()
      openWindow(id: BoardWindow.id)
    }
    if let offer = install.offer, let carried = install.carried {
      Divider()
      Button(offer == .install ? "Install Board…" : "Update Board…") {
        install.show()
        NSApp.activate()
        openWindow(id: BoardWindow.id)
      }
      .badge(Text(carried.board.abbreviated(8)))
    }
  }
}

/// The menu bar icon, with a dot in the accent colour while the release the
/// app carries is not installed. It opens the Board window at launch when
/// the install sheet is up, since the sheet shows on that window.
struct MenuBarIcon: View {
  let install: InstallModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Image(nsImage: install.offer == nil ? Self.plain : Self.dotted)
      .task(id: install.sheetShown) {
        if install.sheetShown { openWindow(id: BoardWindow.id) }
      }
  }

  private static let plain: NSImage = {
    let image =
      NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Board")
      ?? NSImage()
    image.isTemplate = true
    return image
  }()

  /// Drawn when shown, so the symbol takes the menu bar's text colour and
  /// the dot the accent colour of the moment.
  private static let dotted: NSImage = {
    let size = NSSize(width: 18, height: 16)
    let image = NSImage(size: size, flipped: false) { rect in
      let symbol =
        plain.withSymbolConfiguration(
          .init(paletteColors: [.labelColor])) ?? plain
      let side = symbol.size
      symbol.draw(
        in: NSRect(
          x: (rect.width - side.width) / 2, y: (rect.height - side.height) / 2,
          width: side.width, height: side.height))
      NSColor.controlAccentColor.setFill()
      NSBezierPath(ovalIn: NSRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 6, height: 6)).fill()
      return true
    }
    image.accessibilityDescription = "Board, with a release to install"
    return image
  }()
}

/// Starts the relay, the launcher and its shortcut when the app starts.
/// They run until the app quits, so closing the window stops none of them.
@MainActor
final class BoardAppDelegate: NSObject, NSApplicationDelegate {
  let relay = RequestRelay()
  /// Reads the installed release when the app starts, so the sheet and the
  /// menu bar dot are right from the first frame.
  let install = InstallModel()
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

  /// An install still running is stopped, with everything it started,
  /// before the app quits. The sheet offers it again on the next launch.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard install.running else { return .terminateNow }
    Task {
      await install.stop()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  func openLauncher() { panel?.show() }

  func toggleLauncher() { panel?.toggle() }
}
