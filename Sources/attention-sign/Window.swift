import AppKit
import SSHSig
import SwiftUI

/// The window that shows the owner what they are about to sign.
///
/// It shows the order, expiry, pin and context as separate parts only when
/// `Statement.parse` accepts the text, which means the parts rebuild exactly the
/// signed bytes; otherwise it shows the exact signed text. The context is plain text, so nothing in it renders away.
struct SigningView: View {
  let text: String
  let parsed: Statement?
  /// A Board approval, shown as its exact text under its own heading.
  let approval: Approval?
  let finish: (Choice) -> Void
  @State private var requesting = false
  @State private var feedback = ""
  @FocusState private var editing: Bool

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 16) {
        heading
        if let parsed {
          parts(parsed)
        } else {
          if approval == nil {
            Text("This statement is not in the usual form, so the window shows its exact text.")
              .foregroundStyle(.secondary)
          }
          sectionTitle("Exact signed text", note: "these bytes are signed")
          plainBox(text).layoutPriority(1)
        }
        if requesting { feedbackBox }
      }
      .padding(20)
      Divider()
      footer
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
    .frame(width: windowWidth)
    .frame(minHeight: 560, idealHeight: 640)
    .animation(.easeInOut(duration: 0.2), value: requesting)
  }

  var heading: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(approval?.title ?? "Sign an order").font(.title2.weight(.semibold))
      if let parsed {
        HStack(spacing: 6) {
          Text("Expires \(longDate(parsed.expires))")
          Text("·").foregroundStyle(.tertiary)
          if parsed.pinned {
            Label("Pinned to every new agent session", systemImage: "pin.fill")
              .labelStyle(.titleAndIcon)
              .foregroundStyle(.tint)
          } else {
            Text("Not pinned")
          }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder func parts(_ parsed: Statement) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      sectionTitle("Order", note: "binding")
      GroupBox {
        ScrollView {
          Text(parsed.order)
            .font(.title3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
        .frame(maxHeight: 140)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    VStack(alignment: .leading, spacing: 6) {
      sectionTitle("Context", note: "non-binding · \(parsed.contextPath) · shown as plain text")
      plainBox(parsed.context)
    }
    .layoutPriority(1)
  }

  var feedbackBox: some View {
    VStack(alignment: .leading, spacing: 6) {
      sectionTitle("Request changes", note: "nothing will be signed")
      TextEditor(text: $feedback)
        .font(.body)
        .focused($editing)
        .scrollContentBackground(.hidden)
        .padding(6)
        .frame(height: 90)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topLeading) {
          if feedback.isEmpty {
            Text("What is wrong with the order? The agent reads exactly what you write here.")
              .foregroundStyle(.tertiary)
              .padding(.horizontal, 11)
              .padding(.vertical, 6)
              .allowsHitTesting(false)
          }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }
    .transition(.opacity.combined(with: .move(edge: .bottom)))
  }

  @ViewBuilder var footer: some View {
    HStack {
      if requesting {
        Spacer()
        Button("Don't send") { withAnimation { requesting = false } }
          .keyboardShortcut(.cancelAction)
        Button("Send to the agent") { finish(.changes(feedback)) }
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
          .disabled(feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      } else {
        Button {
          withAnimation { requesting = true }
          editing = true
        } label: {
          Label("Request changes…", systemImage: "text.bubble").labelStyle(.titleAndIcon)
        }
        .help("Don't sign, and tell the agent what is wrong with the order.")
        Spacer()
        Button("Cancel") { finish(.cancel) }.keyboardShortcut(.cancelAction)
        Button {
          finish(.sign)
        } label: {
          Label("Sign with Touch ID", systemImage: "touchid").labelStyle(.titleAndIcon)
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
      }
    }
  }

  func sectionTitle(_ title: String, note: String) -> some View {
    Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      + Text("  \(note)").font(.caption).foregroundStyle(.tertiary)
  }

  /// Text shown exactly as it is signed, in a quiet monospaced box.
  func plainBox(_ text: String) -> some View {
    ScrollView {
      Text(text)
        .font(.system(.callout, design: .monospaced))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
    }
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
  }
}

/// `2027-01-16` as `16 January 2027`, or the text unchanged when it is not such a date.
func longDate(_ iso: String) -> String {
  let parser = DateFormatter()
  parser.locale = Locale(identifier: "en_US_POSIX")
  parser.timeZone = TimeZone(identifier: "UTC")
  parser.dateFormat = "yyyy-MM-dd"
  guard let date = parser.date(from: iso) else { return iso }
  let printer = DateFormatter()
  printer.timeZone = parser.timeZone
  printer.dateStyle = .long
  return printer.string(from: date)
}

/// Wide enough that the plain-text boxes fit an 80-column line, as context files are wrapped,
/// with the box's padding, its scroller and the window's margins.
let windowWidth: CGFloat = {
  let size = NSFont.preferredFont(forTextStyle: .callout).pointSize
  let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
  let column = ("0" as NSString).size(withAttributes: [.font: font]).width
  return (column * 81 + 20 + 16 + 40).rounded(.up)
}()

/// Sends the standard editing shortcuts to the focused field. A helper with no
/// menu bar has no Edit menu, so without this ⌘A, ⌘C, ⌘V, ⌘X and ⌘Z do nothing.
func editingShortcuts(_ event: NSEvent) -> NSEvent? {
  let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
  let action: Selector
  switch (event.charactersIgnoringModifiers?.lowercased(), flags) {
  case ("a", .command): action = #selector(NSText.selectAll(_:))
  case ("c", .command): action = #selector(NSText.copy(_:))
  case ("v", .command): action = #selector(NSText.paste(_:))
  case ("x", .command): action = #selector(NSText.cut(_:))
  case ("z", .command): action = Selector(("undo:"))
  case ("z", [.command, .shift]): action = Selector(("redo:"))
  default: return event
  }
  let handled = MainActor.assumeIsolated { NSApp.sendAction(action, to: nil, from: nil) }
  return handled ? nil : event
}

/// What the owner chose in the window.
enum Choice {
  case sign
  case cancel
  /// Don't sign, and tell the agent this.
  case changes(String)
}

/// Cancels when the owner closes the window, as Cancel does.
@MainActor
final class Closer: NSObject, NSWindowDelegate {
  let close: () -> Void
  init(close: @escaping () -> Void) { self.close = close }
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    close()
    return false
  }
}

/// Shows the statement in a window and returns what the owner chose.
@MainActor
func choose(_ text: String, approval: Approval?) -> Choice {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let window = NSWindow(
    contentRect: .zero, styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
    backing: .buffered, defer: false)
  window.title = approval?.title ?? "Sign an order"
  window.titleVisibility = .hidden
  window.titlebarAppearsTransparent = true
  window.isMovableByWindowBackground = true
  window.standardWindowButton(.miniaturizeButton)?.isHidden = true
  window.standardWindowButton(.zoomButton)?.isHidden = true
  var choice = Choice.cancel
  // An approval is never parsed as an order.
  let parsed = approval == nil ? Statement.parse(text) : nil
  let view = SigningView(text: text, parsed: parsed, approval: approval) { chosen in
    choice = chosen
    app.stopModal()
  }
  let closer = Closer { app.stopModal() }
  window.delegate = closer
  window.contentView = NSHostingView(rootView: view)
  window.center()
  let shortcuts = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: editingShortcuts)
  // Start with no button focused, so Space does nothing until the owner chooses.
  RunLoop.main.perform(inModes: [.modalPanel]) {
    MainActor.assumeIsolated { _ = window.makeFirstResponder(nil) }
  }
  app.activate(ignoringOtherApps: true)
  app.runModal(for: window)
  shortcuts.map(NSEvent.removeMonitor)
  window.orderOut(nil)
  return choice
}
