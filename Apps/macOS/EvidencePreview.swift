// The evidence preview window: one evidence file rendered, the name search
// over it, and the metadata comparison at its foot. Space on an evidence
// row opens it; Space or Esc closes it.
import AppKit
import Launcher
import Quartz
import SwiftUI

/// Opens an evidence file in its default app, unless opening it would run
/// it. Then it is shown in Finder instead.
@MainActor
func openEvidence(_ path: String) {
  let url = URL(fileURLWithPath: path)
  switch EvidenceFiles.opening(path) {
  case .open: NSWorkspace.shared.open(url)
  case .reveal: NSWorkspace.shared.activateFileViewerSelecting([url])
  case .missing: break
  }
}

/// A file's content, read once when the window shows it.
enum FileContent {
  case markdown([MarkdownBlock])
  case text(String)
  case image(NSImage)
  case quickLook(URL)
  case unreadable(String)

  /// Reads only a regular file, and only its first megabyte.
  static func load(_ file: EvidenceFile) -> FileContent {
    let path = file.evidence.path
    switch file.previewKind {
    case .markdown:
      guard let data = EvidenceFiles.read(path) else { return .unreadable(path) }
      return .markdown(MarkdownBlock.parse(String(decoding: data, as: UTF8.self)))
    case .text:
      guard let data = EvidenceFiles.read(path) else { return .unreadable(path) }
      return .text(String(decoding: data, as: UTF8.self))
    case .image:
      guard let data = EvidenceFiles.read(path, limit: 50_000_000), let image = NSImage(data: data)
      else { return .unreadable(path) }
      return .image(image)
    case .other:
      return EvidenceFiles.isRegular(path)
        ? .quickLook(URL(fileURLWithPath: path)) : .unreadable(path)
    }
  }
}

@MainActor
@Observable
final class EvidenceModel {
  var browser: EvidenceBrowser? {
    didSet {
      if let current = browser?.current, current != oldValue?.current {
        content = FileContent.load(current)
      }
    }
  }
  private(set) var content = FileContent.unreadable("")
}

/// A titled, resizable panel that takes the keyboard without activating
/// the app, like the launcher.
private final class PreviewPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

@MainActor
final class EvidencePreviewController: NSObject, NSWindowDelegate {
  /// Called after the window closes, so the launcher takes focus back.
  var closed: () -> Void = {}
  /// Called when the window loses focus.
  var lostFocus: () -> Void = {}

  private let model = EvidenceModel()
  private var panel: PreviewPanel?

  var isKey: Bool { panel?.isKeyWindow == true }

  func show(_ browser: EvidenceBrowser) {
    model.browser = browser
    let panel = self.panel ?? makePanel()
    self.panel = panel
    updateTitle()
    panel.makeKeyAndOrderFront(nil)
  }

  func close() {
    guard let panel, panel.isVisible else { return }
    panel.orderOut(nil)
    closed()
  }

  private func makePanel() -> PreviewPanel {
    let panel = PreviewPanel(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
      styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
      backing: .buffered, defer: false)
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.minSize = NSSize(width: 480, height: 360)
    panel.delegate = self
    panel.contentView = NSHostingView(rootView: EvidenceWindowView(model: model))
    let accessory = NSTitlebarAccessoryViewController()
    accessory.layoutAttribute = .trailing
    accessory.view = NSHostingView(
      rootView: TitleControls(model: model, move: { [weak self] in self?.move($0) }))
    accessory.view.frame.size = NSSize(width: 150, height: 28)
    panel.addTitlebarAccessoryViewController(accessory)
    panel.center()
    // Keeps the size and position between invocations.
    panel.setFrameAutosaveName("EvidencePreview")
    return panel
  }

  private func updateTitle() {
    panel?.title = model.browser?.current.name ?? ""
  }

  private func move(_ delta: Int) {
    model.browser?.move(delta)
    updateTitle()
  }

  func windowWillClose(_ notification: Notification) {
    closed()
  }

  func windowDidResignKey(_ notification: Notification) {
    lostFocus()
  }

  /// ← → move, Enter opens the file, Space or Esc closes, and / searches.
  /// In the search, ↑ ↓ choose, Enter shows the choice and Esc returns.
  func handles(_ event: NSEvent) -> Bool {
    guard let panel, event.window === panel, var browser = model.browser else { return false }
    defer { updateTitle() }
    if browser.searching {
      switch Int(event.keyCode) {
      case 125: browser.moveSearch(1)
      case 126: browser.moveSearch(-1)
      case 36, 76: browser.closeSearch(choosing: true)
      case 53: browser.closeSearch(choosing: false)
      default: return false
      }
      model.browser = browser
      return true
    }
    switch Int(event.keyCode) {
    case 123: browser.move(-1)
    case 124: browser.move(1)
    case 36, 76:
      openEvidence(browser.current.evidence.path)
      return true
    case 49, 53:
      close()
      return true
    default:
      guard event.charactersIgnoringModifiers == "/" else { return false }
      browser.openSearch()
    }
    model.browser = browser
    return true
  }
}

// MARK: Views

private struct TitleControls: View {
  let model: EvidenceModel
  let move: (Int) -> Void

  var body: some View {
    HStack(spacing: 6) {
      if let browser = model.browser {
        Text(browser.position).font(.callout.monospacedDigit()).foregroundStyle(
          Palette.secondaryText)
        Button {
          move(-1)
        } label: {
          Image(systemName: "chevron.left")
        }
        .disabled(!browser.hasPrevious)
        .accessibilityLabel("Previous file")
        Button {
          move(1)
        } label: {
          Image(systemName: "chevron.right")
        }
        .disabled(!browser.hasNext)
        .accessibilityLabel("Next file")
      }
    }
    .buttonStyle(.borderless)
    .padding(.trailing, 8)
  }
}

private struct EvidenceWindowView: View {
  let model: EvidenceModel

  var body: some View {
    if let browser = model.browser {
      VStack(spacing: 0) {
        FileView(content: model.content)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .overlay(alignment: .top) {
            if browser.searching { SearchPanel(model: model) }
          }
        Divider().overlay(Palette.separator)
        ComparisonView(browser: browser)
      }
      .background(Palette.background)
      .foregroundStyle(Palette.text)
    }
  }
}

/// The file rendered by its kind: Markdown, an image, text in SF Mono, or
/// Quick Look for the rest.
private struct FileView: View {
  let content: FileContent

  var body: some View {
    switch content {
    case .markdown(let blocks):
      ScrollView {
        MarkdownView(blocks: blocks)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(20)
      }
    case .image(let image):
      Image(nsImage: image).resizable().scaledToFit().padding(12)
    case .text(let text):
      ScrollView([.vertical, .horizontal]) {
        Text(verbatim: text)
          .font(.body.monospaced())
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(16)
      }
    case .quickLook(let url):
      QuickLook(url: url)
    case .unreadable(let path):
      Unreadable(path: path)
    }
  }
}

/// Markdown drawn block by block, with inline syntax rendered in each.
private struct MarkdownView: View {
  let blocks: [MarkdownBlock]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
        blockView(block)
      }
    }
    // A link in the file opens only when it is http or https.
    .environment(
      \.openURL,
      OpenURLAction { url in Address.isWeb(url) ? .systemAction : .discarded })
  }

  @ViewBuilder private func blockView(_ block: MarkdownBlock) -> some View {
    switch block {
    case .heading(let level, let text):
      Text(inline(text)).font(level == 1 ? .title : level == 2 ? .title2 : .title3)
        .fontWeight(.semibold)
    case .paragraph(let text): Text(inline(text))
    case .bullet(let text):
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text("•")
        Text(inline(text))
      }
    case .numbered(let marker, let text):
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(marker).monospacedDigit()
        Text(inline(text))
      }
    case .quote(let text):
      Text(inline(text)).foregroundStyle(Palette.secondaryText).padding(.leading, 10)
        .overlay(alignment: .leading) { Rectangle().fill(Palette.separator).frame(width: 3) }
    case .code(let text):
      Text(verbatim: text).font(.body.monospaced())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Palette.row, in: RoundedRectangle(cornerRadius: 6))
    case .rule: Divider().overlay(Palette.separator)
    }
  }

  private func inline(_ text: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
  }
}

private struct Unreadable: View {
  let path: String

  var body: some View {
    VStack(spacing: 8) {
      StatusBadge(status: Status(tone: .failed, word: "Unreadable"))
      Text(path).font(.callout.monospaced()).foregroundStyle(Palette.secondaryText)
    }
  }
}

private struct QuickLook: NSViewRepresentable {
  let url: URL

  func makeNSView(context: Context) -> QLPreviewView {
    let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
    view.previewItem = url as NSURL
    return view
  }

  func updateNSView(_ view: QLPreviewView, context: Context) {
    if (view.previewItem as? NSURL) as URL? != url { view.previewItem = url as NSURL }
  }
}

/// Filters the item's evidence files by name, with each file's kind, size
/// and date.
private struct SearchPanel: View {
  let model: EvidenceModel
  @FocusState private var focused: Bool

  var body: some View {
    if let browser = model.browser {
      VStack(alignment: .leading, spacing: 0) {
        TextField(
          "Search evidence",
          text: Binding(
            get: { model.browser?.query ?? "" }, set: { model.browser?.query = $0 })
        )
        .textFieldStyle(.plain)
        .font(.title3)
        .focused($focused)
        .padding(12)
        Divider().overlay(Palette.separator)
        let matches = browser.matches
        if matches.isEmpty {
          Text("No file matches.").foregroundStyle(Palette.secondaryText).padding(12)
        }
        ForEach(Array(matches.enumerated()), id: \.element.id) { index, file in
          HStack {
            Text(file.name).lineLimit(1)
            Spacer()
            Text(file.evidence.kind).foregroundStyle(Palette.secondaryText)
            Text(EvidenceBrowser.size(file.evidence.size)).foregroundStyle(Palette.secondaryText)
            Text(EvidenceBrowser.date(file.evidence.added)).foregroundStyle(Palette.secondaryText)
          }
          .font(.callout)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(index == browser.searchIndex ? Palette.row : .clear)
        }
      }
      .frame(maxWidth: 520)
      .background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.separator))
      .padding(.top, 40)
      .onAppear { focused = true }
    }
  }
}

/// Kind, size, added, task record and short SHA-256 for the previous,
/// current and next file, with the current one on the raised surface.
private struct ComparisonView: View {
  let browser: EvidenceBrowser

  var body: some View {
    let rows = browser.comparison
    Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
      GridRow {
        Text("")
        heading("Previous")
        heading("This file").background(Palette.row)
        heading("Next")
      }
      ForEach(rows, id: \.label) { row in
        GridRow {
          cell(row.label).foregroundStyle(Palette.secondaryText)
          cell(row.previous ?? "—", mono: row.label == "SHA-256")
          cell(row.current, mono: row.label == "SHA-256").background(Palette.row)
          cell(row.next ?? "—", mono: row.label == "SHA-256")
        }
      }
    }
    .font(.callout)
    .padding(12)
  }

  private func heading(_ text: String) -> some View {
    cell(text).font(.caption.weight(.semibold)).foregroundStyle(Palette.secondaryText)
  }

  private func cell(_ text: String, mono: Bool = false) -> some View {
    Text(text)
      .font(mono ? .callout.monospaced() : .callout)
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
  }
}
