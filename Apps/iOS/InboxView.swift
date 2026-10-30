// The inbox: the requests plugins asked the owner to answer, newest first.
// It follows the signed-off Inbox v2 design: a NavigationSplitView with a
// Boards list and the requests of the chosen board, laid out as Mail lays out
// mailboxes and messages. The tabletop pose puts the Boards list on the lower
// half.
import Requests
import SwiftUI

/// The boards the inbox can show: every board, or one by its git remote.
enum BoardChoice: Hashable {
  case all
  case board(String)

  var name: String? {
    if case .board(let name) = self { return name }
    return nil
  }
}

struct InboxView: View {
  @State var requests: PhoneRequests
  /// No choice shows every board; the compact split view shows the Boards
  /// list only while nothing is chosen.
  @State private var choice: BoardChoice? = Fixture.boards ? nil : .all
  /// The app opens on All Boards; Back leads to the Boards list.
  @State private var column: NavigationSplitViewColumn = Fixture.boards ? .sidebar : .detail
  /// The Boards sidebar beside the requests, hidden while a request is open so
  /// that it fills the screen.
  @State private var columns: NavigationSplitViewVisibility =
    Fixture.open == nil ? .all : .detailOnly
  @State private var halfOpen = false
  /// The request screen open, by request id.
  @State private var path: [String] = Fixture.open.map { [$0.id] } ?? []
  @State private var refusing: Request?
  @Environment(\.horizontalSizeClass) private var sizeClass

  var body: some View {
    GeometryReader { geometry in
      // An open request fills the screen and lays out its own tabletop pose.
      if sizeClass == .regular && halfOpen && geometry.size.height > geometry.size.width
        && path.isEmpty
      {
        tabletop(geometry)
      } else {
        split
      }
    }
    .background(HingeReader(halfOpen: $halfOpen))
    .refuseAlert($refusing, requests: requests)
    .task { await requests.watch() }
    .onChange(of: requests.inbox.boards.map(\.name)) { _, names in
      // A board leaves the list once nothing waits in it.
      if let name = choice?.name, !names.contains(name) { choice = .all }
    }
    .onChange(of: requests.inbox.requests.map(\.id)) { _, ids in
      // A request answered here or elsewhere closes its screen.
      path.removeAll { !ids.contains($0) }
    }
    .onChange(of: path.isEmpty) { _, empty in columns = empty ? .all : .detailOnly }
  }

  private var board: String? { choice?.name }
  private var title: String { board ?? "All Boards" }
  private var shown: [Request] { requests.inbox.requests(in: board) }

  // MARK: Layouts

  /// The Boards list beside the requests, or behind Back in compact width.
  /// The inbox has no bar items, so the sidebar has no toggle.
  private var split: some View {
    NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $column) {
      BoardsList(inbox: requests.inbox, choice: $choice)
        .navigationTitle("Boards")
        .toolbar(removing: .sidebarToggle)
    } detail: {
      stack(.large)
    }
    .navigationSplitViewStyle(.balanced)
  }

  /// The requests above the fold and the Boards list below it. The fold is
  /// the middle of the whole screen, not of the safe area, whose top and
  /// bottom insets differ.
  private func tabletop(_ geometry: GeometryProxy) -> some View {
    let insets = geometry.safeAreaInsets
    let fold = (geometry.size.height + insets.top + insets.bottom) / 2 - insets.top
    return VStack(spacing: 0) {
      stack(.inline).frame(height: fold)
      BoardsPicker(inbox: requests.inbox, choice: $choice)
        .frame(height: geometry.size.height - fold)
    }
  }

  private func stack(_ mode: NavigationBarItem.TitleDisplayMode) -> some View {
    NavigationStack(path: $path) {
      RequestList(requests: requests, shown: shown, refusing: $refusing)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(mode)
        .navigationDestination(for: String.self) { id in
          if let request = requests.request(id) {
            RequestView(request: request, requests: requests)
          }
        }
    }
  }
}

/// The requests of one board, or of every board. It redraws every 30
/// seconds, so the subtitle says the list is out of date even when no read
/// succeeds, and a row's "Yesterday" moves on at midnight.
struct RequestList: View {
  let requests: PhoneRequests
  let shown: [Request]
  @Binding var refusing: Request?

  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      let stale = requests.isOutOfDate(now: context.date)
      List {
        Section {
          ForEach(shown) { request in
            NavigationLink(value: request.id) {
              RequestRow(request: request, now: context.date)
            }
            .swipeActions(edge: .trailing) {
              // Not a destructive role, which would remove the row before the
              // alert asks.
              Button {
                refusing = request
              } label: {
                Label("Refuse", systemImage: "xmark")
              }
              .tint(.red)
              .disabled(requests.sending.contains(request.id))
            }
          }
        } header: {
          // Before iOS 26 there is no navigation subtitle, so the list says it.
          if #unavailable(iOS 26), let text = subtitle(stale: stale) {
            Text(text)
          }
        } footer: {
          if stale {
            Text(
              "Your Mac shares new requests while it is awake and Board is open on it. Pull down to try again."
            )
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
          }
        }
      }
      .listStyle(.plain)
      .overlay {
        if shown.isEmpty {
          ContentUnavailableView(
            "No Requests", systemImage: "tray",
            description: Text("When a plugin asks before it acts, its request appears here."))
        }
      }
      .subtitle(subtitle(stale: stale))
    }
    .refreshable { await requests.refresh() }
  }

  /// The count, or how old the list is when the Mac has stopped sharing.
  private func subtitle(stale: Bool) -> String? {
    if stale, let shared = requests.shared {
      let today = Calendar.current.isDateInToday(shared)
      return
        "Mac last shared requests at \(shared.formatted(date: today ? .omitted : .abbreviated, time: .shortened))"
    }
    return shown.isEmpty ? nil : "\(shown.count) Waiting"
  }
}

extension View {
  /// The navigation subtitle, on iOS 26 and later. An empty one shows
  /// nothing, and keeps the list's identity when the count goes.
  @ViewBuilder func subtitle(_ text: String?) -> some View {
    if #available(iOS 26, *) {
      navigationSubtitle(text ?? "")
    } else {
      self
    }
  }
}

struct RequestRow: View {
  let request: Request
  var now = Date()

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline) {
        Text(request.name).font(.headline).lineLimit(2)
        Spacer(minLength: 8)
        Text(askedLabel(request.asked, now: now)).font(.subheadline).foregroundStyle(.secondary)
      }
      Text(request.sentence).font(.subheadline)
      Text(request.boardName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
    }
  }
}

/// The Boards column: All Boards, then each board with requests waiting. It
/// is a sidebar beside the requests, and an inset grouped screen behind Back.
struct BoardsList: View {
  let inbox: Inbox
  @Binding var choice: BoardChoice?
  @Environment(\.horizontalSizeClass) private var sizeClass

  var body: some View {
    let list = List(selection: $choice) {
      Section {
        NavigationLink(value: BoardChoice.all) {
          row("All Boards", "tray.2", inbox.requests.count)
        }
      }
      Section {
        ForEach(inbox.boards, id: \.name) { board in
          NavigationLink(value: BoardChoice.board(board.name)) {
            row(board.name, "folder", board.count)
          }
        }
      } header: {
        Text("Boards")
      } footer: {
        Text(
          "A board is named by its git remote. A board appears here while it has requests waiting.")
      }
    }
    if sizeClass == .regular {
      list.listStyle(.sidebar)
    } else {
      list.listStyle(.insetGrouped)
    }
  }

  /// The count before the chevron, as Mail shows it. A list badge would
  /// follow the chevron in an inset grouped list.
  private func row(_ name: String, _ symbol: String, _ count: Int) -> some View {
    HStack {
      Label(name, systemImage: symbol)
      Spacer()
      Text("\(count)").foregroundStyle(.secondary)
    }
  }
}

/// The Boards list on the lower half in the tabletop pose, with a checkmark
/// on the chosen board, as in a Settings picker.
struct BoardsPicker: View {
  let inbox: Inbox
  @Binding var choice: BoardChoice?

  var body: some View {
    List {
      Section("Boards") {
        row(.all, "All Boards", "tray.2", inbox.requests.count)
        ForEach(inbox.boards, id: \.name) { board in
          row(.board(board.name), board.name, "folder", board.count)
        }
      }
    }
    .listStyle(.insetGrouped)
  }

  private func row(_ value: BoardChoice, _ name: String, _ symbol: String, _ count: Int)
    -> some View
  {
    Button {
      choice = value
    } label: {
      HStack {
        Label(name, systemImage: symbol)
        Spacer()
        Text("\(count)").foregroundStyle(.secondary)
        Image(systemName: "checkmark").foregroundStyle(.tint).opacity(choice == value ? 1 : 0)
      }
    }
    .foregroundStyle(.primary)
  }
}

#Preview("Inbox") { InboxView(requests: PhoneRequests(preview: PreviewRequests.all)) }
#Preview("Empty") { InboxView(requests: PhoneRequests(preview: [])) }
#Preview("Out of date") {
  InboxView(
    requests: PhoneRequests(
      preview: PreviewRequests.all, shared: Date().addingTimeInterval(-3600)))
}
