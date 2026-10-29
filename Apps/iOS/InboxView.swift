// The inbox: the requests plugins asked the owner to answer, newest first.
// It follows the signed-off Inbox design: a compact list with the board
// switcher in its title, a regular layout with a boards sidebar, and a
// tabletop layout with the boards as buttons on the lower half.
import Requests
import SwiftUI

struct InboxView: View {
  @State var requests: PhoneRequests
  /// The board the list is narrowed to, or nil for every board.
  @State private var board: String?
  @State private var choosingBoard = false
  @State private var halfOpen = false
  @Environment(\.horizontalSizeClass) private var sizeClass

  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        let portrait = geometry.size.height > geometry.size.width
        if sizeClass == .regular && halfOpen && portrait {
          tabletop(geometry)
        } else if sizeClass == .regular {
          regular(sidebarWidth: portrait ? geometry.size.width * 0.35 : geometry.size.width / 2)
        } else {
          compact
        }
      }
      .toolbar(.hidden, for: .navigationBar)
      .onChange(of: requests.inbox.boards.map(\.name)) { _, names in
        // A board leaves the list once nothing waits in it.
        if let board, !names.contains(board) { self.board = nil }
      }
    }
    .background(HingeReader(halfOpen: $halfOpen))
    .task { await requests.watch() }
  }

  private var title: String { board ?? "All boards" }
  private var shown: [Request] { requests.inbox.requests(in: board) }

  // MARK: Layouts

  private var compact: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Button {
          choosingBoard = true
        } label: {
          HStack(spacing: 4) {
            Text(title).font(.title.bold()).foregroundStyle(.primary)
            Image(systemName: "chevron.down").font(.headline)
          }
        }
        header
      }
      .padding(.horizontal, 16)
    }
    .defaultScrollAnchor(.top)
    .overlay { if shown.isEmpty { empty } }
    .sheet(isPresented: $choosingBoard) {
      BoardsSheet(inbox: requests.inbox, board: $board).presentationDetents([.medium])
    }
  }

  private func regular(sidebarWidth: CGFloat) -> some View {
    HStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          sidebarHeading
          boardItem(nil, "All boards", requests.inbox.requests.count)
          ForEach(requests.inbox.boards, id: \.name) { boardItem($0.name, $0.name, $0.count) }
        }
        .padding(10)
      }
      .frame(width: sidebarWidth)
      .background(Color(.secondarySystemBackground))
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Text(title).font(.title2.bold())
          header
        }
        .padding(.horizontal, 16)
      }
      .overlay { if shown.isEmpty { empty } }
    }
  }

  /// The list above the fold and the boards below it. The fold is the
  /// middle of the whole screen, not of the safe area, whose top and bottom
  /// insets differ.
  private func tabletop(_ geometry: GeometryProxy) -> some View {
    let insets = geometry.safeAreaInsets
    let fold = (geometry.size.height + insets.top + insets.bottom) / 2 - insets.top
    return VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Text(title).font(.title3.bold())
          header
        }
        .padding(.horizontal, 14)
      }
      .frame(height: fold)
      .overlay { if shown.isEmpty { empty } }
      VStack(alignment: .leading, spacing: 8) {
        sidebarHeading
        boardButton(nil, "All boards", requests.inbox.requests.count)
        ForEach(requests.inbox.boards, id: \.name) { boardButton($0.name, $0.name, $0.count) }
        Spacer(minLength: 0)
      }
      .padding(16)
      .frame(height: geometry.size.height - fold)
    }
  }

  // MARK: Parts

  /// The count, the out-of-date banner and the rows. It redraws every 30
  /// seconds, so the banner appears even when no read succeeds, and a row's
  /// "Yesterday" moves on at midnight.
  private var header: some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      VStack(alignment: .leading, spacing: 0) {
        if !shown.isEmpty {
          Text("\(shown.count) waiting").font(.subheadline).foregroundStyle(.secondary)
            .padding(.bottom, 8)
        }
        if requests.isOutOfDate(now: context.date), let shared = requests.shared {
          OutOfDate(shared: shared)
        }
        ForEach(shown) { request in
          RequestRow(request: request, now: context.date)
          if request.id != shown.last?.id { Divider() }
        }
      }
    }
  }

  private var empty: some View {
    VStack(spacing: 6) {
      Image(systemName: "tray").font(.system(size: 40)).foregroundStyle(.tertiary)
      Text("Nothing waiting").font(.headline)
      Text("When a plugin asks before it acts, the request appears here.")
        .foregroundStyle(.secondary)
    }
    .multilineTextAlignment(.center)
    .padding(20)
  }

  private var sidebarHeading: some View {
    Text("Boards").font(.caption.weight(.semibold)).textCase(.uppercase)
      .foregroundStyle(.secondary).padding(.horizontal, 9).padding(.vertical, 4)
  }

  private func boardItem(_ name: String?, _ label: String, _ count: Int) -> some View {
    let on = board == name
    return Button {
      board = name
    } label: {
      HStack {
        Text(label).lineLimit(1).truncationMode(.tail)
        Spacer(minLength: 6)
        Text("\(count)").font(.footnote).foregroundStyle(on ? .white : .secondary)
      }
      .fontWeight(on ? .semibold : .regular)
      .foregroundStyle(on ? .white : .primary)
      .padding(.horizontal, 9)
      .padding(.vertical, 7)
      .background(on ? Color.accentColor : .clear, in: .rect(cornerRadius: 9))
    }
    .buttonStyle(.plain)
  }

  private func boardButton(_ name: String?, _ label: String, _ count: Int) -> some View {
    let on = board == name
    return Button {
      board = name
    } label: {
      HStack {
        Text(label).lineLimit(1)
        Spacer()
        Text("\(count)").foregroundStyle(on ? .white : .secondary)
      }
      .fontWeight(.semibold)
      .frame(maxWidth: .infinity)
      .padding(12)
      .foregroundStyle(on ? .white : .primary)
      .background(
        on ? Color.accentColor : Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }
    .buttonStyle(.plain)
  }
}

struct RequestRow: View {
  let request: Request
  var now = Date()

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Badge(plugin: request.plugin)
      VStack(alignment: .leading, spacing: 1) {
        Text(request.name).font(.subheadline.weight(.semibold)).lineLimit(2)
        Text(request.sentence).font(.footnote).foregroundStyle(.secondary)
        Text("\(request.boardName) · \(askedLabel(request.asked, now: now))")
          .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 10)
    .contentShape(.rect)
  }
}

/// The phone cannot reach new requests, so the list says how old it is.
struct OutOfDate: View {
  let shared: Date

  var body: some View {
    Label {
      Text(
        "This list may be out of date. Your Mac last shared requests at \(shared.formatted(date: Calendar.current.isDateInToday(shared) ? .omitted : .abbreviated, time: .shortened)). Open Board on the Mac, or check that it is awake."
      )
    } icon: {
      Image(systemName: "clock")
    }
    .font(.footnote)
    .foregroundStyle(Color.orange)
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.orange.opacity(0.12), in: .rect(cornerRadius: 10))
    .padding(.vertical, 8)
  }
}

/// The board switcher the compact title opens.
struct BoardsSheet: View {
  let inbox: Inbox
  @Binding var board: String?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Boards").font(.headline).padding(.bottom, 6)
      row(nil, "All boards", inbox.requests.count)
      ForEach(inbox.boards, id: \.name) { row($0.name, $0.name, $0.count) }
      Text(
        "Boards are named by their git remote. A board appears here while it has requests waiting."
      )
      .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
      Spacer(minLength: 0)
    }
    .padding(16)
  }

  private func row(_ name: String?, _ label: String, _ count: Int) -> some View {
    Button {
      board = name
      dismiss()
    } label: {
      HStack {
        Text(label).fontWeight(name == nil ? .semibold : .regular)
        Spacer()
        Text("\(count)").foregroundStyle(.secondary)
        if board == name { Image(systemName: "checkmark").foregroundStyle(.tint) }
      }
      .padding(.vertical, 10)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .overlay(alignment: .bottom) { Divider() }
  }
}

#Preview("Inbox") { InboxView(requests: PhoneRequests(preview: PreviewRequests.all)) }
#Preview("Empty") { InboxView(requests: PhoneRequests(preview: [])) }
#Preview("Out of date") {
  InboxView(
    requests: PhoneRequests(
      preview: PreviewRequests.all, shared: Date().addingTimeInterval(-3600)))
}
