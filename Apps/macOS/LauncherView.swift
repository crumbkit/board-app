// The launcher panel's content: the field, the list on the left, the
// selected row's view on the right, and the footer.
import Launcher
import SwiftUI

struct LauncherView: View {
  let controller: LauncherController
  @FocusState private var fieldFocused: Bool

  var body: some View {
    let state = controller.state
    let screen = state.screen
    let selected = state.selected(in: screen)
    VStack(spacing: 0) {
      header(screen)
      Divider().overlay(Palette.separator)
      if let notice = screen.notice {
        Notice(text: notice)
        Divider().overlay(Palette.separator)
      }
      HStack(spacing: 0) {
        if controller.showsList {
          list(screen, selected: selected).frame(width: 320)
          Divider().overlay(Palette.separator)
        }
        DetailPane(row: selected, screen: screen, inFailureLevel: state.path.last.isFailure)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
      Divider().overlay(Palette.separator)
      Footer(provider: state.provider, hints: state.hints)
    }
    .background(Palette.background)
    .foregroundStyle(Palette.text)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .onChange(of: controller.opened, initial: true) { fieldFocused = true }
  }

  private func header(_ screen: Screen) -> some View {
    HStack(spacing: 8) {
      if screen.chip != nil {
        Button {
          controller.toggleSidebar()
        } label: {
          Image(systemName: "sidebar.left")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Palette.secondaryText)
        .help(controller.sidebarHidden ? "Show the list (⌃⌘S)" : "Hide the list (⌃⌘S)")
        .accessibilityLabel(controller.sidebarHidden ? "Show the list" : "Hide the list")
      }
      Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondaryText)
      if let chip = screen.chip {
        Text(chip)
          .font(.body.weight(.medium))
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(Palette.row, in: RoundedRectangle(cornerRadius: 6))
      }
      TextField(
        screen.placeholder,
        text: Binding(
          get: { controller.state.query }, set: { controller.state.query = $0 })
      )
      .textFieldStyle(.plain)
      .font(.title3)
      .focused($fieldFocused)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
  }

  private func list(_ screen: Screen, selected: Row?) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(screen.sections) { section in
            if !section.title.isEmpty {
              Text(section.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.secondaryText)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)
            }
            ForEach(section.rows) { row in
              RowView(row: row, selected: row.id == selected?.id)
                .id(row.id)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                  controller.state.selectedID = row.id
                  controller.activate(alternate: false)
                }
                .onTapGesture { controller.state.selectedID = row.id }
            }
          }
        }
        .padding(.vertical, 6)
      }
      .onChange(of: selected?.id) { _, id in
        if let id { proxy.scrollTo(id) }
      }
    }
  }
}

extension Optional where Wrapped == Level {
  fileprivate var isFailure: Bool {
    if case .failure = self { return true }
    return false
  }
}

private struct RowView: View {
  let row: Row
  let selected: Bool

  var body: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        if isPrimary {
          // The action a confirm step runs is the one primary action.
          Text(row.title)
            .font(.body.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: 5))
        } else {
          Text(row.title)
            .lineLimit(isNote ? 3 : 1)
            .foregroundStyle(isNote ? Palette.secondaryText : Palette.text)
        }
        if let subtitle = row.subtitle {
          Text(subtitle).font(.caption).foregroundStyle(Palette.secondaryText).lineLimit(1)
        }
      }
      Spacer(minLength: 4)
      if let status = row.status { StatusBadge(status: status, compact: true) }
      if selected, !isNote {
        Text("↩")
          .font(.caption.weight(.semibold))
          .foregroundStyle(Palette.onAccent)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(Palette.accent, in: RoundedRectangle(cornerRadius: 4))
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(selected ? Palette.row : .clear, in: RoundedRectangle(cornerRadius: 6))
    .padding(.horizontal, 6)
  }

  private var isNote: Bool {
    if case .note = row.kind { return true }
    return false
  }

  private var isPrimary: Bool {
    if case .confirm = row.kind { return true }
    return false
  }
}

/// A state as a symbol, a word and a colour. A failure is drawn on Alert.
struct StatusBadge: View {
  let status: Status
  var compact = false

  var body: some View {
    let label = Label(status.word, systemImage: symbol)
      .font(compact ? .caption : .callout)
      .labelStyle(.titleAndIcon)
    if status.tone == .failed {
      label
        .foregroundStyle(Palette.onAlert)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(Palette.alert, in: Capsule())
    } else {
      label.foregroundStyle(colour)
    }
  }

  private var symbol: String {
    switch status.tone {
    case .good: "checkmark.circle.fill"
    case .neutral: "circle"
    case .failed: "exclamationmark.triangle.fill"
    case .removed: "minus.circle"
    }
  }

  private var colour: Color {
    switch status.tone {
    case .good: Palette.verified
    case .neutral: Palette.secondaryText
    case .failed: Palette.onAlert
    case .removed: Palette.removed
    }
  }
}

private struct Notice: View {
  let text: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      StatusBadge(status: Status(tone: .failed, word: "Not loaded"), compact: true)
      Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
  }
}

private struct Footer: View {
  let provider: String?
  let hints: [Hint]

  var body: some View {
    HStack(spacing: 14) {
      Text(provider ?? "Board")
        .font(.caption.weight(.medium))
        .foregroundStyle(Palette.secondaryText)
      Spacer()
      ForEach(hints, id: \.self) { hint in
        HStack(spacing: 4) {
          Text(hint.key).font(.caption.monospaced())
          Text(hint.label).font(.caption).foregroundStyle(Palette.secondaryText)
        }
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 7)
  }
}
