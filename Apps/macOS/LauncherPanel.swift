// The launcher's floating panel, and the keys the panel handles before its
// field sees them. The app delegate adds the menu bar item and the shortcut
// that open it.
import AppKit
import Launcher
import SwiftUI
import os

/// A borderless panel that takes the keyboard without activating the app,
/// so closing it leaves the previous app frontmost.
final class LauncherPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

/// Opens, places and closes the launcher panel, and routes the keys it
/// handles before the text field sees them.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
  static let size = NSSize(width: 760, height: 480)

  let launcher = LauncherController()
  private let panel: LauncherPanel
  private let preview = EvidencePreviewController()
  private var keyMonitor: Any?
  /// When the panel last closed because it lost focus. Clicking the menu
  /// bar item takes focus first, so a click just after must not reopen it.
  private var resignedAt = Date.distantPast

  override init() {
    panel = LauncherPanel(
      contentRect: NSRect(origin: .zero, size: Self.size),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    super.init()
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.delegate = self
    let host = NSHostingView(rootView: LauncherView(controller: launcher))
    host.frame = NSRect(origin: .zero, size: Self.size)
    host.autoresizingMask = [.width, .height]
    panel.contentView = host

    launcher.close = { [weak self] in self?.hide() }
    launcher.showPreview = { [weak self] in self?.preview.show($0) }
    preview.closed = { [weak self] in
      guard let self, panel.isVisible else { return }
      panel.makeKeyAndOrderFront(nil)
    }
    preview.lostFocus = { [weak self] in self?.closeIfUnfocused() }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let handled = MainActor.assumeIsolated { self?.handles(event) ?? false }
      return handled ? nil : event
    }
  }

  func toggle() {
    if panel.isVisible {
      hide()
    } else if Date().timeIntervalSince(resignedAt) > 0.3 {
      show()
    }
  }

  /// Opens at the top level, centred in the upper third of the screen with
  /// the mouse.
  func show() {
    launcher.opening()
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    if let frame = screen?.visibleFrame {
      let top = frame.maxY - frame.height / 6
      panel.setFrameOrigin(
        NSPoint(
          x: frame.midX - Self.size.width / 2, y: max(frame.minY, top - Self.size.height)))
    }
    panel.makeKeyAndOrderFront(nil)
  }

  func hide() {
    panel.orderOut(nil)
    preview.close()
  }

  func windowDidResignKey(_ notification: Notification) {
    closeIfUnfocused()
  }

  /// Closes the launcher when neither it nor its preview window has focus.
  /// The check waits a turn, since the window taking focus is not key yet.
  private func closeIfUnfocused() {
    DispatchQueue.main.async { [self] in
      guard panel.isVisible, !panel.isKeyWindow, !preview.isKey else { return }
      resignedAt = Date()
      hide()
    }
  }

  /// Arrows move the selection, Enter acts, Esc goes back or closes,
  /// Backspace in an empty field goes back, Space previews evidence and
  /// ⌃⌘S shows or hides the list below the top level. Other keys reach the
  /// field.
  private func handles(_ event: NSEvent) -> Bool {
    if preview.handles(event) { return true }
    guard event.window === panel else { return false }
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if modifiers == [.control, .command], event.charactersIgnoringModifiers?.lowercased() == "s" {
      launcher.toggleSidebar()
      return true
    }
    switch Int(event.keyCode) {
    case 125: launcher.move(1)
    case 126: launcher.move(-1)
    case 36, 76: launcher.activate(alternate: event.modifierFlags.contains(.command))
    case 53: launcher.escape()
    case 51: return launcher.backspace()
    case 49: return launcher.space()
    default: return false
    }
    return true
  }
}
